#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/story_review_equivalence_check.sh"
MATRIX="$ROOT/plans/story_review_equivalence_matrix.json"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local out=""
  set +e
  out="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$out" | grep -Fq "$pattern" || fail "$label missing expected pattern '$pattern'"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
[[ -f "$MATRIX" ]] || fail "missing matrix file: $MATRIX"

ok_output="$("$SCRIPT" "$MATRIX")"
printf '%s\n' "$ok_output" | grep -Fq "PASS: story review equivalence matrix" || fail "missing pass output"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

missing_id_matrix="$tmp_dir/missing_id.json"
jq '[ .[] | select(.id != "codex_two_reviews") ]' "$MATRIX" > "$missing_id_matrix"
expect_fail "missing id matrix" "STORY_REVIEW_EQUIVALENCE_DRIFT" "$SCRIPT" "$missing_id_matrix"

duplicate_matrix="$tmp_dir/duplicate.json"
jq '. + [.[0]]' "$MATRIX" > "$duplicate_matrix"
expect_fail "duplicate id matrix" "duplicate ids" "$SCRIPT" "$duplicate_matrix"

echo "PASS: story_review_equivalence_check"
