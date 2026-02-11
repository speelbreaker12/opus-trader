#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/pre_pr_review_gate.sh"

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
  if ! printf '%s\n' "$output" | grep -Fq -- "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story_root="$tmp_dir/story"
slice_root="$tmp_dir/slice_reviews"
story="S1-TEST"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

mkdir -p "$story_root/$story/code_review_expert"
review_file="$story_root/$story/code_review_expert/20260211T000000Z_review.md"
cat > "$review_file" <<EOF
# Code-review-expert findings

- Story: $story
- HEAD: $head_sha
- Timestamp (UTC): 2026-02-11T00:00:00Z
- Branch: test-branch
- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md
- Review Status: COMPLETE
- Title: test review

## Findings
- Blocking: none
- Major: none
- Medium: none

## Final Disposition
- Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
EOF

"$SCRIPT" "$story" --head "$head_sha" --artifacts-root "$story_root" >/dev/null

expect_fail "missing review artifact" "missing code-review-expert review artifact" \
  "$SCRIPT" "S1-MISSING" --head "$head_sha" --artifacts-root "$story_root"

draft_story="S1-DRAFT"
mkdir -p "$story_root/$draft_story/code_review_expert"
cat > "$story_root/$draft_story/code_review_expert/20260211T000001Z_review.md" <<EOF
- Story: $draft_story
- HEAD: $head_sha
- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md
- Review Status: DRAFT
EOF
expect_fail "draft review status" "review must be COMPLETE" \
  "$SCRIPT" "$draft_story" --head "$head_sha" --artifacts-root "$story_root"

placeholder_story="S1-PLACEHOLDER"
mkdir -p "$story_root/$placeholder_story/code_review_expert"
cat > "$story_root/$placeholder_story/code_review_expert/20260211T000002Z_review.md" <<EOF
- Story: $placeholder_story
- HEAD: $head_sha
- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md
- Review Status: COMPLETE
- Blocking: <none | summary>
EOF
expect_fail "placeholder findings" "contains unresolved placeholder" \
  "$SCRIPT" "$placeholder_story" --head "$head_sha" --artifacts-root "$story_root"

expect_fail "slice review missing" "missing slice thinking-review artifact" \
  "$SCRIPT" "$story" --head "$head_sha" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root"

mkdir -p "$slice_root/slice-1"
cat > "$slice_root/slice-1/thinking_review.md" <<EOF
# Thinking Review (Slice Close)

- Slice ID: slice-1
- Integration HEAD: $head_sha
- Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md
- Reviewer: tester
- Timestamp (UTC): 2026-02-11T00:00:00Z

## Scope
- Stories merged in this slice: S1-001,S1-002
- Branch reviewed: run/slice1-clean

## Findings
- Blocking: none
- Major: none
- Medium: none

## Final Disposition
- Ready To Close Slice: YES
- Follow-ups: none
EOF

"$SCRIPT" "$story" --head "$head_sha" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root" >/dev/null

echo "PASS: pre_pr_review_gate fixtures"
