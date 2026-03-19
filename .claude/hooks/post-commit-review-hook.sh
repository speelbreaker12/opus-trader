#!/usr/bin/env bash
# PostToolUse hook: advisory reminder to run code-review-expert after commit.
# This is a REMINDER, not a gate. The real enforcement is in the pre-commit hook
# (code_review_expert_guard.sh) which checks attestation before allowing commit.
#
# Never exit 2 — that blocks the agent from proceeding, which causes more
# friction than value for docs/formatting/follow-up commits.

INPUT=$(cat)

COMMAND=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git commit( |$)'; then
    cat >&2 <<'EOF'
REMINDER: git commit detected. Consider running code-review-expert if this
was a significant implementation change. The /commit skill (step 3) describes
when review is required vs skippable by change class.
EOF
fi

# Always exit 0 — advisory only
exit 0
