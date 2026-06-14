#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
app_executable="$app_bundle/Contents/MacOS/ClamGUI"
clamav_prefix="${CLAMAV_PREFIX:-${HOMEBREW_PREFIX:-/opt/homebrew}}"
smoke_home="$(mktemp -d "${TMPDIR:-/tmp}/clamgui-smoke-home.XXXXXX")"
smoke_db="$smoke_home/Library/Application Support/ClamGUI/Database"

cleanup() {
  rm -rf "$smoke_home"
}
trap cleanup EXIT

"$project_root/Scripts/build-debug-with-clamav-runtime.sh"

if [[ ! -x "$app_executable" ]]; then
  echo "error: app executable not found: $app_executable" >&2
  exit 66
fi

mkdir -p "$smoke_db"

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
  echo "error: no local ClamAV database files found for smoke test seeding" >&2
  exit 69
fi

find "$database_source" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) -exec cp -p {} "$smoke_db/" \;

HOME="$smoke_home" "$app_executable" --clamgui-smoke-test
