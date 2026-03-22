---
name: slice-execute
description: Per-story implementation protocol.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: slice-execute skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/slice-execute.md"; if [ ! -r "$FILE" ]; then echo "ERROR: slice-execute skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
