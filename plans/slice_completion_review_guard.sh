#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DOC="${WORKFLOW_CONTRACT_FILE:-specs/WORKFLOW_CONTRACT.md}"
TEMPLATE="artifacts/slice_reviews/_template/thinking_review.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$DOC" ]] || fail "missing workflow contract: $DOC"
[[ -f "$TEMPLATE" ]] || fail "missing slice review template: $TEMPLATE"

extract_slice_completion_section() {
  awk '
    /^### 9\.2 Slice completion/ {in_section=1; next}
    in_section && /^### / {exit}
    in_section && /^## / {exit}
    in_section {print}
  ' "$DOC"
}

require_token_in_slice_section() {
  local token="$1"
  grep -Fq -- "$token" <<<"$SLICE_SECTION" || fail "workflow contract missing required slice-review token in 9.2 Slice completion: $token"
}

grep -Fq -- "### 9.2 Slice completion" "$DOC" || fail "workflow contract missing required 9.2 Slice completion heading"

SLICE_SECTION="$(extract_slice_completion_section)"
[[ -n "$SLICE_SECTION" ]] || fail "workflow contract 9.2 Slice completion section is empty"

require_token_in_slice_section "~/.agents/skills/thinking-review-expert/SKILL.md"
require_token_in_slice_section "plans/thinking_review_logged.sh <slice_id> --head <integration_head_sha>"
require_token_in_slice_section "artifacts/slice_reviews/<slice_id>/thinking_review.md"
require_token_in_slice_section "artifacts/slice_reviews/_template/thinking_review.md"
require_token_in_slice_section "plans/slice_review_gate.sh <slice_id> --head <integration_head_sha>"
require_token_in_slice_section "plans/slice_completion_enforce.sh"
require_token_in_slice_section "Only then is the slice considered done."

# Template must keep canonical fields to avoid ad hoc artifacts.
for field in \
  "Slice ID:" \
  "Integration HEAD:" \
  "Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md" \
  "## Findings" \
  "## Final Disposition" \
  "Ready To Close Slice: YES/NO"; do
  grep -Fq -- "$field" "$TEMPLATE" || fail "slice review template missing field: $field"
done

echo "PASS: slice completion review guard"
