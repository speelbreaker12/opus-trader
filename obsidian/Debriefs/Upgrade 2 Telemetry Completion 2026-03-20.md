---
project: "[[Upgrade 2 Telemetry Completion]]"
date: "2026-03-20"
---

## Commits
- `240baeaf` — shipped code for Upgrade 2 graybox telemetry completion
- `1b33802d` — PR #223 review-closure fixes for graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry gaps
- `d626c5af` — preflight full-mode empty-array fix for bash-3.2 `set -u` during merge verification
- `9c11df57` — workflow harness follow-up fixing the review-stack wrapper contract and stale deleted verify test entry
- `3e3e7f0b` — workflow-contract follow-up wiring `graybox_telemetry_lint` into the contract/checker and adding a fail-closed batching regression

## 0) What shipped
- Feature/behavior: Completed Upgrade 2 graybox telemetry seams across the remaining execution/risk paths, closed the PR #223 review gaps, fixed the preflight full-mode empty-array bash-3.2 bug, aligned the review-stack wrapper and verify workflow test list with the current harness contract, and then wired `graybox_telemetry_lint` into the workflow contract/checker so the PR-page review gap is self-proving.
- Value (what problem it solves): The PR branch no longer relies on a reviewer noticing that `graybox_telemetry_lint` exists only in `rust_gates.sh`; the workflow contract now names it, the checker enforces it, and the batching regression proves removing that token fails closed.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The PR page still showed an external-review concern that `graybox_telemetry_lint` was only wired in `plans/lib/rust_gates.sh`, while `specs/WORKFLOW_CONTRACT.md` and `plans/verify_gate_contract_check.sh` did not name it. That meant the new graybox-lint enforcement could be silently removed without tripping the contract checker.
- Time/token drain it caused: The code and targeted tests already worked, but the PR still looked partially unaddressed from the reviewer’s perspective because the enforcement was not self-proving at the contract layer.
- Workaround I used this session (exploit): Narrowed the fix to the contract/checker surface only, then added a batching regression that mutates `plans/lib/rust_gates.sh` and asserts the checker fails on the missing `graybox_telemetry_lint` token.
- Next-agent default behavior (subordinate): When a workflow review says “this new gate is not self-proving,” patch the contract text and the checker together, then add a regression that fails if the new gate token is removed from the implementation script.
- Permanent fix proposal (elevate): Keep newly introduced verify gates dual-traced from day one: once in `specs/WORKFLOW_CONTRACT.md`, once in `plans/verify_gate_contract_check.sh`, with a mutation-style regression proving the checker notices drift in the real gate script.
- Smallest increment: For every newly added `run_logged_or_exit "<gate>"` in `plans/lib/*.sh`, extend the contract checker token list and its batching fixture in the same change.
- Validation (proof it got better): `bash plans/tests/test_verify_gate_contract_check_batching.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, and `./plans/verify_gate_contract_check.sh` all passed after the contract/checker update.

## 2) Best follow-up
- Single best next step: Commit and push the workflow-contract fix, then resolve the still-open PR threads and add a short PR comment tying the external-review note to the new contract/checker regression.
- 1-3 upgrades worth considering: Replace the pending hash once committed; if CI exposes any remaining workflow-only friction, split it out from PR #223 instead of widening the telemetry scope again; keep pairing every new verify gate with a checker token plus mutation-style regression.

## PR Boundary
- Refresh method: `git fetch origin --prune` then `git rebase origin/main` on `upgrade2` (no-op; already up to date).
- PR: #223 — https://github.com/speelbreaker12/opus-trader/pull/223
- Validation after refresh, review closure, harness follow-up, and contract fix: `bash plans/tests/test_lint_graybox_telemetry.sh` passed, `bash plans/tests/test_preflight_diagnostics.sh` passed, `bash plans/tests/test_preflight_fixture_profiles.sh` passed, `bash plans/tests/test_review_command_wrappers.sh` passed, `bash plans/tests/test_rust_gates_smoke_targets.sh` passed, `bash plans/tests/test_verify_gate_contract_check_batching.sh` passed, `./plans/verify_gate_contract_check.sh` passed, `cargo fmt --all -- --check` passed, `cargo test -p soldier_core --lib --locked` passed, and `./plans/verify.sh full` passed (`20260320_190741`) before the later contract/checker follow-up.
- Known blocker after refresh: local full verify has not yet been rerun on the post-merge `c8f8c594` base plus this final contract-checker delta; CI or another full run is still needed before any merge attempt.
- Handoff / next step: commit and push this final workflow-contract batch, refresh attestation on the pushed head if merge will be attempted from it, and re-check PR #223 thread state/CI before resuming merge cleanup.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: No `*_with_events` body may call `emit_execution_metric_line`, `fetch_add`, wrapper-only `bump_/record_` helpers, or `tracing::*!`; trigger: any new graybox seam edit; prevents: hidden telemetry leakage back into logic; enforce: `plans/lint_graybox_telemetry.sh`.
- Rule: If production logging needs input context, carry it in the internal event enum instead of logging from graybox logic; trigger: seam extraction for a path that currently logs values; prevents: observability regressions during refactor; enforce: graybox event assertions in the touched module tests.
- Rule: Wrapper parity tests must remain the only place that inspects traced metric lines or depends on global metric counters; trigger: any new telemetry-related test; prevents: graybox tests coupling themselves back to shared telemetry globals; enforce: module graybox/parity test split plus review.
