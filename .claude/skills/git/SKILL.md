---
name: git
description: Branch, merge, and worktree discipline.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: git skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/git.md"; if [ ! -r "$FILE" ]; then echo "ERROR: git skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
