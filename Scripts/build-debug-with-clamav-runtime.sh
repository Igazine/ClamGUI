#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
clamav_prefix="${CLAMAV_PREFIX:-${HOMEBREW_PREFIX:-/opt/homebrew}}"

xcodebuild \
  -project "$project_root/ClamGUI.xcodeproj" \
  -scheme ClamGUI \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
"$project_root/Scripts/package-clamav-runtime.sh" "$app_bundle" "$clamav_prefix"
"$project_root/Scripts/verify-clamav-runtime.sh" "$app_bundle"

echo "Built packaged debug app:"
echo "  $app_bundle"
