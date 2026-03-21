---
name: post-impl-audit
description: Post-implementation breaker audit.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: post-impl-audit skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/post-impl-audit.md"; if [ ! -r "$FILE" ]; then echo "ERROR: post-impl-audit skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
