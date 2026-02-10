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

require_token() {
  local token="$1"
  grep -Fq -- "$token" "$DOC" || fail "workflow contract missing required slice-review token: $token"
}

require_token "### 9.2 Slice completion"
require_token "~/.agents/skills/thinking-review-expert/skill.md"
require_token "artifacts/slice_reviews/<slice_id>/thinking_review.md"
require_token "artifacts/slice_reviews/_template/thinking_review.md"
require_token "Only then is the slice considered done."

# Template must keep canonical fields to avoid ad hoc artifacts.
for field in \
  "Slice ID:" \
  "Integration HEAD:" \
  "Skill Path: ~/.agents/skills/thinking-review-expert/skill.md" \
  "## Findings" \
  "## Final Disposition" \
  "Ready To Close Slice: YES/NO"; do
  grep -Fq -- "$field" "$TEMPLATE" || fail "slice review template missing field: $field"
done

echo "PASS: slice completion review guard"
