---
name: pre-commit
description: Pre-commit safety gate checks.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: pre-commit skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/pre-commit.md"; if [ ! -r "$FILE" ]; then echo "ERROR: pre-commit skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
