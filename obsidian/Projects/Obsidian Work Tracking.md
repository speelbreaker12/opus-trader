---
status: in-progress
priority: P1
branch: workflow/obsidian-fixes
base: main
pr:
started: "2026-03-16"
scope_paths:
  - .codex/commands/**
  - .claude/commands/**
  - .claude/hooks/**
  - .claude/scripts/**
  - .claude/settings.json
  - .claude/skills/**
  - .githooks/**
  - AGENTS.md
  - SKILLS/**
  - docs/skills/index.md
  - docs/workflow-index.md
  - obsidian/**
  - plans/code_review_expert_guard.sh
  - plans/lib/obsidian_frontmatter.py
  - plans/obsidian_commit_guard.sh
  - plans/post_rebase_frontmatter_check.sh
  - plans/project_scope_guard.sh
  - plans/open_project_pr.sh
  - plans/tests/**
  - plans/verify_fork.sh
  - plans/worktree_commit_push.sh
  - plans/workflow_files_allowlist.txt
  - plans/workflow_verify.sh
  - plans/write_review_gate_marker.sh
  - scripts/setup_hooks.sh
---

## Current State
In progress. Obsidian debrief now acts as the default session handoff for normal project work, and the repo is adding Codex mirrors for `/commit` and `/push-pr` so the same workflow skills are available outside Claude-specific wrappers.

## Commits
- `pending` — 2026-03-19 — fix skills index validation (review-stack entries, command format)
- `e56b088e` — 2026-03-19 — update commit refs and runtime state
- `6d235f31` — 2026-03-19 — add /merge-cleanup skill, restructure skills index, add workflow index
- `b007c317` — 2026-03-19 — debrief template upgrade, workspace policy expansion, test fixture alignment
- `821fabe3` — 2026-03-19 — risk-class commit gates, shared frontmatter parser, context hook warnings

## Key Files
- .codex/commands/commit.md
- .codex/commands/push-pr.md
- obsidian/Templates/Project.md
- obsidian/Templates/Debrief.md
- .claude/hooks/obsidian-context-hook.sh
- .claude/hooks/obsidian-precommit-hook.sh
- .claude/settings.json
- .git/hooks/pre-commit
- AGENTS.md (Obsidian Project Tracking section)

## Debriefs
- [[Obsidian Work Tracking 2026-03-17 Post-Commit Dashboard Sync Notice]]
- [[Obsidian Work Tracking 2026-03-19 Workflow Skill Split]]
- [[Obsidian Work Tracking 2026-03-19 Guard Hardening]]
- [[Obsidian Work Tracking 2026-03-19 Codex Command Mirrors]]

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
### 2026-03-19
- Mirrored `/commit` and `/push-pr` into `.codex/commands/` so Codex can invoke the same repo-backed skills as Claude.
- Extended `plans/tests/test_review_command_wrappers.sh` to prove both Claude and Codex command wrappers point at the same `SKILLS/` source files.
