#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hash_utils="$repo_root/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$hash_utils" ]] || fail "hash utils not found at $hash_utils"

assert_uses_shared_hash_utils() {
  local script="$1"

  [[ -f "$script" ]] || fail "script not found: $script"
  grep -Fq 'plans/lib/hash_utils.sh' "$script" \
    || fail "$(basename "$script") must source plans/lib/hash_utils.sh"
  if grep -Eq '^[[:space:]]*(sha256_file|hash_file)\(\)[[:space:]]*\{' "$script"; then
    fail "$(basename "$script") still declares a local hash helper"
  fi
}

assert_uses_shared_hash_utils "$repo_root/plans/run_prd_auditor.sh"
assert_uses_shared_hash_utils "$repo_root/plans/prd_pipeline.sh"
assert_uses_shared_hash_utils "$repo_root/plans/prd_audit_check.sh"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

set +e
missing_hash="$(
  source "$hash_utils"
  sha256_file "$tmp_dir/does-not-exist"
)"
missing_rc=$?
set -e
[[ "$missing_rc" -eq 0 ]] || fail "sha256_file should return rc=0 for missing files"
[[ -z "$missing_hash" ]] || fail "sha256_file should return empty string for missing files"

echo "fixture" > "$tmp_dir/present.txt"
present_hash="$(
  source "$hash_utils"
  sha256_file "$tmp_dir/present.txt"
)"
[[ -n "$present_hash" ]] || fail "sha256_file should return a hash for existing files"

echo "test_prd_hash_utils_adoption.sh: ok"
