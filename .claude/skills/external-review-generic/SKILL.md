---
name: external-review-generic
description: Run four generic external reviewers in parallel.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: external-review-generic skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/external-review-generic.md"; if [ ! -r "$FILE" ]; then echo "ERROR: external-review-generic skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
