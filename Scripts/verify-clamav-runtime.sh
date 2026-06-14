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

if [[ ! -d "$app_bundle/Contents" ]]; then
  echo "error: app bundle not found: $app_bundle" >&2
  exit 66
fi

required_files=(
  "$frameworks_dir/libclamav.12.dylib"
  "$frameworks_dir/libfreshclam.4.dylib"
  "$frameworks_dir/libclammspack.0.dylib"
  "$frameworks_dir/libssl.3.dylib"
  "$frameworks_dir/libcrypto.3.dylib"
  "$frameworks_dir/libpcre2-8.0.dylib"
  "$frameworks_dir/libjson-c.5.dylib"
  "$macos_dir/freshclam"
)

echo "Checking ClamAV runtime files..."
for file in "${required_files[@]}"; do
  if [[ ! -f "$file" ]]; then
    echo "error: missing runtime file: $file" >&2
    exit 70
  fi
done

echo "Checking code signatures..."
for file in "${required_files[@]}"; do
  codesign --verify "$file"
done

echo "Checking dynamic library load commands..."
for file in "${required_files[@]}"; do
  if otool -L "$file" | awk 'NR > 1 { print $1 }' | grep -E '^(/opt/homebrew|/usr/local)/' >/dev/null; then
    echo "error: Homebrew load command remains in $(basename "$file")" >&2
    otool -L "$file" >&2
    exit 71
  fi
done

echo "Checking bundled freshclam startup..."
"$macos_dir/freshclam" --version

echo "ClamAV runtime verification passed:"
echo "  $app_bundle"
