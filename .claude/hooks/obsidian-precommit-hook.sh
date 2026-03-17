#!/usr/bin/env bash
# PreToolUse hook (Bash matcher): BLOCK git commit unless Obsidian project file was updated
# Exit 2 = block the tool call

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
    # Check if any obsidian/Projects/*.md file has been modified in this worktree
    CHANGED=$(git diff --name-only HEAD 2>/dev/null | grep '^obsidian/Projects/.*\.md$')
    STAGED=$(git diff --cached --name-only 2>/dev/null | grep '^obsidian/Projects/.*\.md$')
    UNTRACKED=$(git ls-files --others --exclude-standard 2>/dev/null | grep '^obsidian/Projects/.*\.md$')

    if [ -n "$CHANGED" ] || [ -n "$STAGED" ] || [ -n "$UNTRACKED" ]; then
        # Project file was touched — allow commit
        exit 0
    fi

    # List existing projects so the agent can pick one or decide to create new
    EXISTING=$(ls obsidian/Projects/*.md 2>/dev/null | xargs -I{} basename {} .md | sed 's/^/  - /')

    cat >&2 <<EOF
BLOCKED: No Obsidian project file updated.

Existing projects:
${EXISTING:-  (none)}

If one of these matches your work, update it:
  1. Add a dated entry under ## Log with what changed
  2. Update ## Current State if the project status shifted
  3. Update frontmatter (status, branch, pr) if needed

If NONE match, create a new project file:
  1. Write obsidian/Projects/<Project Name>.md with this frontmatter:
     ---
     status: in-progress
     priority: P1
     branch: $(git branch --show-current 2>/dev/null || echo "")
     pr:
     started: "$(date +%Y-%m-%d)"
     ---
  2. Fill in ## Current State, ## Key Files, and ## Log

Do NOT retry the commit until you have created or updated a project file.
EOF
    exit 2
fi
