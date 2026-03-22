---
name: verify
description: Verification run and failure explanation workflow.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: verify skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/verify.md"; if [ ! -r "$FILE" ]; then echo "ERROR: verify skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
