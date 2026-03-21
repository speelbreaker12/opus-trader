---
project: "[[Upgrade 2 Telemetry Completion]]"
date: "2026-03-20"
---

## Commits
- `240baeaf` — shipped code for Upgrade 2 graybox telemetry completion
- `1b33802d` — PR #223 review-closure fixes for graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry gaps
- `d626c5af` — preflight full-mode empty-array fix for bash-3.2 `set -u` during merge verification

## 0) What shipped
- Feature/behavior: Completed Upgrade 2 graybox telemetry seams across the remaining execution/risk paths, closed the PR #223 review gaps, and then fixed a preflight full-mode harness bug that only appears on bash 3.2 when the serial full-only fixture list is empty.
- Value (what problem it solves): The PR branch now covers both the telemetry review items and the merge-blocking harness edge case, so `./plans/verify.sh full` no longer trips over an empty-array expansion before it reaches the real verification gates.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The merge flow reached `./plans/verify.sh full`, preflight aborted before emitting diagnostics, and the failure reduced to bash 3.2 treating `"${empty_array[@]}"` as unbound under `set -u` when `FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS` was declared but empty.
- Time/token drain it caused: The branch looked merge-ready from targeted tests and CI, but the final local verification gate still stopped early on a shell-specific harness edge case that static fixture-profile checks did not execute.
- Workaround I used this session (exploit): Reproduced the shell behavior directly, added a runtime regression that executes preflight in `full` mode with an intentionally empty serial fixture list, and then guarded the empty-array append in the production script.
- Next-agent default behavior (subordinate): When a workflow harness failure appears only in `full` mode, add the cheapest executable fixture that hits that path before changing the script.
- Permanent fix proposal (elevate): Keep both source-shape and runtime fixture coverage for any bash-array or `set -u` sensitive preflight paths, especially where lists may intentionally be empty.
- Smallest increment: For preflight list plumbing, always add one runtime fixture that executes the mode branch and one source-level assertion that the guard remains in place.
- Validation (proof it got better): `bash plans/tests/test_preflight_diagnostics.sh` and `bash plans/tests/test_preflight_fixture_profiles.sh` pass after the empty-array guard change.

## 2) Best follow-up
- Single best next step: Commit and push the preflight empty-array fix, then rerun the merge gate with a fresh `code_review_expert` attestation and `./plans/verify.sh full` on the new head.
- 1-3 upgrades worth considering: Replace the pending hash once committed; if `./plans/verify.sh full` advances beyond preflight and still hits `test_pr_review_gate_hook.sh`, split that timeout into its own follow-up; keep expanding the lint fixture matrix whenever another wrapper-only helper or Rust syntax form appears.

## PR Boundary
- Refresh method: `git fetch origin --prune` then `git rebase origin/main` on `upgrade2` (no-op; already up to date).
- PR: #223 — https://github.com/speelbreaker12/opus-trader/pull/223
- Validation after refresh, review closure, and follow-up harness fix: `bash plans/tests/test_lint_graybox_telemetry.sh` passed, `bash plans/tests/test_preflight_diagnostics.sh` passed, `bash plans/tests/test_preflight_fixture_profiles.sh` passed, `bash plans/tests/test_rust_gates_smoke_targets.sh` passed, `cargo fmt --all -- --check` passed, and `cargo test -p soldier_core --lib --locked` passed.
- Known blocker after refresh: merge is still pending a rerun of `./plans/verify.sh full` on the post-fix head; if it advances past preflight and later stalls in `plans/tests/test_pr_review_gate_hook.sh` again, that timeout still appears unrelated to PR #223.
- Handoff / next step: commit and push the preflight fix, rerun `code_review_expert` attestation plus `./plans/verify.sh full`, then resume the merge flow if the final gate is green.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: No `*_with_events` body may call `emit_execution_metric_line`, `fetch_add`, wrapper-only `bump_/record_` helpers, or `tracing::*!`; trigger: any new graybox seam edit; prevents: hidden telemetry leakage back into logic; enforce: `plans/lint_graybox_telemetry.sh`.
- Rule: If production logging needs input context, carry it in the internal event enum instead of logging from graybox logic; trigger: seam extraction for a path that currently logs values; prevents: observability regressions during refactor; enforce: graybox event assertions in the touched module tests.
- Rule: Wrapper parity tests must remain the only place that inspects traced metric lines or depends on global metric counters; trigger: any new telemetry-related test; prevents: graybox tests coupling themselves back to shared telemetry globals; enforce: module graybox/parity test split plus review.
