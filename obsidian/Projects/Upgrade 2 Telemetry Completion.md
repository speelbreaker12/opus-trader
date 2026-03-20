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
  - plans/workflow_files_allowlist.txt
  - plans/workflow_verify.sh
  - plans/lint_graybox_telemetry.sh
  - plans/tests/test_lint_graybox_telemetry.sh
  - obsidian/Projects/Upgrade 2 Telemetry Completion.md
  - obsidian/Debriefs/Upgrade 2 Telemetry Completion 2026-03-20.md
---

## Current State
Upgrade 2 is complete on branch `upgrade2` and PR #223 is open against `main`. The remaining orchestration telemetry paths were moved behind internal event sinks, the wrapper layer still preserves the existing metrics contract, and the graybox telemetry boundary is now mechanically enforced by a dedicated lint wired into workflow verification. The branch was refreshed via a no-op rebase onto `origin/main` before push. Current validation after refresh: `bash plans/lint_graybox_telemetry.sh`, `bash plans/tests/test_lint_graybox_telemetry.sh`, and `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target cargo test -p soldier_core --locked` passed; `env CARGO_TARGET_DIR=/tmp/wt_upgrade2-target ./plans/workflow_verify.sh` still stops at `wf_test_preflight_fixture_profiles` with `unexpected smoke fixture count: 13 (expected 12)`.

## Commits
- `240baeaf` — 2026-03-20 — complete Upgrade 2 graybox telemetry migration, preserve wrapper parity and diagnostic context, add graybox telemetry lint plus regression coverage.
- `pending` — 2026-03-20 — record PR #223, refresh method, review-stack marker, and post-refresh validation/handoff state.

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
