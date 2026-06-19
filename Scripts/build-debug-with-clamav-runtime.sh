#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="${CLAMGUI_DERIVED_DATA:-/private/tmp/clamgui-derived}"
source "$project_root/Scripts/clamav-development.sh"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [clamav-prefix]" >&2
  exit 64
fi

clamav_prefix="$(resolve_clamav_prefix "${1:-}" || true)"
if [[ -z "$clamav_prefix" ]]; then
  echo "error: Homebrew ClamAV was not found. Install it with: brew install clamav" >&2
  exit 69
fi

"$project_root/Scripts/check-development-environment.sh" "$clamav_prefix"

xcodebuild \
  -project "$project_root/ClamGUI.xcodeproj" \
  -scheme ClamGUI \
  -configuration Debug \
  -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=NO \
  "SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG CLAMGUI_SCRIPTED_BUILD" \
  build

app_bundle="$derived_data/Build/Products/Debug/ClamGUI.app"
"$project_root/Scripts/package-clamav-runtime.sh" "$app_bundle" "$clamav_prefix"
"$project_root/Scripts/verify-clamav-runtime.sh" "$app_bundle"

echo "Built packaged debug app:"
echo "  $app_bundle"
