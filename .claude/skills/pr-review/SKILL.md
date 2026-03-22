---
name: pr-review
description: General PR review checklist.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: pr-review skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/pr-review.md"; if [ ! -r "$FILE" ]; then echo "ERROR: pr-review skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
