#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): delegate Obsidian commit enforcement to the
# shared repo guard. Exit 2 = block the tool call.
#
# This hook only fires when the command IS a git commit (not when git commit
# appears as part of a chained command like "git add && git commit").
# The git pre-commit hook (.githooks/pre-commit) handles enforcement for
# actual commit execution — this hook is a pre-flight check.

set -euo pipefail

INPUT=$(cat)

COMMAND=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

# Only match when the FINAL command in the chain is git commit.
# Split on && / ; / || and check the last segment.
# This prevents blocking 'git add . && git commit' at the add stage.
last_segment="$(echo "$COMMAND" | sed 's/.*[;&|]\{1,2\}//' | xargs)"
if ! echo "$last_segment" | grep -qE '^git commit( |$)'; then
  # Also check: is the ENTIRE command just a git commit?
  if ! echo "$COMMAND" | grep -qE '^[[:space:]]*git commit( |$)'; then
    exit 0
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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
