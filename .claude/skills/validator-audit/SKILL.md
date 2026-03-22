---
name: validator-audit
description: Validator completeness and gap audit.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: validator-audit skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/validator-audit.md"; if [ ! -r "$FILE" ]; then echo "ERROR: validator-audit skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
