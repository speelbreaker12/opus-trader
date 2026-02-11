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

require_token() {
  local token="$1"
  grep -Fq -- "$token" "$DOC" || fail "workflow contract missing required findings-review token: $token"
}

require_token "## 6. Story loop (minimal, mandatory)"
require_token "~/.agents/skills/code-review-expert/SKILL.md"
require_token 'plans/code_review_expert_logged.sh <STORY_ID> --head "$REVIEW_SHA" --status COMPLETE'
require_token "artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md"
require_token "Turn top findings into failing tests first (red phase)."
require_token "Fix until those tests pass (green phase)."
require_token "./plans/verify.sh quick"

echo "PASS: story review findings guard"
