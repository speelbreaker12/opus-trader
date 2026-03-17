---
status: done
priority: P1
branch: main
pr:
started: "2026-03-16"
---

## Current State
Complete. Obsidian-based project tracking now includes repo-level debrief enforcement in pre-commit, Claude-side hook delegation to the same shared guard, first-prompt project routing into the best matching Obsidian note, and a commit-aware debrief/template workflow with explicit commit history on the project page.

## Commits
- `pending` — 2026-03-17 — route first-session prompts to the best matching Obsidian project note, inject the matched note into hook context, wire router coverage into workflow verification, and add a shared guard reminder to include only the changes you made in the commit.
- `b1393d87` — 2026-03-17 — enforce linked debriefs in repo and Claude commit hooks.
- `788133f8` — 2026-03-17 — enable Context7 and expand AGENTS instructions for Warp/Codex workflows.
- `2a2f0fd1` — 2026-03-16 — enforce project tracking for all agents via git hook and AGENTS rules.
- `1bb74a97` — 2026-03-16 — enforce mandatory project tracking on commit.
- `872149dc` — 2026-03-16 — add the initial Obsidian project context hooks and work-tracking setup.

## Key Files
- obsidian/Templates/Project.md
- obsidian/Templates/Debrief.md
- .claude/hooks/obsidian-context-hook.sh
- .claude/hooks/obsidian-precommit-hook.sh
- plans/obsidian_commit_guard.sh
- plans/tests/test_obsidian_context_hook.sh
- .claude/settings.json
- .git/hooks/pre-commit
- AGENTS.md (Obsidian Project Tracking section)

## Debriefs
- [[Obsidian Work Tracking 2026-03-17 Debrief Guard]]
- [[Obsidian Work Tracking 2026-03-17 Context Router]]

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
- Replaced the passive context dump in `.claude/hooks/obsidian-context-hook.sh` with first-prompt project routing based on the user message, including explicit single-match, ambiguous-match, and no-match response instructions.
- Added `plans/tests/test_obsidian_context_hook.sh` and wired it into workflow verification and allowlist coverage.
- Updated the shared Obsidian commit guard to remind blocked commits to include only the changes made in the commit.
- Added a `## Commits` section near the top of this project note and updated the project template/AGENTS guidance so future project pages keep a date/hash/summary history.
