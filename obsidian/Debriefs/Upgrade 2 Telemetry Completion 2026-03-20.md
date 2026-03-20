---
project: "[[Upgrade 2 Telemetry Completion]]"
date: "2026-03-20"
---

## Commits
- `240baeaf` — shipped code for Upgrade 2 graybox telemetry completion
- `pending` — project/debrief PR-boundary update for PR #223 and refresh/validation status

## 0) What shipped
- Feature/behavior: Completed Upgrade 2 graybox telemetry seams across the remaining execution/risk paths and enforced the boundary with a dedicated lint.
- Value (what problem it solves): Logic can now be tested as inputs to decisions plus typed events without global telemetry side effects, while production wrappers preserve the existing metrics and trace-enriched observability contract.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Remaining orchestration code still mutated global counters directly; wrapper-only logging context was easy to lose during seam extraction; and there was no mechanical guard preventing regressions back into direct telemetry.
- Time/token drain it caused: Multiple review/fix loops were spent removing hidden telemetry from graybox seams and restoring production-only diagnostic detail after the first refactor passes.
- Workaround I used this session (exploit): Carried observability context through internal event payloads and validated the seam with a grep/parser-based lint plus targeted graybox regression tests.
- Next-agent default behavior (subordinate): When moving logic behind `*_with_events`, push every metric/log side effect into the production adapter immediately and add a graybox event assertion for any context that production logs need.
- Permanent fix proposal (elevate): Keep evolving the graybox telemetry lint as the canonical mechanical boundary and extend its fixtures whenever a new wrapper-only helper or telemetry pattern appears.
- Smallest increment: Add a regression fixture and one real-source test case for each newly discovered telemetry pattern before landing future seam work.
- Validation (proof it got better): `bash plans/tests/test_lint_graybox_telemetry.sh`, `bash plans/lint_graybox_telemetry.sh`, and `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target cargo test -p soldier_core --locked` all passed after the final context-preserving fixes.

## 2) Best follow-up
- Single best next step: Fix `plans/tests/test_preflight_fixture_profiles.sh` on the proper workflow branch so `./plans/workflow_verify.sh` stops failing on the new smoke fixture count and PR #223 can present a green workflow surface.
- 1-3 upgrades worth considering: Replace the pending PR-boundary hash once committed; add any future wrapper-only telemetry helpers to the graybox lint fixture matrix; fold this branch back into the broader execution facade tracking once the review/merge path is chosen.

## PR Boundary
- Refresh method: `git fetch origin --prune` then `git rebase origin/main` on `upgrade2` (no-op; already up to date).
- PR: #223 — https://github.com/speelbreaker12/opus-trader/pull/223
- Validation after refresh: `bash plans/lint_graybox_telemetry.sh` passed, `bash plans/tests/test_lint_graybox_telemetry.sh` passed, `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target cargo test -p soldier_core --locked` passed.
- Known blocker after refresh: `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target ./plans/workflow_verify.sh` fails in `wf_test_preflight_fixture_profiles` with `unexpected smoke fixture count: 13 (expected 12)`.
- Handoff / next step: resolve the workflow smoke-count expectation on the workflow-owned branch, then rerun workflow verification and update PR #223 if needed.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: No `*_with_events` body may call `emit_execution_metric_line`, `fetch_add`, wrapper-only `bump_/record_` helpers, or `tracing::*!`; trigger: any new graybox seam edit; prevents: hidden telemetry leakage back into logic; enforce: `plans/lint_graybox_telemetry.sh`.
- Rule: If production logging needs input context, carry it in the internal event enum instead of logging from graybox logic; trigger: seam extraction for a path that currently logs values; prevents: observability regressions during refactor; enforce: graybox event assertions in the touched module tests.
- Rule: Wrapper parity tests must remain the only place that inspects traced metric lines or depends on global metric counters; trigger: any new telemetry-related test; prevents: graybox tests coupling themselves back to shared telemetry globals; enforce: module graybox/parity test split plus review.
