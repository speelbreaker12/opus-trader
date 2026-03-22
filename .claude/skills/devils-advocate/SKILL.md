---
name: devils-advocate
description: Mutation-style test-the-tests review.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: devils-advocate skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/devils-advocate.md"; if [ ! -r "$FILE" ]; then echo "ERROR: devils-advocate skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
