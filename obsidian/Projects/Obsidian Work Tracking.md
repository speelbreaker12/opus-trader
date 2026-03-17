---
status: done
priority: P1
branch: main
pr:
started: "2026-03-16"
---

## Current State
Complete. Obsidian-based project tracking now includes repo-level debrief enforcement in pre-commit, Claude-side hook delegation to the same shared guard, and a commit-aware debrief template, alongside the existing Templates and AGENTS instructions.

## Key Files
- obsidian/Templates/Project.md
- obsidian/Templates/Debrief.md
- .claude/hooks/obsidian-context-hook.sh
- .claude/hooks/obsidian-precommit-hook.sh
- .claude/settings.json
- .git/hooks/pre-commit
- AGENTS.md (Obsidian Project Tracking section)

## Debriefs
- [[Obsidian Work Tracking 2026-03-17 Debrief Guard]]

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
### 2026-03-17
- Enabled context7 plugin in .claude/settings.json
- Expanded AGENTS.md with Warp/Codex build/test/architecture instructions
- Added a repo-owned Obsidian commit guard that requires both a staged project note and a staged debrief, plus a project-note link to the staged debrief.
- Added regression coverage for the debrief guard and wired it into `.githooks/pre-commit`.
- Repointed `.claude/hooks/obsidian-precommit-hook.sh` to the shared guard so tool-time blocking matches repo pre-commit behavior.
- Updated the debrief template and AGENTS instructions so debriefs record commit hashes, using `pending` until the current commit exists.
