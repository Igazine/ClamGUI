#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
smoke_home="$(mktemp -d "${TMPDIR:-/tmp}/clamgui-smoke-home.XXXXXX")"

usage() {
  echo "Usage: $0 [path-to-ClamGUI.app]" >&2
}

if [[ $# -gt 1 ]]; then
  usage
  exit 64
fi

cleanup() {
  rm -rf "$smoke_home"
}
trap cleanup EXIT

if [[ $# -eq 1 ]]; then
  app_bundle="$1"
else
  "$project_root/Scripts/build-debug-with-clamav-runtime.sh"
  app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
fi

app_executable="$app_bundle/Contents/MacOS/ClamGUI"

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
