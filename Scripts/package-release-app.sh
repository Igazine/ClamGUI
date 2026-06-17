#!/usr/bin/env bash
set -eo pipefail
export COPYFILE_DISABLE=1

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-release-derived}"
clamav_prefix="${CLAMAV_PREFIX:-${HOMEBREW_PREFIX:-/opt/homebrew}}"
artifacts_dir="${CLAMGUI_ARTIFACTS_DIR:-$project_root/build/Artifacts}"
staging_dir="$artifacts_dir/Release"
pkgroot_dir="$artifacts_dir/pkgroot"
pkg_path="$artifacts_dir/ClamGUI.pkg"

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
ditto --norsrc --noextattr --noqtn --noacl --nopersistRootless "$app_bundle" "$staging_dir/ClamGUI.app"

rm -rf "$pkgroot_dir"
mkdir -p "$pkgroot_dir/Applications"
ditto --norsrc --noextattr --noqtn --noacl --nopersistRootless "$app_bundle" "$pkgroot_dir/Applications/ClamGUI.app"
xattr -cr "$pkgroot_dir/Applications/ClamGUI.app" 2>/dev/null || true
find "$pkgroot_dir" -name "._*" -delete

rm -f "$pkg_path"
pkgbuild \
  --root "$pkgroot_dir" \
  --install-location "/" \
  --identifier "com.clamgui.app" \
  --version "1.0.0" \
  "$pkg_path"

echo "Packaged release artifacts:"
echo "  App: $staging_dir/ClamGUI.app"
echo "  PKG: $pkg_path"
