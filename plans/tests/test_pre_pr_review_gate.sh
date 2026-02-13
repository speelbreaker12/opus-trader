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

write_valid_case() {
  local base="$1"
  local story="$2"
  local head_sha="$3"

  local story_dir="$base/$story"
  local self_dir="$story_dir/self_review"
  local codex_dir="$story_dir/codex"
  local kimi_dir="$story_dir/kimi"
  local code_review_expert_dir="$story_dir/code_review_expert"

  mkdir -p "$self_dir" "$codex_dir" "$kimi_dir" "$code_review_expert_dir"

  cat > "$self_dir/20260209T000000Z_self_review.md" <<EOF_SELF
# Self Review
Story: $story
HEAD: $head_sha
Decision: PASS
Checklist:
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF_SELF

  cat > "$codex_dir/20260209T000000Z_review.md" <<EOF_CODEX1
# Codex review
- Story: $story
- HEAD: $head_sha
EOF_CODEX1

  cat > "$codex_dir/20260209T000100Z_review.md" <<EOF_CODEX2
# Codex review (second pass)
- Story: $story
- HEAD: $head_sha
EOF_CODEX2

  cat > "$kimi_dir/20260209T000050Z_review.md" <<EOF_KIMI
# Kimi review
- Story: $story
- HEAD: $head_sha
EOF_KIMI

  cat > "$code_review_expert_dir/20260209T000080Z_review.md" <<EOF_EXPERT
# Code-review-expert findings
- Story: $story
- HEAD: $head_sha
- Review Status: COMPLETE
- Blocking: none
- Major: none
- Medium: none
EOF_EXPERT

  cat > "$story_dir/review_resolution.md" <<EOF_RES
Story: $story
HEAD: $head_sha
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Kimi final review file: kimi/20260209T000050Z_review.md
Codex final review file: codex/20260209T000100Z_review.md
Codex second review file: codex/20260209T000000Z_review.md
Code-review-expert final review file: code_review_expert/20260209T000080Z_review.md
EOF_RES
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story_root="$tmp_dir/story"
slice_root="$tmp_dir/slice_reviews"
story="S1-TEST"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

write_valid_case "$story_root" "$story" "$head_sha"

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" >/dev/null

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story-fix" --artifacts-root "$story_root" >/dev/null

expect_fail "missing story artifact" "missing self-review artifact" \
  "$SCRIPT" "S1-MISSING" --head "$head_sha" --branch "story/S1-MISSING/gate" --artifacts-root "$story_root"

expect_fail "invalid story id" "invalid STORY_ID value: ../escape" \
  "$SCRIPT" "../escape" --head "$head_sha" --branch "story/S1-TEST/gate" --artifacts-root "$story_root"

expect_fail "invalid slash story id" "invalid STORY_ID value: workflow/maintenance" \
  "$SCRIPT" "workflow/maintenance" --head "$head_sha" --branch "story/S1-TEST/gate" --artifacts-root "$story_root"

expect_fail "invalid branch format" "branch must be story-scoped" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "codex/$story/gate" --artifacts-root "$story_root"

expect_fail "branch/story mismatch" "story id mismatch" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/S9-999/gate" --artifacts-root "$story_root"

rm -f "$story_root/$story/kimi/20260209T000050Z_review.md"
expect_fail "story review gate failure propagates" "missing Kimi review artifact for HEAD" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root"

# Restore valid story artifacts for slice checks.
rm -rf "$story_root/$story"
write_valid_case "$story_root" "$story" "$head_sha"

expect_fail "slice review missing" "missing slice thinking-review artifact" \
  "$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root"

mkdir -p "$slice_root/slice-1"
cat > "$slice_root/slice-1/thinking_review.md" <<EOF_SLICE
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
EOF_SLICE

"$SCRIPT" "$story" --head "$head_sha" --branch "story/$story/gate" --artifacts-root "$story_root" --slice-id "slice-1" --slice-artifacts-root "$slice_root" >/dev/null

echo "PASS: pre_pr_review_gate fixtures"
