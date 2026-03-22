---
name: push-pr
description: Refresh branch, push, and create or update PR. No code edits.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: push-pr skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/push-pr.md"; if [ ! -r "$FILE" ]; then echo "ERROR: push-pr skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
