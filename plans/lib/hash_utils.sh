#!/usr/bin/env bash

if [[ -n "${__HASH_UTILS_SOURCED:-}" ]]; then
  return 0
fi
__HASH_UTILS_SOURCED=1

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  return 1
}
