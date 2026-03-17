---
status: done
priority: P1
branch: main
pr:
started: "2026-03-16"
---

## Current State
Complete. Obsidian-based project tracking with Templates, Bases-compatible frontmatter, Claude Code hooks, git pre-commit hook, and AGENTS.md instructions for Codex/all agents.

## Commits
- `pending` — 2026-03-17 — post-commit prints dashboard auto-sync status when `obsidian/Active Projects.md` changed.

## Key Files
- obsidian/Templates/Project.md
- obsidian/Templates/Debrief.md
- .claude/hooks/obsidian-context-hook.sh
- .claude/hooks/obsidian-precommit-hook.sh
- .claude/settings.json
- .git/hooks/pre-commit
- AGENTS.md (Obsidian Project Tracking section)

## Debriefs
- [[Obsidian Work Tracking 2026-03-17 Post-Commit Dashboard Sync Notice]]

## Log
### 2026-03-16
- Created vault structure: Projects/, Debriefs/, Templates/, archive/
- Created Project template with frontmatter (status, priority, branch, pr, started)
- Created Debrief template with TOC format (shipped, constraint, follow-up, rules)
- Seeded 4 project files from memory (Autoresearch, Tmatic, Execution Facade, Phase 1)
- Built obsidian-context-hook.sh — UserPromptSubmit hook, shows active projects every message
- Built obsidian-precommit-hook.sh — PreToolUse hook, blocks git commit unless project file updated
- Made precommit hook mandatory (exit 2), lists existing projects, includes inline template for new ones
- Registered both hooks in .claude/settings.json
- Added git pre-commit hook (.git/hooks/pre-commit) — blocks commit for ALL agents (Codex, Gemini, manual)
- Added Obsidian Project Tracking section to AGENTS.md — read on start, update before commit, create if missing
