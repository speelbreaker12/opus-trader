---
name: failure-mode-review
description: Implementation-level failure path analysis.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: failure-mode-review skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/failure-mode-review.md"; if [ ! -r "$FILE" ]; then echo "ERROR: failure-mode-review skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
