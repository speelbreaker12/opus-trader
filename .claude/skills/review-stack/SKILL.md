---
name: review-stack
description: Full 7-skill review stack — pr-review → failure-mode → strategic → contract → validator-audit → devils-advocate → loss-risk-gate. Produces P0/P1/P2 verdict.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`root_dir="$(git rev-parse --show-toplevel 2>/dev/null)" && cat "$root_dir/SKILLS/review-stack.md" || echo "Error: Could not locate SKILLS/review-stack.md; ensure you're in a git worktree with that file present."`
