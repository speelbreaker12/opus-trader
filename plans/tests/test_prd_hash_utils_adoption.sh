#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
hash_utils="$repo_root/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$hash_utils" ]] || fail "hash_utils.sh not found at $hash_utils"

scripts=(
  "$repo_root/plans/run_prd_auditor.sh"
  "$repo_root/plans/prd_pipeline.sh"
  "$repo_root/plans/prd_audit_check.sh"
)

for script in "${scripts[@]}"; do
  [[ -f "$script" ]] || fail "missing script: $script"
  grep -Eq 'source .*lib/hash_utils\.sh' "$script" \
    || fail "expected $script to source hash_utils.sh"
  if grep -nE '^(sha256_file|hash_file)\(\)' "$script" >/dev/null; then
    fail "expected $script to stop declaring local hash helpers"
  fi
done

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

missing_hash="$(bash -c 'set -euo pipefail; source "$1"; sha256_file "$2"' _ "$hash_utils" "$tmp_dir/missing.txt")"
[[ -z "$missing_hash" ]] || fail "expected missing file hash to be empty"

echo "test_prd_hash_utils_adoption.sh: ok"
