---
name: contract-review
description: Fast fail-open safety filter for changes.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: contract-review skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/contract-review.md"; if [ ! -r "$FILE" ]; then echo "ERROR: contract-review skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
