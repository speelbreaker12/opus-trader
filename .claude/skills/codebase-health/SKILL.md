---
name: codebase-health
description: Architecture friction audit — explore for shallow modules, coupling, facade drift, then propose deepening refactors.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash", "Agent"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: codebase-health skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/codebase-health.md"; if [ ! -r "$FILE" ]; then echo "ERROR: codebase-health skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
