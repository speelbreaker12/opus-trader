---
status: done
priority: P1
branch: project/obsidian-work-tracking
pr: 213
started: "2026-03-16"
aliases:
- obsidian workflow
- project tracking
keywords:
- debrief guard
- context router
- workflow skill
- handoff
worktree: .worktrees/obsidian-work-tracking
---

## Current State
Complete. Obsidian-based project tracking now includes repo-level debrief enforcement in pre-commit, Claude-side hook delegation to the same shared guard, first-prompt project routing into the best matching Obsidian note, alias/keyword-aware project-note scoring, per-project worktree tracking and auto-bootstrap, a companion `/obsidian-workflow` skill for what to read/update/include, a conditional Obsidian handoff policy with a dedicated `obsidian/Handoffs/` path and template, single-project staged Obsidian scope enforcement per commit, and a commit-aware debrief/template workflow with explicit commit history on the project page.

## Commits
- `pending` — 2026-03-17 — add a shared Repo Maintenance project fallback for small fixes and housekeeping work.
- `pending` — 2026-03-17 — add a dedicated `## PRs` section to project pages and document how to keep it current.
- `pending` — 2026-03-17 — backfill the landed hash for the worktree-routing and handoff-policy batch in the project note and debriefs.
- `75abb925` — 2026-03-17 — add the conditional handoff policy plus project-scoped worktree tracking and first-prompt bootstrap/routing to the Obsidian workflow.
- `55adc330` — 2026-03-17 — add alias/keyword-aware project-note scoring to the router, seed the project template for those fields, and backfill the prior skill-companion hash.
- `633c39d7` — 2026-03-17 — add the `/obsidian-workflow` skill companion, register it in the skills index, and teach the first-prompt router to point agents at it explicitly.
- `172f6386` — 2026-03-17 — fail closed when staged Obsidian project/debrief files from another project are present in the same commit.
- `86ab792f` — 2026-03-17 — route first-session prompts to the best matching Obsidian project note, inject the matched note into hook context, wire router coverage into workflow verification, and add a shared guard reminder to include only the changes you made in the commit.
- `b1393d87` — 2026-03-17 — enforce linked debriefs in repo and Claude commit hooks.
- `788133f8` — 2026-03-17 — enable Context7 and expand AGENTS instructions for Warp/Codex workflows.
- `2a2f0fd1` — 2026-03-16 — enforce project tracking for all agents via git hook and AGENTS rules.
- `1bb74a97` — 2026-03-16 — enforce mandatory project tracking on commit.
- `872149dc` — 2026-03-16 — add the initial Obsidian project context hooks and work-tracking setup.

## PRs
- `#213` — branch `pr/obsidian-hooks` — open — split hook/Obsidian routing, guardrails, workflow skill, and worktree tracking into a dedicated review branch.

## Key Files
- obsidian/Templates/Project.md
- obsidian/Templates/Debrief.md
- .claude/hooks/obsidian-context-hook.sh
- .claude/skills/obsidian-workflow/SKILL.md
- SKILLS/obsidian-workflow.md
- docs/skills/index.md
- obsidian/Templates/Project.md
- .worktrees/obsidian-work-tracking
- obsidian/Templates/Handoff.md
- obsidian/Handoffs/
- .claude/hooks/obsidian-precommit-hook.sh
- .githooks/pre-commit
- plans/obsidian_commit_guard.sh
- plans/tests/test_obsidian_context_hook.sh
- .claude/settings.json
- AGENTS.md (Obsidian Project Tracking section)

## Debriefs
- [[Obsidian Work Tracking 2026-03-17 Debrief Guard]]
- [[Obsidian Work Tracking 2026-03-17 Context Router]]
- [[Obsidian Work Tracking 2026-03-17 Single Project Guard]]
- [[Obsidian Work Tracking 2026-03-17 Obsidian Workflow Skill]]
- [[Obsidian Work Tracking 2026-03-17 Router Aliases]]
- [[Obsidian Work Tracking 2026-03-17 Obsidian Handoff Policy]]
- [[Obsidian Work Tracking 2026-03-17 Project Worktrees]]
- [[Obsidian Work Tracking 2026-03-17 PRs Section]]
- [[Obsidian Work Tracking 2026-03-17 Repo Maintenance Fallback]]

## Handoffs
- None active. Save future handoffs under `obsidian/Handoffs/` only when work is paused, blocked, or explicitly handed off.

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
- Tightened the shared Obsidian commit guard to block commits when staged Obsidian debriefs belong to a different project than the staged project note, or when more than one project note is staged at once.
- Added regression coverage for mismatched staged debriefs and multi-project staging so the stricter scope rule is enforced through both the repo hook and the Claude-side hook.
- Added a companion `/obsidian-workflow` skill and taught the first-prompt router to point agents at it explicitly so the checklist for project pages and debriefs is available at session start without replacing the hooks.
- Added optional frontmatter `aliases` / `keywords` to the project template and taught the router to score them so future sessions can rediscover the right project note with less prompt wording friction.
- Added a conditional handoff policy for Obsidian tracking: handoffs now live in `obsidian/Handoffs/` from a dedicated template, are linked from the project page only when active, and do not replace existing workflow-required handoff artifacts elsewhere in the repo.
- Added project-scoped worktree tracking to project-note frontmatter and taught the first-prompt router to create or reuse dedicated `.worktrees/<project-slug>` paths so matched sessions have an isolated workspace immediately.
- Created the dedicated `.worktrees/obsidian-work-tracking` workspace on branch `project/obsidian-work-tracking` so this project note now points at a real isolated checkout instead of a planned one.
- Backfilled commit `75abb925` into this project note and the matching debriefs after the worktree-routing and handoff-policy batch landed.
- Added a `## PRs` section to the project template and workflow guidance, and recorded the dedicated review branch PR for this work.
- Added a dedicated Obsidian debrief/project-note update for the new `## PRs` section so future project pages track active and historical PRs explicitly.
- Added a shared `Repo Maintenance` fallback project for small fixes and housekeeping work so future minor changes do not need a brand-new project page every time.
