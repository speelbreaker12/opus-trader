---
status: in-progress
priority: P2
branch: workflow/obsidian-fixes
worktree: .worktrees/obsidian-workflow-fixes
lifecycle: rewrite_ok
pr:
started: "2026-03-19"
---

## Current State
Branch with workflow improvements: bare-repo commit guard, cargo-verify skip for non-crate branches, worktree collision check in main-recovery, codex commit/push-pr wrappers, skills index validation fixes, context hook and precommit hook enhancements.

## Key Files
- .claude/hooks/obsidian-precommit-hook.sh
- .claude/hooks/obsidian-context-hook.sh
- plans/obsidian_commit_guard.sh
- plans/project_scope_guard.sh
- plans/worktree_commit_push.sh
- plans/write_review_gate_marker.sh
- SKILLS/push-pr.md

## Debriefs
-

## Log
### 2026-03-19
- Rebased 9 commits onto origin/main (2e8f180c)
- Preparing PR for workflow fixes
