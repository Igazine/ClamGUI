#!/usr/bin/env bash
set -eo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
source "$project_root/Scripts/clamav-development.sh"

if [[ $# -gt 1 ]]; then
  echo "Usage: $0 [clamav-prefix]" >&2
  exit 64
fi

clamav_prefix="$(resolve_clamav_prefix "${1:-}" || true)"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "error: xcodebuild was not found. Install Xcode and select it with xcode-select." >&2
  exit 69
fi

if [[ -z "$clamav_prefix" ]]; then
  echo "error: Homebrew ClamAV was not found. Install it with: brew install clamav" >&2
  exit 69
fi

freshclam_path="$clamav_prefix/bin/freshclam"
libclamav_path="$clamav_prefix/lib/libclamav.dylib"

if [[ ! -x "$freshclam_path" ]]; then
  echo "error: freshclam was not found at $freshclam_path" >&2
  exit 69
fi

if [[ ! -f "$libclamav_path" && ! -f "$clamav_prefix/lib/libclamav.12.dylib" ]]; then
  echo "error: libclamav was not found under $clamav_prefix/lib" >&2
  exit 69
fi

database_directory="$(find_clamav_database_directory "$clamav_prefix" || true)"
if [[ -z "$database_directory" ]]; then
  brew_prefix="$(brew --prefix 2>/dev/null || true)"
  database_directory="${brew_prefix:-/opt/homebrew}/var/lib/clamav"
  echo "error: ClamAV signature databases were not found." >&2
  echo "Create and populate them with:" >&2
  echo "  mkdir -p \"$database_directory\"" >&2
  echo "  \"$freshclam_path\" --datadir=\"$database_directory\"" >&2
  exit 69
fi

echo "Development environment is ready:"
echo "  Xcode: $(xcodebuild -version | head -n 1)"
echo "  ClamAV: $clamav_prefix"
echo "  Signatures: $database_directory"
