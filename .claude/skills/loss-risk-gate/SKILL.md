---
name: loss-risk-gate
description: Trading loss / profit-block economic safety review.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: loss-risk-gate skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/loss-risk-gate.md"; if [ ! -r "$FILE" ]; then echo "ERROR: loss-risk-gate skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
