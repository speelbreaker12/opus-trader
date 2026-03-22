---
name: main-recovery
description: Diagnose and recover abnormal states on main — diverged, dirty, accidental commits, stuck rebase/merge.
context: fork
allowed-tools: ["Read", "Glob", "Grep", "Bash"]
---

!`REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: main-recovery skill: unable to determine repository root."; exit 1; }; FILE="$REPO_ROOT/SKILLS/main-recovery.md"; if [ ! -r "$FILE" ]; then echo "ERROR: main-recovery skill: markdown file not found at '$FILE'."; exit 1; fi; cat "$FILE"`
