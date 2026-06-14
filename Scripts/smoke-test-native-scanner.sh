#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
app_executable="$app_bundle/Contents/MacOS/ClamGUI"

"$project_root/Scripts/build-debug-with-clamav-runtime.sh"

if [[ ! -x "$app_executable" ]]; then
  echo "error: app executable not found: $app_executable" >&2
  exit 66
fi

"$app_executable" --clamgui-smoke-test
