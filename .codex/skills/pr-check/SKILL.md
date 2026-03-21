---
name: pr-check
description: Review comments to merge-ready branch flow.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat SKILLS/pr-check.md || echo "ERROR: SKILLS/pr-check.md not found"`
