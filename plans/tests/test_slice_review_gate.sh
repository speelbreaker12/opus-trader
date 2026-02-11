#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/slice_review_gate.sh"

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

[[ -x "$GATE" ]] || fail "missing executable gate: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

slice_id="slice-1"
head_sha="abc123def456"
review_dir="$tmp_dir/$slice_id"
review_file="$review_dir/thinking_review.md"
mkdir -p "$review_dir"

cat > "$review_file" <<EOF
# Thinking Review (Slice Close)

- Slice ID: $slice_id
- Integration HEAD: $head_sha
- Skill Path: ~/.agents/skills/thinking-review-expert/skill.md
- Reviewer: tester
- Timestamp (UTC): 2026-02-10T00:00:00Z

## Findings
- Blocking: none

## Final Disposition
- Ready To Close Slice: YES
- Follow-ups: none
EOF

"$GATE" "$slice_id" --head "$head_sha" --artifacts-root "$tmp_dir" >/dev/null

sed -i.bak "s/- Ready To Close Slice: YES/- Ready To Close Slice: NO/" "$review_file"
rm -f "$review_file.bak"
expect_fail "ready-to-close must be yes" "must assert ready-to-close YES" \
  "$GATE" "$slice_id" --head "$head_sha" --artifacts-root "$tmp_dir"

echo "PASS: slice review gate fixtures"
