---
status: in-progress
priority: P2
branch: recover/claude-skill-path-fixes-20260321
base: main
pr:
started: "2026-03-21"
aliases:
  - Skill Wrapper Path Fixes
keywords:
  - claude
  - skills
  - path-resolution
scope_paths:
  - .claude/skills/premortem/SKILL.md
  - .claude/skills/review-stack/SKILL.md
  - obsidian/Projects/Claude Skill Path Fixes.md
  - obsidian/Debriefs/Claude Skill Path Fixes 2026-03-21.md
---

## Current State
In progress. This branch isolates the only salvageable part of the older recovery stash: two `.claude/skills/*` path fixes that replace CWD-relative `cat` calls with repo-root-resolved paths.

## Commits
- `pending` — 2026-03-21 — harden `.claude` skill wrappers to load repo files from the repo root

## Key Files
- .claude/skills/premortem/SKILL.md
- .claude/skills/review-stack/SKILL.md

## Debriefs
- [[Claude Skill Path Fixes 2026-03-21]]

## Log
### 2026-03-21
- Recovered the two path-resolution edits onto `recover/claude-skill-path-fixes-20260321` in an isolated worktree.
- Scoped the project note to only the two `.claude/skills/*` files plus this note and its debrief so the commit stays mechanically narrow.
