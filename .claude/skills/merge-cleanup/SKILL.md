---
name: merge-cleanup
description: Merge single PR, sync main, remove worktree, delete branch, update Obsidian.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: merge-cleanup skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/merge-cleanup.md"; if [ ! -r "$FILE" ]; then echo "ERROR: merge-cleanup skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
