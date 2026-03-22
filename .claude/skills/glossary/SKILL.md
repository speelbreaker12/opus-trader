---
name: glossary
description: Extract and maintain domain terminology glossary from codebase.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: glossary skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/glossary.md"; if [ ! -r "$FILE" ]; then echo "ERROR: glossary skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
