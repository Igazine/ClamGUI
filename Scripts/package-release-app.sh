#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-release-derived}"
clamav_prefix="${CLAMAV_PREFIX:-${HOMEBREW_PREFIX:-/opt/homebrew}}"
artifacts_dir="${CLAMGUI_ARTIFACTS_DIR:-$project_root/build/Artifacts}"
staging_dir="$artifacts_dir/Release"
dmg_path="$artifacts_dir/ClamGUI.dmg"

usage() {
  echo "Usage: $0 [clamav-prefix]" >&2
  echo "Example: $0 /opt/homebrew" >&2
}

if [[ $# -gt 1 ]]; then
  usage
  exit 64
fi

if [[ $# -eq 1 ]]; then
  clamav_prefix="$1"
fi

xcodebuild \
  -project "$project_root/ClamGUI.xcodeproj" \
  -scheme ClamGUI \
  -configuration Release \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  build

app_bundle="$derived_data/Build/Products/Release/ClamGUI.app"

"$project_root/Scripts/package-clamav-runtime.sh" "$app_bundle" "$clamav_prefix"
"$project_root/Scripts/verify-clamav-runtime.sh" "$app_bundle"

rm -rf "$staging_dir"
mkdir -p "$staging_dir"
ditto "$app_bundle" "$staging_dir/ClamGUI.app"

rm -f "$dmg_path"
hdiutil create \
  -volname "ClamGUI" \
  -srcfolder "$staging_dir" \
  -ov \
  -format UDZO \
  "$dmg_path"

echo "Packaged release artifacts:"
echo "  App: $staging_dir/ClamGUI.app"
echo "  DMG: $dmg_path"
