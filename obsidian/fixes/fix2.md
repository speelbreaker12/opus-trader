# Fix 2 - PR171 Follow-up After Commit 3cf8124

## Context

Historical summary of the push titled `Fix remaining PR171 review findings` on branch `origin/wip/main-pre-sync-20260304`.

## Verified Repo State

- Commit `3cf81246a5b6b75a70a829efd7c4a56bf7e05e32` exists in the current repository.
- The commit touched `plans/aggregate_proofs.sh`, `plans/parallel_review.sh`, `plans/bidi_control_guard.sh`, `crates/soldier_core/src/execution/engine.rs`, `crates/soldier_core/src/execution/engine_decision_tests.rs`, `crates/soldier_infra/src/store/ledger.rs`, and related tests.
- The original note reported targeted verification only. It did not claim a full `./plans/verify.sh full` run.

## Verification Reported In The Original Note

- `bash -n` on the touched workflow files
- `bash plans/tests/test_aggregate_proofs.sh`
- `bash plans/tests/test_bidi_control_guard.sh`
- `bash plans/tests/test_external_review_generic.sh`
- `cargo test -p soldier_core decide_pipeline_open_fails_closed_instead_of_panicking --lib`
- `cargo test -p soldier_core wal_failure --lib`
- `cargo test -p soldier_core no_gate_configured --lib`
- `cargo test -p soldier_infra legacy_reduce_only_warning_helper_logs_only_once --lib`
- `cargo test -p soldier_infra test_legacy_record_missing_reduce_only_defaults_fail_closed --test test_ledger_replay`
- `./plans/code_review_expert_attest.sh`
- `./plans/workflow_verify.sh` still stopped at the existing preflight timeout cap rather than a new assertion.
- `./plans/verify.sh full` was not run in that turn.

## Review Reruns Reported In The Original Note

- Full wrapper rerun succeeded with all four reviewers exiting `0`.
- Direct Codex-only rerun under outer `gtimeout 1800` exited `0`.
- Referenced artifacts: `summary.md`, `dispatch_status.json`, `codex.generic.md`, and `codex_outer_gtimeout.log`.

## Open Findings Captured At That Time

- P1 `premortem_gate.sh:60`: `table_rows()` still counted header rows as evidence.
- P1 `order_size.rs:142`: NaN quantization could fail open to `0`.
- P1 `order_size.rs:30`: `OrderSize` field visibility change looked like a breaking API change.
- P2 `bidi_control_guard.sh:17`: the fast `rg` path still scanned `.tmp/external-review` worktrees.
- P2 `external_review_generic.sh:190`: PR mode should pin the resolved head OID instead of `pull/<n>/head`.
- P1 `build_order_intent.rs:242`: the `Relaxed` increment on `WAL_NONBLOCKING_ALLOWED_TOTAL` could undercount under concurrency.

## Review Coverage Reported

- `aggregate_proofs.sh:27`
- `parallel_review.sh:45`
- `bidi_control_guard.sh:11`
- `test_aggregate_proofs.sh:197`
- `test_bidi_control_guard.sh:54`
- `engine.rs:300`
- `engine_decision_tests.rs:312`
- `ledger.rs:27`
- `plans/progress.txt:1022`

## Recommended Next Step

Treat this as a historical checkpoint, not a clean bill of health. If it remains an active handoff note, explicitly mark the disposition of all six findings above before using it to drive the next change.
