---
name: design-interface
description: Design It Twice — parallel sub-agents generate radically different interface designs for comparison.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: design-interface skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/design-interface.md"; if [ ! -r "$FILE" ]; then echo "ERROR: design-interface skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
