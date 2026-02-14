#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOC="${WORKFLOW_CONTRACT_FILE:-specs/WORKFLOW_CONTRACT.md}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "missing workflow contract: $DOC"

extract_story_loop_section() {
  awk '
    /^## 6\. Story loop \(minimal, mandatory\)/ {in_section=1; next}
    in_section && /^## / {exit}
    in_section {print}
  ' "$DOC"
}

require_token_in_story_loop() {
  local token="$1"
  grep -Fq -- "$token" <<<"$STORY_LOOP_SECTION" || fail "workflow contract missing required findings-review token in Story loop section: $token"
}

require_one_of_tokens_in_story_loop() {
  local found=0
  local token=""
  for token in "$@"; do
    if grep -Fq -- "$token" <<<"$STORY_LOOP_SECTION"; then
      found=1
      break
    fi
  done
  [[ "$found" -eq 1 ]] || fail "workflow contract missing required findings-review token set in Story loop section: $*"
}

grep -Fq -- "## 6. Story loop (minimal, mandatory)" "$DOC" || fail "workflow contract missing required Story loop heading"

STORY_LOOP_SECTION="$(extract_story_loop_section)"
[[ -n "$STORY_LOOP_SECTION" ]] || fail "workflow contract Story loop section is empty"

require_token_in_story_loop "~/.agents/skills/code-review-expert/SKILL.md"
require_token_in_story_loop 'plans/code_review_expert_logged.sh <STORY_ID> --head "$REVIEW_SHA" --status COMPLETE'
require_token_in_story_loop "artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md"
require_token_in_story_loop "Turn top findings into failing tests first (red phase)."
require_token_in_story_loop "Fix until those tests pass (green phase)."
require_one_of_tokens_in_story_loop "./plans/verify.sh quick" "plans/workflow_quick_step.sh <STORY_ID> <checkpoint>"

echo "PASS: story review findings guard"
