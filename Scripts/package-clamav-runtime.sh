#!/usr/bin/env bash
set -eo pipefail

usage() {
  echo "Usage: $0 /path/to/ClamGUI.app [clamav-prefix]" >&2
  echo "Example: $0 /tmp/Build/Products/Debug/ClamGUI.app /opt/homebrew" >&2
}

if [[ $# -lt 1 || $# -gt 2 ]]; then
  usage
  exit 64
fi

app_bundle="$1"
clamav_prefix="${2:-${CLAMAV_PREFIX:-${HOMEBREW_PREFIX:-/opt/homebrew}}}"

if [[ ! -d "$app_bundle/Contents" ]]; then
  echo "error: app bundle not found: $app_bundle" >&2
  exit 66
fi

frameworks_dir="$app_bundle/Contents/Frameworks"
macos_dir="$app_bundle/Contents/MacOS"
resources_dir="$app_bundle/Contents/Resources"
database_dir="$resources_dir/Database"
mkdir -p "$frameworks_dir" "$macos_dir" "$database_dir"

find_existing_file() {
  local candidate
  for candidate in "$@"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

freshclam_path="$(find_existing_file \
  "$clamav_prefix/bin/freshclam" \
  "/opt/homebrew/bin/freshclam" \
  "/usr/local/bin/freshclam")" || {
    echo "error: freshclam not found. Install ClamAV or pass a ClamAV prefix." >&2
    exit 69
  }

libclamav_path="$(find_existing_file \
  "$clamav_prefix/lib/libclamav.12.dylib" \
  "$clamav_prefix/lib/libclamav.dylib" \
  "/opt/homebrew/lib/libclamav.12.dylib" \
  "/opt/homebrew/lib/libclamav.dylib" \
  "/usr/local/lib/libclamav.12.dylib" \
  "/usr/local/lib/libclamav.dylib")" || {
    echo "error: libclamav not found. Install ClamAV or pass a ClamAV prefix." >&2
    exit 69
  }

database_source=""
for candidate in \
  "$clamav_prefix/var/lib/clamav" \
  "/opt/homebrew/var/lib/clamav" \
  "/usr/local/var/lib/clamav" \
  "$clamav_prefix/share/clamav" \
  "/opt/homebrew/share/clamav" \
  "/usr/local/share/clamav"; do
  if compgen -G "$candidate/*.c[lv]d" >/dev/null || compgen -G "$candidate/*.cud" >/dev/null; then
    database_source="$candidate"
    break
  fi
done

if [[ -z "$database_source" ]]; then
  echo "error: ClamAV database files not found. Run freshclam locally or pass a ClamAV prefix with databases." >&2
  exit 69
fi

find "$database_dir" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) -delete
find "$database_source" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) -exec cp -p {} "$database_dir/" \;

declare -a queue=("$libclamav_path" "$freshclam_path")
declare -a copied_sources=()
declare -a copied_destinations=()

is_bundle_dependency() {
  local path="$1"
  [[ "$path" == /opt/homebrew/* || "$path" == /usr/local/* ]]
}

find_prefixed_library() {
  local library_name="$1"
  local candidate

  for candidate in \
    "$clamav_prefix/lib/$library_name" \
    "/opt/homebrew/lib/$library_name" \
    "/usr/local/lib/$library_name"; do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

resolve_dependency_source() {
  local dependency="$1"

  if is_bundle_dependency "$dependency" && [[ -f "$dependency" ]]; then
    echo "$dependency"
    return 0
  fi

  if [[ "$dependency" == @rpath/* ]]; then
    find_prefixed_library "$(basename "$dependency")"
    return $?
  fi

  return 1
}

copy_runtime_file() {
  local source="$1"
  local destination="$2/$(basename "$source")"
  local copied_source
  local copied_destination

  for copied_source in "${copied_sources[@]}"; do
    if [[ "$copied_source" == "$source" ]]; then
      return 0
    fi
  done

  for copied_destination in "${copied_destinations[@]}"; do
    if [[ "$copied_destination" == "$destination" ]]; then
      copied_sources+=("$source")
      return 0
    fi
  done

  cp -p "$source" "$destination"
  chmod u+w "$destination"
  copied_sources+=("$source")
  copied_destinations+=("$destination")

  while IFS= read -r dependency; do
    dependency_source="$(resolve_dependency_source "$dependency" || true)"
    if [[ -n "$dependency_source" ]]; then
      queue+=("$dependency_source")
    fi
  done < <(otool -L "$source" | awk 'NR > 1 { print $1 }')
}

while ((${#queue[@]} > 0)); do
  item="${queue[0]}"
  queue=("${queue[@]:1}")

  if [[ "$(basename "$item")" == "freshclam" ]]; then
    copy_runtime_file "$item" "$macos_dir"
  else
    copy_runtime_file "$item" "$frameworks_dir"
  fi
done

for destination in "${copied_destinations[@]}"; do
  if [[ "$destination" == "$frameworks_dir"/* ]]; then
    install_name_tool -id "@rpath/$(basename "$destination")" "$destination" 2>/dev/null || true
  fi

  while IFS= read -r dependency; do
    dependency_source="$(resolve_dependency_source "$dependency" || true)"
    if [[ -n "$dependency_source" ]]; then
      if [[ "$destination" == "$frameworks_dir"/* ]]; then
        replacement="@loader_path/$(basename "$dependency")"
      else
        replacement="@loader_path/../Frameworks/$(basename "$dependency")"
      fi
      install_name_tool -change "$dependency" "$replacement" "$destination" 2>/dev/null || true
    fi
  done < <(otool -L "$destination" | awk 'NR > 1 { print $1 }')
done

for destination in "${copied_destinations[@]}"; do
  codesign --force --sign - "$destination" >/dev/null
done

echo "Packaged ClamAV runtime into $app_bundle"
echo "Copied files:"
printf '  %s\n' "${copied_destinations[@]}" | sort
echo "Copied database files:"
find "$database_dir" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) -print | sort | sed 's/^/  /'
