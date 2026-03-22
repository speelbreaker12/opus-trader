---
name: contract-audit-full
description: Exhaustive contract coverage and conflict audit.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: contract-audit-full skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/contract-audit-full.md"; if [ ! -r "$FILE" ]; then echo "ERROR: contract-audit-full skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
