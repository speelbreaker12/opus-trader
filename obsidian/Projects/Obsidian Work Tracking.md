---
status: in-progress
priority: P1
branch: workflow/obsidian-work-tracking-closeout
base: main
pr:
started: "2026-03-16"
scope_paths:
  - .codex/commands/**
  - .codex/skills/**
  - .claude/commands/**
  - .claude/hooks/**
  - .claude/settings.json
  - .claude/skills/**
  - .gitignore
  - .githooks/**
  - AGENTS.md
  - SKILLS/**
  - docs/skills/index.md
  - obsidian/**
  - plans/obsidian_commit_guard.sh
  - plans/project_scope_guard.sh
  - plans/open_project_pr.sh
  - plans/tests/**
  - plans/verify_fork.sh
  - plans/workflow_files_allowlist.txt
  - plans/workflow_verify.sh
  - scripts/setup_hooks.sh
---

## Current State
The original `workflow/obsidian-skills-clean` slice is complete and merged as PR `#217` via merge commit `071e3c84`, and the repo-tracked Codex regression fix is now staged on this follow-up branch. The Codex mirror coverage and wrapper regression test are green, but the broader `./plans/workflow_verify.sh` run is still blocked by the existing `wf_test_pr_review_gate_hook` failure that expects plain `gh pr create` to exit `2` when the review marker is missing.

## Commits
- `071e3c84` — 2026-03-17 — Merge PR #217 (`workflow/obsidian-skills-clean`) into `main`.
- `pending` — 2026-03-21 — Track repo-local Codex skill mirrors, command wrappers, and regression coverage so all repo skills stay invokable from Codex worktrees.

## Key Files
- .gitignore
- .codex/commands/commit.md
- .codex/commands/commit-push-pr.md
- .codex/skills/commit/SKILL.md
- .codex/skills/commit-push-pr/SKILL.md
- plans/tests/test_review_command_wrappers.sh
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
- [[Obsidian Work Tracking 2026-03-21 Codex Skill Mirrors]]
- [[Obsidian Work Tracking 2026-03-21 Merge Closeout]]

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
### 2026-03-21
- Confirmed PR #217 merged to `main` as `071e3c84` and that `workflow/obsidian-skills-clean` is no longer an active execution lane.
- Opened `workflow/obsidian-work-tracking-closeout` only to normalize this project note and add a final debrief after the merge.
- Retired the stale `origin/workflow/obsidian-skills-clean` branch ref so future workflow work starts from a fresh main-based lane.
- Mirrored repo-local `.claude/skills/*/SKILL.md` wrappers into tracked `.codex/skills/*/SKILL.md` files so Codex worktrees expose the same repo-defined skill surface.
- Added tracked `.codex/commands/*.md` wrappers, including alias coverage such as `/6`, `/external-review`, and the deprecated but still invokable `/commit-push-pr`.
- Tightened `.gitignore` to allow tracked `.codex/skills/**` and `.codex/commands/*.md` while keeping other local Codex state ignored.
- Expanded `plans/tests/test_review_command_wrappers.sh` to fail when repo-tracked Codex skill mirrors or command wrappers drift from the Claude wrappers.
- Fixed the staged Codex `/review` alias so it invokes the global `code-review-expert` skill instead of pointing at a nonexistent repo-local skill mirror.
- Ran `./plans/workflow_verify.sh`; the Codex mirror changes held, but the suite still failed in the existing `wf_test_pr_review_gate_hook` gate on plain `gh pr create` marker enforcement.
