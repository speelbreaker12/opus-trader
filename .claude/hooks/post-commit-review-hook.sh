#!/usr/bin/env bash
# PostToolUse hook: ENFORCE /code-review-expert after every git commit
# Exit 2 blocks Claude from proceeding until it handles this output.

INPUT=$(cat)

COMMAND=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" 2>/dev/null || echo "")

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git commit( |$)'; then
    cat >&2 <<'EOF'
ENFORCEMENT: git commit detected.
You MUST invoke the /code-review-expert skill NOW.
Do NOT call any other tool. Do NOT write any other response.
Invoke /code-review-expert immediately — this is mandatory, not optional.
EOF
    exit 2
fi
