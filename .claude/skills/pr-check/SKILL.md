---
name: pr-check
description: Review comments to merge-ready branch flow.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: pr-check skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/pr-check.md"; if [ ! -r "$FILE" ]; then echo "ERROR: pr-check skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
