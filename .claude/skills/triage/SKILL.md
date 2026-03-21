---
name: triage
description: Investigate bug, find root cause, file GH issue with TDD fix plan.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: triage skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/triage.md"; if [ ! -r "$FILE" ]; then echo "ERROR: triage skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
