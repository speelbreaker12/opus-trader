#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): Before git commit, remind agent to update Obsidian progress

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
    echo "OBSIDIAN PROGRESS REMINDER: You are about to commit."
    echo "Before proceeding:"
    echo "  1. Update the relevant obsidian/Projects/*.md file:"
    echo "     - Add a dated entry under ## Log with what changed"
    echo "     - Update ## Current State if the project status shifted"
    echo "     - Update frontmatter (status, branch, pr) if needed"
    echo "  2. If this is the last commit of a work session, write a debrief:"
    echo "     - Create obsidian/Debriefs/<Project> <date>.md using the Debrief template"
    echo "     - Fill: what shipped, constraint, follow-up, enforceable rules"
    echo "     - Link it from the project's ## Debriefs section"
    echo "If you already updated the project file in this session, proceed with the commit."
fi
