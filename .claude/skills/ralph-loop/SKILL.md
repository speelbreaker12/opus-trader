---
name: ralph-loop
description: Run Ralph harness iterations.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: ralph-loop skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/ralph-loop.md"; if [ ! -r "$FILE" ]; then echo "ERROR: ralph-loop skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
