---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-19"
---

## Commits
- `599f1306` workflow: split commit/push skills, add hotfix + main-recovery + workspace policy
- `1d38c5a1` workflow: remove dead main-push verify path, fix rebase status label
- (pending) workflow: update project note branch + scope_paths for clean cherry-pick branch

## What shipped
Split monolithic commit-push-pr into composable lifecycle skills. Added hotfix, main-recovery, and workspace-policy as new skills. Hardened git hooks with main branch guards and pre-rebase speed bump. Fixed obsidian-precommit-hook.sh early-exit bug.

## Files touched
- SKILLS/commit.md, push-pr.md, workspace-policy.md, hotfix.md, main-recovery.md, obsidian-workflow.md
- .githooks/pre-commit, pre-push, pre-rebase
- .claude/hooks/obsidian-precommit-hook.sh
- .claude/commands/ and .claude/skills/ wiring
- docs/skills/index.md
- obsidian/Projects/Obsidian Work Tracking.md

## Handoff
- wt-main worktree created on main (local main diverged from origin, needs reconciliation)
- All new skills tested via logic checks and live hook tests
- Next: push-pr to ship this branch, reconcile local main divergence
