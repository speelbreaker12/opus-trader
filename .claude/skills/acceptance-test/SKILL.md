---
name: acceptance-test
description: Generate acceptance tests from contract requirements.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat SKILLS/acceptance-test.md || echo "ERROR: SKILLS/acceptance-test.md not found"`
