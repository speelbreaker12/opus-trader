---
name: grill
description: Adversarial plan interview — stress-test decisions until every branch is resolved.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: grill skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/grill.md"; if [ ! -r "$FILE" ]; then echo "ERROR: grill skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
