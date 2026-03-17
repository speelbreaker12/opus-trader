#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): delegate Obsidian commit enforcement to the
# shared repo guard. Exit 2 = block the tool call.

set -euo pipefail

INPUT=$(cat)
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

COMMAND=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

if echo "$COMMAND" | grep -qE '(^|[;&|[:space:]])git commit( |$)'; then
    if [[ ! -x "$ROOT/plans/obsidian_commit_guard.sh" ]]; then
        cat >&2 <<EOF
BLOCKED: Missing shared Obsidian commit guard.

Expected executable:
  $ROOT/plans/obsidian_commit_guard.sh
EOF
        exit 2
    fi

    if ! output="$(bash "$ROOT/plans/obsidian_commit_guard.sh" 2>&1)"; then
        printf '%s\n' "$output" >&2
        exit 2
    fi
fi
