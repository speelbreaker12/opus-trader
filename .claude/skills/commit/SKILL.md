---
name: commit
description: Create a clean local commit in the correct worktree. No push, no PR.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat SKILLS/commit.md || echo "ERROR: SKILLS/commit.md not found"`
