---
name: acceptance-test
description: Generate acceptance tests from contract requirements.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: acceptance-test skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/acceptance-test.md"; if [ ! -r "$FILE" ]; then echo "ERROR: acceptance-test skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
