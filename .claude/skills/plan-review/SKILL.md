---
name: plan-review
description: Implementation plan review checklist.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: plan-review skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/plan-review.md"; if [ ! -r "$FILE" ]; then echo "ERROR: plan-review skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
