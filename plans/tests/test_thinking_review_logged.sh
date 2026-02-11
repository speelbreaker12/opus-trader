#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/thinking_review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

slice_id="slice-1"
out_root="$tmp_dir/slice_reviews"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

"$SCRIPT" "$slice_id" --head "$head_sha" --branch run/slice1-clean --stories S1-001,S1-002 --reviewer tester --out-root "$out_root" >/dev/null

review_file="$out_root/$slice_id/thinking_review.md"
[[ -f "$review_file" ]] || fail "thinking review artifact missing"

grep -Fxq -- "- Slice ID: $slice_id" "$review_file" || fail "missing slice id line"
grep -Fxq -- "- Integration HEAD: $head_sha" "$review_file" || fail "missing integration head line"
grep -Fxq -- "- Ready To Close Slice: NO" "$review_file" || fail "default disposition should be NO"

expect_fail "no overwrite without force" "artifact already exists" \
  "$SCRIPT" "$slice_id" --head "$head_sha" --out-root "$out_root"

"$SCRIPT" "$slice_id" --head "$head_sha" --out-root "$out_root" --force >/dev/null
grep -Fxq -- "- Integration HEAD: $head_sha" "$review_file" || fail "overwrite lost head metadata"

echo "PASS: thinking review logger fixtures"
