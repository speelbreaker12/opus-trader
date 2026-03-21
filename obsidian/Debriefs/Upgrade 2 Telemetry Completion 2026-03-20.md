---
project: "[[Upgrade 2 Telemetry Completion]]"
date: "2026-03-20"
---

## Commits
- `240baeaf` — shipped code for Upgrade 2 graybox telemetry completion
- `1b33802d` — PR #223 review-closure fixes for graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry gaps
- `d626c5af` — preflight full-mode empty-array fix for bash-3.2 `set -u` during merge verification
- `9c11df57` — workflow harness follow-up fixing the review-stack wrapper contract and stale deleted verify test entry

## 0) What shipped
- Feature/behavior: Completed Upgrade 2 graybox telemetry seams across the remaining execution/risk paths, closed the PR #223 review gaps, fixed the preflight full-mode empty-array bash-3.2 bug, then aligned the review-stack wrapper and verify workflow test list with the current harness contract.
- Value (what problem it solves): The PR branch now clears the actual merge gate locally: `./plans/verify.sh full` no longer fails on an empty-array expansion, an outdated command wrapper, or a deleted workflow test referenced by `verify_fork.sh`.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The merge flow first died in preflight because bash 3.2 treated `"${empty_array[@]}"` as unbound under `set -u`, then later `full` verify failed again because `.claude/commands/review-stack.md` no longer matched the enforced wrapper contract, and finally because `plans/verify_fork.sh` still tried to run a deleted `plans/tests/test_contract_at_wording_drift.sh`.
- Time/token drain it caused: The branch looked merge-ready from targeted tests and CI, but the final local verification gate kept surfacing stale harness assumptions late in the run, forcing repeated long verify cycles.
- Workaround I used this session (exploit): Added targeted executable regressions for the empty-array path and the workflow-test list, replaced the stale command wrapper body with the current thin wrapper form, and removed the deleted workflow test from the verify integration array.
- Next-agent default behavior (subordinate): When `full` verify fails on workflow infrastructure, patch the narrow failing contract and add a cheap regression that proves the harness list or wrapper shape cannot silently drift again.
- Permanent fix proposal (elevate): Keep verify-array membership under executable regression coverage and prefer thin command wrappers that delegate to the canonical skill file instead of duplicating skill bodies.
- Smallest increment: For every new workflow integration test entry, add a source-level assertion that the listed path exists on disk; for every command wrapper contract, keep one targeted wrapper-regression fixture.
- Validation (proof it got better): `bash plans/tests/test_review_command_wrappers.sh`, `bash plans/tests/test_preflight_fixture_profiles.sh`, and `./plans/verify.sh full` (`20260320_190741`) all passed after the harness fixes.

## 2) Best follow-up
- Single best next step: Commit and push the workflow harness fixes, refresh the review attestation on the new head, then re-check PR #223 status/CI and ask for merge confirmation.
- 1-3 upgrades worth considering: Replace the pending hash once committed; if PR CI reports any residual harness timing issue, split it into a separate follow-up instead of widening PR #223; keep expanding the workflow regression suite whenever verify arrays or command wrappers change.

## PR Boundary
- Refresh method: `git fetch origin --prune` then `git rebase origin/main` on `upgrade2` (no-op; already up to date).
- PR: #223 — https://github.com/speelbreaker12/opus-trader/pull/223
- Validation after refresh, review closure, and follow-up harness fix: `bash plans/tests/test_lint_graybox_telemetry.sh` passed, `bash plans/tests/test_preflight_diagnostics.sh` passed, `bash plans/tests/test_preflight_fixture_profiles.sh` passed, `bash plans/tests/test_review_command_wrappers.sh` passed, `bash plans/tests/test_rust_gates_smoke_targets.sh` passed, `cargo fmt --all -- --check` passed, `cargo test -p soldier_core --lib --locked` passed, and `./plans/verify.sh full` passed (`20260320_190741`).
- Known blocker after refresh: none in local verification; remaining merge prerequisites are commit/push, fresh review attestation for the new head, and PR approval/CI state.
- Handoff / next step: commit and push this final workflow harness batch, refresh attestation on the pushed head, then resume the merge flow once PR #223 shows ready-to-merge state.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: No `*_with_events` body may call `emit_execution_metric_line`, `fetch_add`, wrapper-only `bump_/record_` helpers, or `tracing::*!`; trigger: any new graybox seam edit; prevents: hidden telemetry leakage back into logic; enforce: `plans/lint_graybox_telemetry.sh`.
- Rule: If production logging needs input context, carry it in the internal event enum instead of logging from graybox logic; trigger: seam extraction for a path that currently logs values; prevents: observability regressions during refactor; enforce: graybox event assertions in the touched module tests.
- Rule: Wrapper parity tests must remain the only place that inspects traced metric lines or depends on global metric counters; trigger: any new telemetry-related test; prevents: graybox tests coupling themselves back to shared telemetry globals; enforce: module graybox/parity test split plus review.
