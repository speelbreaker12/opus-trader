---
name: premortem
description: Pre-implementation safety analysis — 25 binary assertions, STOPLIGHT gate (GREEN/YELLOW/RED), Hard Gate table. Blocks implementation if RED.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: premortem skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/premortem.md"; if [ ! -r "$FILE" ]; then echo "ERROR: premortem skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
