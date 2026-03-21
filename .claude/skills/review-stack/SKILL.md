---
name: review-stack
description: Full 7-skill review stack — pr-review → failure-mode → strategic → contract → validator-audit → devils-advocate → loss-risk-gate. Produces P0/P1/P2 verdict.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`cat "$(git rev-parse --show-toplevel)/SKILLS/review-stack.md"`
