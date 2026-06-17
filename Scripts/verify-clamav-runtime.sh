#!/usr/bin/env bash
set -eo pipefail

usage() {
  echo "Usage: $0 /path/to/ClamGUI.app" >&2
}

if [[ $# -ne 1 ]]; then
  usage
  exit 64
fi

app_bundle="$1"
frameworks_dir="$app_bundle/Contents/Frameworks"
macos_dir="$app_bundle/Contents/MacOS"
database_dir="$app_bundle/Contents/Resources/Database"
app_executable="$macos_dir/ClamGUI"

if [[ ! -d "$app_bundle/Contents" ]]; then
  echo "error: app bundle not found: $app_bundle" >&2
  exit 66
fi

required_globs=(
  "$frameworks_dir/libclamav"*.dylib
  "$frameworks_dir/libfreshclam"*.dylib
  "$frameworks_dir/libclammspack"*.dylib
  "$frameworks_dir/libssl"*.dylib
  "$frameworks_dir/libcrypto"*.dylib
  "$frameworks_dir/libpcre2-8"*.dylib
  "$frameworks_dir/libjson-c"*.dylib
)

echo "Checking ClamAV runtime files..."
for pattern in "${required_globs[@]}"; do
  if ! compgen -G "$pattern" >/dev/null; then
    echo "error: missing runtime file matching: $pattern" >&2
    exit 70
  fi
done

if [[ ! -x "$macos_dir/freshclam" ]]; then
  echo "error: missing bundled freshclam executable: $macos_dir/freshclam" >&2
  exit 70
fi

runtime_files=("$macos_dir/freshclam")
if [[ -x "$app_executable" ]]; then
  runtime_files+=("$app_executable")
fi
while IFS= read -r file; do
  runtime_files+=("$file")
done < <(find "$frameworks_dir" -maxdepth 1 -type f -name "*.dylib" | sort)

signed_runtime_files=("$macos_dir/freshclam")
while IFS= read -r file; do
  signed_runtime_files+=("$file")
done < <(find "$frameworks_dir" -maxdepth 1 -type f -name "*.dylib" | sort)

echo "Checking code signatures..."
for file in "${signed_runtime_files[@]}"; do
  codesign --verify "$file"
done

echo "Checking dynamic library load commands..."
for file in "${runtime_files[@]}"; do
  if otool -L "$file" | awk 'NR > 1 { print $1 }' | grep -E '^(/opt/homebrew|/usr/local)/' >/dev/null; then
    echo "error: Homebrew load command remains in $(basename "$file")" >&2
    otool -L "$file" >&2
    exit 71
  fi
done

echo "Checking bundled freshclam startup..."
"$macos_dir/freshclam" --version

echo "Checking bundled signature databases..."
if [[ ! -d "$database_dir" ]] ||
   ! find "$database_dir" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) | grep -q .; then
  echo "error: bundled signature database files are missing from $database_dir" >&2
  exit 72
fi

echo "ClamAV runtime verification passed:"
echo "  $app_bundle"
