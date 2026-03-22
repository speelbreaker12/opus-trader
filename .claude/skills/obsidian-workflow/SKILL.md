---
name: obsidian-workflow
description: Use when starting a new session in this repo or updating Obsidian project/debrief tracking for the current task
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: obsidian-workflow skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/obsidian-workflow.md"; if [ ! -r "$FILE" ]; then echo "ERROR: obsidian-workflow skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
