#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/plans/story_review_findings_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$GUARD" ]] || fail "missing executable guard: $GUARD"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

valid_doc="$tmp_dir/workflow_contract_valid.md"
cat > "$valid_doc" <<'EOF'
## 6. Story loop (minimal, mandatory)
Use ~/.agents/skills/code-review-expert/SKILL.md
Save artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md
Turn top findings into failing tests first (red phase).
Fix until those tests pass (green phase).
Run ./plans/verify.sh quick again after fixes.
EOF

WORKFLOW_CONTRACT_FILE="$valid_doc" "$GUARD" >/dev/null

invalid_doc="$tmp_dir/workflow_contract_invalid.md"
cat > "$invalid_doc" <<'EOF'
## 6. Story loop (minimal, mandatory)
Use ~/.agents/skills/code-review-expert/SKILL.md
Save artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md
Fix until those tests pass (green phase).
Run ./plans/verify.sh quick again after fixes.
EOF

set +e
out="$(WORKFLOW_CONTRACT_FILE="$invalid_doc" "$GUARD" 2>&1)"
rc=$?
set -e

[[ $rc -ne 0 ]] || fail "expected guard to fail when required token is missing"
echo "$out" | grep -Fq "workflow contract missing required findings-review token" || fail "missing expected error message"

echo "PASS: story review findings guard fixtures"
