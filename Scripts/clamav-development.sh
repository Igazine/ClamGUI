#!/usr/bin/env bash

resolve_clamav_prefix() {
  local explicit_prefix="${1:-}"
  local candidate

  if [[ -n "$explicit_prefix" ]]; then
    printf '%s\n' "$explicit_prefix"
    return 0
  fi

  if [[ -n "${CLAMAV_PREFIX:-}" ]]; then
    printf '%s\n' "$CLAMAV_PREFIX"
    return 0
  fi

  if command -v brew >/dev/null 2>&1; then
    candidate="$(brew --prefix clamav 2>/dev/null || true)"
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  for candidate in /opt/homebrew/opt/clamav /usr/local/opt/clamav /opt/homebrew /usr/local; do
    if [[ -f "$candidate/lib/libclamav.dylib" || -f "$candidate/lib/libclamav.12.dylib" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}

find_clamav_database_directory() {
  local clamav_prefix="$1"
  local brew_prefix=""
  local candidate

  if command -v brew >/dev/null 2>&1; then
    brew_prefix="$(brew --prefix 2>/dev/null || true)"
  fi

  for candidate in \
    "$clamav_prefix/var/lib/clamav" \
    "${brew_prefix:+$brew_prefix/var/lib/clamav}" \
    "/opt/homebrew/var/lib/clamav" \
    "/usr/local/var/lib/clamav" \
    "$clamav_prefix/share/clamav" \
    "/opt/homebrew/share/clamav" \
    "/usr/local/share/clamav"; do
    [[ -n "$candidate" ]] || continue
    if compgen -G "$candidate/*.c[lv]d" >/dev/null || compgen -G "$candidate/*.cud" >/dev/null; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done

  return 1
}
