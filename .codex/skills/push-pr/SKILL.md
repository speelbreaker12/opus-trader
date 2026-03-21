---
name: push-pr
description: Refresh branch, push, and create or update PR. No code edits.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat SKILLS/push-pr.md || echo "ERROR: SKILLS/push-pr.md not found"`
