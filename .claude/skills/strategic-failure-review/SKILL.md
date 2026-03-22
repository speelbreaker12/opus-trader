---
name: strategic-failure-review
description: Systemic/architectural risk review.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: strategic-failure-review skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/strategic-failure-review.md"; if [ ! -r "$FILE" ]; then echo "ERROR: strategic-failure-review skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
