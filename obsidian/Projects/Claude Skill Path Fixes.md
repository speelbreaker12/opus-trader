---
status: in-review
priority: P2
branch: recover/claude-skill-path-fixes-20260321
base: main
pr: 229
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
In review. This branch isolates the only salvageable part of the older recovery stash: two `.claude/skills/*` path fixes that replace CWD-relative `cat` calls with repo-root-resolved paths, and PR #229 is open against `main`.

## Commits
- `pending` — 2026-03-21 — record PR #229 and publish branch state
- `e0699b55` — 2026-03-21 — record claude skill path fix hash
- `c49eb256` — 2026-03-21 — harden `.claude` skill wrappers to load repo files from the repo root

## Key Files
- .claude/skills/premortem/SKILL.md
- .claude/skills/review-stack/SKILL.md

## Debriefs
- [[Claude Skill Path Fixes 2026-03-21]]

## Log
### 2026-03-21
- Recovered the two path-resolution edits onto `recover/claude-skill-path-fixes-20260321` in an isolated worktree.
- Scoped the project note to only the two `.claude/skills/*` files plus this note and its debrief so the commit stays mechanically narrow.
- Pushed `recover/claude-skill-path-fixes-20260321` to `origin` and opened PR #229 with the existing `workflow_verify.sh` timeout caveat documented in the PR test plan.
