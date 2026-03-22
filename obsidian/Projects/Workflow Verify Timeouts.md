---
status: in-progress
priority: P1
branch: workflow/verify-mechanical-timeout-fix
base: main
pr: 230
started: "2026-03-21"
aliases:
  - Mechanical Verify Timeout Fix
keywords:
  - workflow
  - verify
  - timeout
  - mechanical
scope_paths:
  - plans/verify_fork.sh
  - plans/tests/test_verify_timeout_policy.sh
  - plans/tests/test_pr_review_gate_hook.sh
  - plans/tests/test_pr_review_gate_hook_scope.sh
  - .claude/hooks/pr-review-gate-hook.sh
  - plans/progress.txt
  - obsidian/Projects/Workflow Verify Timeouts.md
  - obsidian/Debriefs/Workflow Verify Timeouts 2026-03-21.md
---

## Current State
In progress. PR #230 is open for the first workflow timeout root cause fix: `mechanical_verification` was capped at `240s` even though the clean-main direct run now takes `247.54s`. The downstream `wf_test_pr_review_gate_hook` timeout investigation is now reduced to a stale-test mismatch: commit `a3cd8a51` aligns the regression with the hook's warning-only PR-create contract, the focused test passes in `2:27.68`, and `workflow_verify.sh` advances beyond that gate to the next pre-existing failure in `wf_test_review_command_wrappers`.

## Commits
- `a3cd8a51` — 2026-03-21 — align `wf_test_pr_review_gate_hook` expectations with warning-only PR-create review-gate behavior
- `e988d95d` — 2026-03-21 — record PR #230 and continue `wf_test_pr_review_gate_hook` timeout investigation
- `09ce84bc` — 2026-03-21 — raise mechanical verification timeout budget and publish root-cause evidence

## Key Files
- plans/verify_fork.sh
- plans/tests/test_verify_timeout_policy.sh
- plans/tests/test_pr_review_gate_hook.sh
- .claude/hooks/pr-review-gate-hook.sh

## Debriefs
- [[Workflow Verify Timeouts 2026-03-21]]

## Log
### 2026-03-21
- Reproduced the original timeout on clean `main` in `.worktrees/verify-mechanical-timeout-fix` and proved the failure was a budget mismatch, not a stuck Upgrade 1B proof.
- Raised `MECHANICAL_TIMEOUT` to `5m`, updated the timeout policy test, and confirmed `workflow_verify.sh` now passes `mechanical_verification` before exposing the next timeout in `wf_test_pr_review_gate_hook`.
- Pushed `workflow/verify-mechanical-timeout-fix` and opened PR #230 to publish the timeout-budget fix separately from the current downstream timeout investigation.
- Proved the downstream `wf_test_pr_review_gate_hook` issue was stale test expectations, not a live hook deadlock: missing or stale review markers warn at PR creation, the focused test now passes in `2:27.68`, and `workflow_verify.sh` advances to the separate pre-existing wrapper mismatch in `wf_test_review_command_wrappers`.
