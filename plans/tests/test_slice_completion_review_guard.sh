#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GUARD="$ROOT/plans/slice_completion_review_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$GUARD" ]] || fail "missing executable guard: $GUARD"

# Real contract + template should pass.
"$GUARD" >/dev/null

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

invalid_doc="$tmp_dir/workflow_contract_invalid.md"
cat > "$invalid_doc" <<'EOF_DOC'
### 9.2 Slice completion
Use ~/.agents/skills/thinking-review-expert/SKILL.md
Use artifacts/slice_reviews/<slice_id>/thinking_review.md
Use artifacts/slice_reviews/_template/thinking_review.md
Only then is the slice considered done.
EOF_DOC

set +e
out="$(WORKFLOW_CONTRACT_FILE="$invalid_doc" "$GUARD" 2>&1)"
rc=$?
set -e

[[ $rc -ne 0 ]] || fail "expected guard to fail when required token is missing"
echo "$out" | grep -Fq "workflow contract missing required slice-review token" || fail "missing expected error message"

scoped_doc="$tmp_dir/workflow_contract_scoped_invalid.md"
cat > "$scoped_doc" <<'EOF_DOC'
### 9.2 Slice completion
Use ~/.agents/skills/thinking-review-expert/SKILL.md
Use artifacts/slice_reviews/<slice_id>/thinking_review.md
Use artifacts/slice_reviews/_template/thinking_review.md
Only then is the slice considered done.

### 9.3 Outside section
Use plans/thinking_review_logged.sh <slice_id> --head <integration_head_sha>
Use plans/slice_review_gate.sh <slice_id> --head <integration_head_sha>
Use plans/slice_completion_enforce.sh
EOF_DOC

set +e
out_scoped="$(WORKFLOW_CONTRACT_FILE="$scoped_doc" "$GUARD" 2>&1)"
rc_scoped=$?
set -e

[[ $rc_scoped -ne 0 ]] || fail "expected guard to fail when required token is only outside 9.2 Slice completion section"
echo "$out_scoped" | grep -Fq "in 9.2 Slice completion" || fail "missing section-scoped failure message"

echo "PASS: slice completion review guard fixtures"
