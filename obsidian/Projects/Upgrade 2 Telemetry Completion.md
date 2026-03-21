---
status: in-review
priority: P1
branch: upgrade2
base: main
pr: 223
started: "2026-03-20"
aliases:
  - Upgrade 2 Telemetry
keywords:
  - upgrade2
  - graybox
  - telemetry
  - event-sink
scope_paths:
  - crates/soldier_core/src/execution/build_order_intent.rs
  - crates/soldier_core/src/execution/build_order_intent_gate_ordering_tests.rs
  - crates/soldier_core/src/execution/group.rs
  - crates/soldier_core/src/execution/post_only_guard.rs
  - crates/soldier_core/src/execution/post_only_guard_tests.rs
  - crates/soldier_core/src/execution/routing.rs
  - crates/soldier_core/src/risk/fees.rs
  - crates/soldier_core/src/risk/pending_exposure.rs
  - docs/codebase/upgrade2_graybox_telemetry_checklist.md
  - plans/lib/rust_gates.sh
  - plans/preflight.sh
  - plans/verify_gate_contract_check.sh
  - plans/verify_fork.sh
  - plans/workflow_files_allowlist.txt
  - plans/workflow_verify.sh
  - plans/lint_graybox_telemetry.sh
  - specs/WORKFLOW_CONTRACT.md
  - plans/tests/test_preflight_diagnostics.sh
  - plans/tests/test_lint_graybox_telemetry.sh
  - plans/tests/test_preflight_fixture_profiles.sh
  - plans/tests/test_rust_gates_smoke_targets.sh
  - plans/tests/test_verify_gate_contract_check_batching.sh
  - .claude/commands/review-stack.md
  - obsidian/Projects/Upgrade 2 Telemetry Completion.md
  - obsidian/Debriefs/Upgrade 2 Telemetry Completion 2026-03-20.md
---

## Current State
Upgrade 2 is complete on branch `upgrade2` and PR #223 is open against `main`. The remaining orchestration telemetry paths were moved behind internal event sinks, the wrapper layer still preserves the existing metrics contract, and the graybox telemetry boundary is now mechanically enforced by a dedicated lint wired into workflow verification. PR #223 review feedback has been folded back into the branch: smoke fixture expectations match the 13-test profile, the graybox lint handles whitespace-trimmed multiline roots plus brace/bracket tracing macros and declaration-only signatures, event payloads no longer carry `f64`, and missing graybox/parity tests were added for the flagged seams. The merge-gate harness follow-ups are also addressed: preflight full mode no longer trips bash-3.2 `set -u` on intentionally empty arrays, the review-stack command wrapper matches the current skill-wrapper contract, and `plans/verify_fork.sh` no longer references the deleted `test_contract_at_wording_drift.sh`. The last substantive PR-page gap was that `graybox_telemetry_lint` existed in `rust_gates.sh` but was not named in the workflow contract or enforced by the verify-gate contract checker; this batch closes that gap with contract text plus a fail-closed regression in `test_verify_gate_contract_check_batching.sh`.

## Commits
- `240baeaf` — 2026-03-20 — complete Upgrade 2 graybox telemetry migration, preserve wrapper parity and diagnostic context, add graybox telemetry lint plus regression coverage.
- `1b33802d` — 2026-03-20 — close PR #223 review gaps in graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry tests.
- `d626c5af` — 2026-03-20 — fix `plans/preflight.sh` full-mode empty-array handling so `set -u` does not abort when the serial full-only fixture list is empty.
- `9c11df57` — 2026-03-20 — align the review-stack wrapper with the enforced skill contract, remove the stale deleted workflow test from `verify_fork`, and add a regression that every workflow test listed in verify exists on disk.
- `3e3e7f0b` — 2026-03-21 — wire `graybox_telemetry_lint` into the workflow contract and verify-gate contract checker, with a regression proving the rust gate token cannot silently drift.

## Key Files
- `crates/soldier_core/src/execution/build_order_intent.rs`
- `crates/soldier_core/src/execution/group.rs`
- `crates/soldier_core/src/execution/post_only_guard.rs`
- `crates/soldier_core/src/risk/fees.rs`
- `crates/soldier_core/src/risk/pending_exposure.rs`
- `plans/lint_graybox_telemetry.sh`
- `plans/tests/test_lint_graybox_telemetry.sh`
- `docs/codebase/upgrade2_graybox_telemetry_checklist.md`

## Debriefs
- [[Upgrade 2 Telemetry Completion 2026-03-20]]

## PR
- PR #223: https://github.com/speelbreaker12/opus-trader/pull/223

## Log
### 2026-03-20
- Finished the remaining Upgrade 2B seams in `execution/group.rs` and `execution/build_order_intent.rs`, keeping legacy wrapper metrics and traced metric-line shapes intact.
- Added graybox/parity coverage for gate-sequence, WAL-nonblocking, group lock/persist/mixed-failed, and follow-up context-preservation cases.
- Added `plans/lint_graybox_telemetry.sh` plus regression coverage and wired the guard into workflow verification so graybox logic cannot directly emit metrics, mutate global counters, or call tracing macros.
- Preserved production diagnostic context by carrying WAL errors, reservation collision identifiers, post-only bad price inputs, and invalid fee config values through internal event payloads instead of logging directly from graybox seams.
- Verified with `bash plans/tests/test_lint_graybox_telemetry.sh`, `bash plans/lint_graybox_telemetry.sh`, and `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target cargo test -p soldier_core --locked`.
- Refreshed `upgrade2` against `origin/main` with a no-op rebase, pushed the branch, opened PR #223, wrote the review-stack gate marker for HEAD `240baeaf`, and recorded that `./plans/workflow_verify.sh` is still blocked by the smoke fixture count expecting 12 instead of 13.
- Addressed the PR #223 review comments by updating the smoke fixture profile test to 13, hardening `plans/lint_graybox_telemetry.sh` for whitespace-trimmed root overrides, brace/bracket tracing macros, declaration-only `*_with_events` signatures, and `bump_*` false positives, and extending the lint regression suite for the previously untested forbidden patterns.
- Converted graybox-only post-only and fee diagnostic payloads from `f64` to `String` so the event enums regain `Eq`, added explicit `InvalidBestAsk`, `InvalidBestBid`, `InstrumentNotRegistered`, and `WalGateError` parity coverage, and aligned no-gate/precomputed WAL warning labels with the metric tags.
- Re-ran targeted validation (`bash plans/tests/test_lint_graybox_telemetry.sh`, `bash plans/tests/test_preflight_fixture_profiles.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, `cargo fmt --all -- --check`, `cargo test -p soldier_core --lib --locked`) and confirmed the old workflow fixture mismatch is gone; the remaining `plans/tests/test_pr_review_gate_hook.sh` timeout looks pre-existing and outside this branch scope.
- While resuming the merge flow, reproduced a new local `./plans/verify.sh full` blocker in `plans/preflight.sh`: bash 3.2 with `set -u` aborts on `"${FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS[@]}"` when that array is declared but empty.
- Added a runtime regression in `plans/tests/test_preflight_diagnostics.sh` that runs preflight in `full` mode with an intentionally empty full-only serial fixture list, then hardened `plans/preflight.sh` to guard empty-array appends before `+=`.
- Added matching source-shape assertions in `plans/tests/test_preflight_fixture_profiles.sh`, and re-verified with `bash plans/tests/test_preflight_diagnostics.sh` and `bash plans/tests/test_preflight_fixture_profiles.sh`.
- While resuming merge verification, fixed two additional workflow harness blockers: `.claude/commands/review-stack.md` still used the old 6-skill wrapper body instead of the enforced Skill-tool wrapper contract, and `plans/verify_fork.sh` still listed the deleted `plans/tests/test_contract_at_wording_drift.sh` in `WORKFLOW_INTEGRATION_TESTS`.
- Replaced the review-stack command wrapper with the current thin wrapper form, removed the stale deleted test from `WORKFLOW_INTEGRATION_TESTS`, and added a regression in `plans/tests/test_preflight_fixture_profiles.sh` that fails if any workflow test path named in verify no longer exists on disk.
- Re-ran targeted workflow checks (`bash plans/tests/test_review_command_wrappers.sh`, `bash plans/tests/test_preflight_fixture_profiles.sh`) and then completed `./plans/verify.sh full` successfully (`20260320_190741`).

### 2026-03-21
- Audited the live PR #223 GitHub threads/comments instead of relying on local memory, and confirmed the remaining substantive open item was the missing workflow-contract coverage for `graybox_telemetry_lint`.
- Updated `specs/WORKFLOW_CONTRACT.md` so QUICK explicitly names `graybox_telemetry_lint`, tightened `plans/verify_gate_contract_check.sh` to require the token in both quick/full Rust gate expectations, and extended `plans/tests/test_verify_gate_contract_check_batching.sh` so removing the lint from `rust_gates.sh` fails closed.
- Re-validated the fix with `bash plans/tests/test_verify_gate_contract_check_batching.sh`, `bash plans/tests/test_rust_gates_smoke_targets.sh`, and `./plans/verify_gate_contract_check.sh`.
