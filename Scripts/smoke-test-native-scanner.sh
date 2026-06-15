#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
app_executable="$app_bundle/Contents/MacOS/ClamGUI"
smoke_home="$(mktemp -d "${TMPDIR:-/tmp}/clamgui-smoke-home.XXXXXX")"

cleanup() {
  rm -rf "$smoke_home"
}
trap cleanup EXIT

"$project_root/Scripts/build-debug-with-clamav-runtime.sh"

if [[ ! -x "$app_executable" ]]; then
  echo "error: app executable not found: $app_executable" >&2
  exit 66
fi

HOME="$smoke_home" "$app_executable" --clamgui-smoke-test

smoke_db="$smoke_home/Library/Application Support/ClamGUI/Database"
if ! find "$smoke_db" -maxdepth 1 -type f \( -name "*.cvd" -o -name "*.cld" -o -name "*.cud" \) | grep -q .; then
  echo "error: app did not bootstrap signature databases into $smoke_db" >&2
  exit 73
fi
