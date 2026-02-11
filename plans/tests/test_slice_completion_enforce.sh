#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/slice_completion_enforce.sh"

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

prd_pending="$tmp_dir/prd_pending.json"
cat > "$prd_pending" <<'EOF_PENDING'
{
  "items": [
    {"id":"S1-001","slice":1,"passes":true},
    {"id":"S1-002","slice":1,"passes":false}
  ]
}
EOF_PENDING

prd_all_pass="$tmp_dir/prd_all_pass.json"
cat > "$prd_all_pass" <<'EOF_ALL_PASS'
{
  "items": [
    {"id":"S1-001","slice":1,"passes":true},
    {"id":"S1-002","slice":1,"passes":true}
  ]
}
EOF_ALL_PASS

# Case 1: non-slice integration branch should skip.
out1="$($SCRIPT --branch feature/test --head deadbeef --prd-file "$prd_pending" --artifacts-root "$tmp_dir/slice_reviews")"
printf '%s\n' "$out1" | grep -Fq "SKIP: slice completion enforcement not applicable" || fail "expected branch skip"

# Case 2: slice integration branch with pending stories should skip.
out2="$($SCRIPT --branch run/slice1-clean --head deadbeef --prd-file "$prd_pending" --artifacts-root "$tmp_dir/slice_reviews")"
printf '%s\n' "$out2" | grep -Fq "SKIP: slice=1 has 1 stories with passes!=true" || fail "expected pending-story skip"

# Case 3: fully-passed slice must fail if thinking review artifact is missing.
expect_fail "missing thinking review artifact" "missing slice thinking-review artifact" \
  "$SCRIPT" --branch run/slice1-clean --head deadbeef --prd-file "$prd_all_pass" --artifacts-root "$tmp_dir/slice_reviews"

# Case 4: fully-passed slice succeeds when thinking review artifact is present and ready.
review_dir="$tmp_dir/slice_reviews/slice1"
mkdir -p "$review_dir"
cat > "$review_dir/thinking_review.md" <<'EOF_REVIEW'
# Thinking Review (Slice Close)

- Slice ID: slice1
- Integration HEAD: deadbeef
- Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md
- Reviewer: tester
- Timestamp (UTC): 2026-02-10T00:00:00Z

## Findings
- Blocking: none

## Final Disposition
- Ready To Close Slice: YES
- Follow-ups: none
EOF_REVIEW

out4="$($SCRIPT --branch run/slice1-clean --head deadbeef --prd-file "$prd_all_pass" --artifacts-root "$tmp_dir/slice_reviews")"
printf '%s\n' "$out4" | grep -Fq "PASS: slice completion enforcement passed" || fail "expected pass output"

echo "PASS: slice completion enforcement fixtures"
