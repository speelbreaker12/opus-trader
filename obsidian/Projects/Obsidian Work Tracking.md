---
status: in-progress
priority: P1
branch: workflow/obsidian-fixes
base: main
pr:
started: "2026-03-16"
scope_paths:
  - .claude/commands/**
  - .claude/hooks/**
  - .claude/scripts/**
  - .claude/settings.json
  - .claude/skills/**
  - .githooks/**
  - AGENTS.md
  - SKILLS/**
  - docs/skills/index.md
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
In progress. Replacing size-based commit tiers (trivial/light/full) with risk-class classification (docs_only/obsidian_only/non_critical/critical). Extracting shared frontmatter parser to `plans/lib/obsidian_frontmatter.py` to eliminate 3 duplicate implementations. Adding worktree-mismatch and merged-PR warnings to context hook. Hardening force-push blocker and scope guard error messages.

## Commits
- `pending` — 2026-03-19 — risk-class commit gates, shared frontmatter parser, context hook warnings

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
- [[Obsidian Work Tracking 2026-03-19 Workflow Skill Split]]
- [[Obsidian Work Tracking 2026-03-19 Guard Hardening]]

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
