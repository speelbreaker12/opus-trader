---
name: hotfix
description: Triage and fix shared baseline bugs — dedicated branch from main, merge first, refresh affected branches.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: hotfix skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/hotfix.md"; if [ ! -r "$FILE" ]; then echo "ERROR: hotfix skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
