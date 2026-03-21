---
status: in-progress
priority: P1
branch: workflow/pr-review-gate-hook-fix
base: main
pr:
started: "2026-03-21"
worktree: /Users/admin/Desktop/opus-trader/.git/Desktop/wt_pr_review_gate_hook_fix
aliases:
  - PR Review Gate Hook
keywords:
  - workflow
  - pr
  - review-stack
  - hook
scope_paths:
  - .claude/commands/review-stack.md
  - .claude/hooks/pr-review-gate-hook.sh
  - obsidian/Projects/PR Review Gate Hook Fix.md
  - obsidian/Debriefs/PR Review Gate Hook Fix *.md
  - plans/progress.txt
  - plans/tests/test_pr_review_gate_hook.sh
---

## Current State

In progress on branch `workflow/pr-review-gate-hook-fix` in worktree `/Users/admin/Desktop/opus-trader/.git/Desktop/wt_pr_review_gate_hook_fix`. The hook now fail-closes PR creation when the canonical review-stack marker is missing, invalid, or stale, while still honoring legacy `.review-stack.json` markers only when no canonical marker exists. Local focused verification passed via direct hook invocations plus syntax/diff checks; the full long-running shell fixture remains noisy in this Codex session because unrelated background harnesses in other worktrees keep re-spawning the same hook test.

## Commits
- `pending` — 2026-03-21 — restore blocking PR review gate behavior for missing/stale review-stack markers and align the command doc with the live marker path.

## Key Files
- .claude/hooks/pr-review-gate-hook.sh
- .claude/commands/review-stack.md
- plans/tests/test_pr_review_gate_hook.sh

## Debriefs
- [[PR Review Gate Hook Fix 2026-03-21]]

## Log
### 2026-03-21
- Created a fresh workflow-only lane from `origin/main` after confirming the `test_pr_review_gate_hook.sh` failure also reproduces on clean baseline.
- Confirmed the current hook comment/behavior is advisory-at-PR-create, which conflicts with the regression and the `/review-stack` command text that says the marker is checked before PR publication and merge.
- Restored fail-closed PR-create enforcement in `.claude/hooks/pr-review-gate-hook.sh`, including explicit blocks for missing markers, non-pass verdicts, missing head fields, and stale heads.
- Added legacy marker compatibility for `.review-stack.json`, but tightened precedence so an existing canonical `${SAFE_BRANCH}.json` marker always wins over legacy fallback.
- Updated `/review-stack` command docs to emit the canonical `${SAFE_BRANCH}.json` path and extended `plans/tests/test_pr_review_gate_hook.sh` with regression coverage for legacy filename compatibility, canonical-marker precedence, and doc-path alignment.
- Verified with `bash -n .claude/hooks/pr-review-gate-hook.sh plans/tests/test_pr_review_gate_hook.sh`, `git diff --check -- .claude/hooks/pr-review-gate-hook.sh .claude/commands/review-stack.md plans/tests/test_pr_review_gate_hook.sh obsidian/Projects/PR Review Gate Hook Fix.md`, direct sanitized hook invocations proving missing-marker block (`rc=2`), legacy-marker pass (`rc=0`), canonical-fail-over-legacy block (`rc=2`), and a grep check confirming `.claude/commands/review-stack.md` now writes `artifacts/pr-review-gate/${SAFE_BRANCH}.json`.
