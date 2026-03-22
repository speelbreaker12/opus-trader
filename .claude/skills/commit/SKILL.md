---
name: commit
description: Create a clean local commit in the correct worktree. No push, no PR.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: commit skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/commit.md"; if [ ! -r "$FILE" ]; then echo "ERROR: commit skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
