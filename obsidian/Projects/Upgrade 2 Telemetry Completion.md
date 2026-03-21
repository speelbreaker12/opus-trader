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
  - crates/soldier_core/src/execution/dispatch_chokepoint_contract_tests.rs
  - crates/soldier_core/src/execution/gate.rs
  - crates/soldier_core/src/execution/group.rs
  - crates/soldier_core/src/execution/inventory_skew.rs
  - crates/soldier_core/src/execution/inventory_skew_tests.rs
  - crates/soldier_core/src/execution/post_only_guard.rs
  - crates/soldier_core/src/execution/post_only_guard_tests.rs
  - crates/soldier_core/src/execution/preflight.rs
  - crates/soldier_core/src/execution/preflight_tests.rs
  - crates/soldier_core/src/execution/pricer.rs
  - crates/soldier_core/src/execution/pricer_tests.rs
  - crates/soldier_core/src/execution/quantize.rs
  - crates/soldier_core/src/execution/routing.rs
  - crates/soldier_core/src/risk/exposure_budget.rs
  - crates/soldier_core/src/risk/fees.rs
  - crates/soldier_core/src/risk/margin_gate.rs
  - crates/soldier_core/src/risk/margin_gate_tests.rs
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
  - obsidian/Debriefs/Upgrade 2 Telemetry Completion 2026-03-21.md
---

## Current State
The previously open Upgrade 2 review gaps are fixed on branch `upgrade2`, but the branch is not ready to be called complete again yet. Preflight now routes post-only through the sink seam, the missing crossing graybox test exists, the remaining leaf seams moved inline instance-metric mutation into observer sinks, routing no longer bypasses the WAL-nonblocking chokepoint sink, and the graybox lint now catches both inline `metrics.record_*()` calls and wrapper-call bypasses. Fresh targeted validation is green (`cargo fmt --all`, `bash plans/lint_graybox_telemetry.sh`, `bash plans/tests/test_lint_graybox_telemetry.sh`, `cargo clippy --workspace --lib -- -D warnings`, `cargo test -p soldier_core --lib -- --nocapture`), but `./plans/verify.sh quick` failed in `wf_test_pr_review_gate_hook` (`artifacts/verify/20260321_100806`), which is outside this slice.

## Commits
- `pending` — 2026-03-21 — close the remaining Upgrade 2 review gaps in preflight/post-only, observer-sink telemetry purity, routing WAL no-gate diagnostics, and graybox lint coverage; targeted validation green, quick verify blocked by unrelated workflow hook failure.
- `240baeaf` — 2026-03-20 — complete Upgrade 2 graybox telemetry migration, preserve wrapper parity and diagnostic context, add graybox telemetry lint plus regression coverage.
- `1b33802d` — 2026-03-20 — close PR #223 review gaps in graybox lint coverage, smoke fixture accounting, event payload typing, and wrapper/graybox telemetry tests.
- `d626c5af` — 2026-03-20 — fix `plans/preflight.sh` full-mode empty-array handling so `set -u` does not abort when the serial full-only fixture list is empty.
- `9c11df57` — 2026-03-20 — align the review-stack wrapper with the enforced skill contract, remove the stale deleted workflow test from `verify_fork`, and add a regression that every workflow test listed in verify exists on disk.
- `3e3e7f0b` — 2026-03-21 — wire `graybox_telemetry_lint` into the workflow contract and verify-gate contract checker, with a regression proving the rust gate token cannot silently drift.

## Key Files
- `crates/soldier_core/src/execution/build_order_intent.rs`
- `crates/soldier_core/src/execution/gate.rs`
- `crates/soldier_core/src/execution/post_only_guard.rs`
- `crates/soldier_core/src/execution/preflight.rs`
- `crates/soldier_core/src/execution/quantize.rs`
- `crates/soldier_core/src/execution/pricer.rs`
- `crates/soldier_core/src/execution/inventory_skew.rs`
- `crates/soldier_core/src/risk/margin_gate.rs`
- `crates/soldier_core/src/risk/pending_exposure.rs`
- `crates/soldier_core/src/risk/exposure_budget.rs`
- `plans/lint_graybox_telemetry.sh`
- `plans/tests/test_lint_graybox_telemetry.sh`
- `docs/codebase/upgrade2_graybox_telemetry_checklist.md`

## Debriefs
- [[Upgrade 2 Telemetry Completion 2026-03-20]]
- [[Upgrade 2 Telemetry Completion 2026-03-21]]

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
- Closed the still-open Upgrade 2 review gaps by routing preflight post-only checks through `check_post_only_with_events(...)`, adding the missing crossing-reject graybox test, moving remaining leaf instance-metric mutation into observer sinks, and routing `no_gate_configured` WAL visibility through the chokepoint sink instead of direct logging/counter bumps.
- Tightened `plans/lint_graybox_telemetry.sh` so graybox seams now fail on inline `metrics.record_*()` calls and wrapper-call bypasses such as `check_post_only(...)`, then added regression fixtures proving both patterns fail closed.
- Re-validated the telemetry slice with `cargo fmt --all`, `bash plans/lint_graybox_telemetry.sh`, `bash plans/tests/test_lint_graybox_telemetry.sh`, `cargo clippy --workspace --lib -- -D warnings`, and `cargo test -p soldier_core --lib -- --nocapture`.
- Ran `./plans/verify.sh quick`; the Upgrade 2 slice stayed green, but the run failed outside this scope in `wf_test_pr_review_gate_hook` (`artifacts/verify/20260321_100806/FAILED_GATE`) because the workflow test still expects `gh pr create` to hard-block without a review marker while the current hook only warns and allows the command to proceed.
