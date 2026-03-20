---
project: "[[Upgrade 2 Telemetry Completion]]"
date: "2026-03-20"
---

## Commits
- `240baeaf` — shipped code for Upgrade 2 graybox telemetry completion
- `pending` — PR #223 review-closure fixes for graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry gaps

## 0) What shipped
- Feature/behavior: Completed Upgrade 2 graybox telemetry seams across the remaining execution/risk paths, then closed the PR #223 review gaps in the graybox lint, smoke fixture accounting, and missing seam-specific parity/graybox tests.
- Value (what problem it solves): Logic can now be tested as inputs to decisions plus typed events without global telemetry side effects, the workflow fixture surface matches the new lint gate, and the review-raised edge cases are covered mechanically instead of being left as commentary.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Review feedback exposed three kinds of verification drift: the smoke fixture profile lagged the new lint gate, the lint parser missed valid Rust macro/signature forms, and some seam branches still lacked explicit graybox/parity evidence even though the underlying behavior was correct.
- Time/token drain it caused: Time went into rechecking whether each comment was a real bug, then adding narrow regression coverage so the same review arguments do not need to be replayed on the next pass.
- Workaround I used this session (exploit): Treated each review comment as a falsifiable claim, reproduced the real failures first, then closed them with the smallest code/test changes that made the boundary self-checking.
- Next-agent default behavior (subordinate): When a review comment targets telemetry/workflow enforcement, first reproduce it locally, then prefer adding deterministic tests or fixtures over thread-only rebuttals.
- Permanent fix proposal (elevate): Keep the graybox lint fixture suite synchronized with every newly introduced forbidden pattern or parser edge case, and add a cheap gate-presence regression whenever workflow wiring grows.
- Smallest increment: For any new workflow or lint guard, land one targeted regression that proves the guard is still wired and one source-level regression that proves the parser catches the new syntax.
- Validation (proof it got better): `bash plans/tests/test_lint_graybox_telemetry.sh`, `bash plans/tests/test_preflight_fixture_profiles.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, `cargo fmt --all -- --check`, and `cargo test -p soldier_core --lib --locked` all passed after the review-closure fixes.

## 2) Best follow-up
- Single best next step: Push the review-closure patch and rerun CI so PR #223 shows the smoke-fixture and lint-parser fixes on a clean checkout while the unrelated `test_pr_review_gate_hook.sh` timeout is evaluated separately.
- 1-3 upgrades worth considering: Replace the pending hash once committed; decide whether the workflow-hook timeout deserves its own project/branch because it is outside this PR scope; keep expanding the lint fixture matrix whenever another wrapper-only helper or Rust syntax form appears.

## PR Boundary
- Refresh method: `git fetch origin --prune` then `git rebase origin/main` on `upgrade2` (no-op; already up to date).
- PR: #223 — https://github.com/speelbreaker12/opus-trader/pull/223
- Validation after refresh and review closure: `bash plans/tests/test_lint_graybox_telemetry.sh` passed, `bash plans/tests/test_preflight_fixture_profiles.sh` passed, `bash plans/tests/test_rust_gates_smoke_targets.sh` passed, `cargo fmt --all -- --check` passed, and `cargo test -p soldier_core --lib --locked` passed.
- Known blocker after refresh: `./plans/workflow_verify.sh` now gets past the smoke-fixture gate and later stalls in `plans/tests/test_pr_review_gate_hook.sh`; an isolated `timeout 60 bash plans/tests/test_pr_review_gate_hook.sh` reproduced the timeout, so the remaining workflow failure appears unrelated to PR #223.
- Handoff / next step: push the PR #223 review-closure patch, reply on the resolved review threads with the specific tests/files added, and if the hook timeout still matters, track it separately from this branch.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Rule: No `*_with_events` body may call `emit_execution_metric_line`, `fetch_add`, wrapper-only `bump_/record_` helpers, or `tracing::*!`; trigger: any new graybox seam edit; prevents: hidden telemetry leakage back into logic; enforce: `plans/lint_graybox_telemetry.sh`.
- Rule: If production logging needs input context, carry it in the internal event enum instead of logging from graybox logic; trigger: seam extraction for a path that currently logs values; prevents: observability regressions during refactor; enforce: graybox event assertions in the touched module tests.
- Rule: Wrapper parity tests must remain the only place that inspects traced metric lines or depends on global metric counters; trigger: any new telemetry-related test; prevents: graybox tests coupling themselves back to shared telemetry globals; enforce: module graybox/parity test split plus review.
