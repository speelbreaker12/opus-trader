---
name: glossary
description: Extract and maintain domain terminology glossary from codebase.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat SKILLS/glossary.md || echo "ERROR: SKILLS/glossary.md not found"`
