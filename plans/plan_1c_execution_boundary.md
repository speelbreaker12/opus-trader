# 1B Execution Boundary + 1C Facade Lockdown Final Plan

## Goal
Complete the remaining 1B execution-boundary fix and finish 1C facade lockdown for `risk`, `venue`, and `soldier_infra` without unnecessary public API churn.

## Guiding decisions
- Keep the public trait name `RecordedBeforeDispatchGate`; move its definition only.
- Keep `ExecutionRuntime` stable in this story; do not introduce a new public `runtime.rs`.
- Make `routing.rs` the only execution module allowed to import `open_runtime` or `pipeline`.
- Extend the existing execution facade pattern to `risk`, `venue`, and `soldier_infra`: exact export allowlist, external-surface smoke test, internal completeness counterpart, and workflow-backed lint fixtures.
- Treat every new `plans/*` and `plans/tests/*` asset as workflow surface that must be wired into preflight, verify, and workflow allowlist controls.

## File map

### 1B execution boundary
- Create: `crates/soldier_core/src/execution/routing.rs`
- Create: `crates/soldier_core/src/execution/wal_gate.rs`
- Modify: `crates/soldier_core/src/execution/engine.rs`
- Modify: `crates/soldier_core/src/execution/build_order_intent.rs`
- Modify: `crates/soldier_core/src/execution/pipeline.rs`
- Modify: `crates/soldier_core/src/execution/api.rs`
- Modify: `crates/soldier_core/src/execution/mod.rs`
- Modify: `plans/lint_execution_facade.sh`
- Modify: `plans/tests/test_lint_execution_facade.sh`
- Optional comment-only touch if helpful: `crates/soldier_core/src/execution/open_runtime.rs`
- Optional comment-only touch if helpful: `crates/soldier_core/src/execution/pipeline.rs`

### 1C facade lockdown
- Create: `plans/risk_facade_symbols.txt`
- Create: `plans/lint_risk_facade.sh`
- Create: `plans/tests/test_lint_risk_facade.sh`
- Create: `crates/soldier_core/tests/test_risk_facade_public.rs`
- Create: `crates/soldier_core/src/risk/facade_completeness_contract_tests.rs`
- Modify: `crates/soldier_core/src/risk/mod.rs`

- Create: `plans/venue_facade_symbols.txt`
- Create: `plans/lint_venue_facade.sh`
- Create: `plans/tests/test_lint_venue_facade.sh`
- Create: `crates/soldier_core/tests/test_venue_facade_public.rs`
- Create: `crates/soldier_core/src/venue/facade_completeness_contract_tests.rs`
- Modify: `crates/soldier_core/src/venue/mod.rs`

- Create: `plans/soldier_infra_facade_symbols.txt`
- Create: `plans/lint_soldier_infra_facade.sh`
- Create: `plans/tests/test_lint_soldier_infra_facade.sh`
- Create: `crates/soldier_infra/tests/test_soldier_infra_facade_public.rs`
- Create: `crates/soldier_infra/src/facade_completeness_contract_tests.rs`
- Modify: `crates/soldier_infra/src/lib.rs`

### Harness wiring
- Modify: `plans/lib/rust_gates.sh`
- Modify: `plans/preflight.sh`
- Modify: `plans/verify_fork.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify if required by workflow-surface policy: `plans/tests/test_workflow_allowlist_coverage.sh`

## Plan

### Task 1: Fix the remaining execution boundary leak with minimal churn

**Intent**
`engine.rs` should stop importing execution internals directly. Keep the public surface stable and move only the boundary-owning logic.

- [ ] Create `crates/soldier_core/src/execution/wal_gate.rs` containing only:
  - `pub trait RecordedBeforeDispatchGate { fn record_before_dispatch(&mut self) -> Result<(), String>; }`
- [ ] Update `crates/soldier_core/src/execution/build_order_intent.rs` to import `RecordedBeforeDispatchGate` from `super::wal_gate` and remove the in-file trait definition.
- [ ] Keep a compatibility `pub(crate) use super::wal_gate::RecordedBeforeDispatchGate;` re-export in `build_order_intent.rs` unless every existing internal caller is migrated in this story.
- [ ] Update `crates/soldier_core/src/execution/api.rs` to re-export `RecordedBeforeDispatchGate` from `super::wal_gate`. Keep `GateStep` sourced from `super::build_order_intent` unchanged.
- [ ] Update `crates/soldier_core/src/execution/pipeline.rs` to import `RecordedBeforeDispatchGate` from the stable location used by the final design, preserving compileability during the trait move.
- [ ] Create `crates/soldier_core/src/execution/routing.rs` and move the routing-only helpers out of `engine.rs`, including:
  - `build_open_runtime_input`
  - `build_pipeline_input`
  - `pipeline_wal_recorded`
  - `pipeline_result_to_decision`
  - `open_runtime_to_decision`
  - the rejection-step / rejection-code mapping helpers
  - their transitive private helpers: `build_base_gates_input`, `map_l2_snapshot`, `map_order_type`, and `WalRecordOutcome`
  - any remaining private helper functions that only exist to bridge `engine.rs` to `open_runtime` or `pipeline`
- [ ] Add two `pub(crate)` entry points in `routing.rs`:
  - `route_open(...) -> ExecutionDecision`
  - `route_pipeline(...) -> ExecutionDecision`
- [ ] Preserve the CSP.3.1 ordering invariant in `route_open`: the WAL gate must record before dispatch and before `build_open_order_intent_runtime(...)` is called.
- [ ] Update `crates/soldier_core/src/execution/engine.rs` so it:
  - imports `RecordedBeforeDispatchGate` from `wal_gate`
  - no longer imports `open_runtime` or `pipeline`
  - keeps only the public types, runtime container, and top-level dispatch selection
  - delegates `decide_open` and `decide_pipeline` to `routing::route_open` / `routing::route_pipeline`
- [ ] Update `crates/soldier_core/src/execution/mod.rs` with private `mod routing;` and `mod wal_gate;`.
- [ ] Do not rename `RecordedBeforeDispatchGate`.
- [ ] Do not introduce a new public `runtime.rs`.
- [ ] Do not remove the deprecated `ExecutionEngine::evaluate` alias in this story.

### Task 2: Tighten execution facade lint so the boundary is enforced mechanically

**Intent**
The execution boundary should fail closed if `engine.rs` or another module starts importing `open_runtime` or `pipeline` again.

- [ ] Extend `plans/lint_execution_facade.sh` with env-var overrides for:
  - `LINT_EXECUTION_FACADE_ENGINE`
  - `LINT_EXECUTION_FACADE_ROUTING`
- [ ] Add a multi-line-aware check that fails if `engine.rs` imports `open_runtime` or `pipeline`, including grouped `use super::{ ... }` forms.
- [ ] Add a second check that fails if any non-test execution Rust file other than `routing.rs` imports `open_runtime` or `pipeline`.
- [ ] Exempt execution test-only files such as `*_tests.rs` from the routing-boundary import ban.
- [ ] Keep the exact-export allowlist behavior already used for `execution/api.rs`.
- [ ] Extend `plans/tests/test_lint_execution_facade.sh` with a negative fixture proving grouped or multi-line imports in `engine.rs` fail.

### Task 3: Roll out full facade enforcement for `risk`

**Intent**
Match the execution facade pattern exactly: explicit export contract, external-surface smoke test, internal completeness proof, and deterministic lint fixtures.

- [ ] Generate `plans/risk_facade_symbols.txt` from `crates/soldier_core/src/risk/api.rs`; do not hand-maintain the initial symbol list.
- [ ] Create `plans/lint_risk_facade.sh` by adapting the execution lint pattern to `risk`.
- [ ] Create `crates/soldier_core/tests/test_risk_facade_public.rs` mirroring the execution external-surface test shape and importing only through `soldier_core::risk::{...}`.
- [ ] Create `crates/soldier_core/src/risk/facade_completeness_contract_tests.rs` as the unit-side counterpart.
- [ ] Modify `crates/soldier_core/src/risk/mod.rs` to include the internal completeness test module under test-only compilation.
- [ ] Create `plans/tests/test_lint_risk_facade.sh` with:
  - positive fixture on the real files
  - negative `pub mod` leakage case
  - negative “extra export not in allowlist” case
  - negative deep-import case for crate-internal `use crate::risk::<submodule>::...`

### Task 4: Roll out full facade enforcement for `venue`

- [ ] Generate `plans/venue_facade_symbols.txt` from `crates/soldier_core/src/venue/api.rs`.
- [ ] Create `plans/lint_venue_facade.sh` using the same exact-export and private-module checks as `execution` and `risk`.
- [ ] Create `crates/soldier_core/tests/test_venue_facade_public.rs`.
- [ ] Create `crates/soldier_core/src/venue/facade_completeness_contract_tests.rs`.
- [ ] Modify `crates/soldier_core/src/venue/mod.rs` to include the internal completeness test module under test-only compilation.
- [ ] Create `plans/tests/test_lint_venue_facade.sh` with the same positive and negative fixture coverage used for `risk`.

### Task 5: Roll out full facade enforcement for `soldier_infra`

- [ ] Generate `plans/soldier_infra_facade_symbols.txt` from `crates/soldier_infra/src/api.rs`.
- [ ] Create `plans/lint_soldier_infra_facade.sh`.
- [ ] Create `crates/soldier_infra/tests/test_soldier_infra_facade_public.rs` importing only through `soldier_infra::{...}`.
- [ ] Create `crates/soldier_infra/src/facade_completeness_contract_tests.rs`.
- [ ] Modify `crates/soldier_infra/src/lib.rs` to include the internal completeness test module under test-only compilation.
- [ ] Create `plans/tests/test_lint_soldier_infra_facade.sh` with the same positive and negative fixture coverage pattern.
- [ ] Do not spend time on `crates/soldier_infra/tests/test_deribit_instrument.rs`; its root-level imports are already migrated.

### Task 6: Wire new facade checks into the workflow surface

**Intent**
New harness scripts must run in the fast loop, in verify, and inside workflow-surface controls.

- [ ] Add the new facade smoke tests and real-tree lints to `plans/lib/rust_gates.sh` so `./plans/verify.sh quick` and `./plans/verify.sh full` enforce them on repository sources:
  - `cargo test -p soldier_core --test test_risk_facade_public`
  - `cargo test -p soldier_core --test test_venue_facade_public`
  - `cargo test -p soldier_infra --test test_soldier_infra_facade_public`
  - `bash plans/lint_risk_facade.sh`
  - `bash plans/lint_venue_facade.sh`
  - `bash plans/lint_soldier_infra_facade.sh`
- [ ] Add the new facade lint fixture tests to the preflight smoke list in `plans/preflight.sh`:
  - `plans/tests/test_lint_risk_facade.sh`
  - `plans/tests/test_lint_venue_facade.sh`
  - `plans/tests/test_lint_soldier_infra_facade.sh`
- [ ] Add the same three tests to `WORKFLOW_INTEGRATION_TESTS` in `plans/verify_fork.sh`.
- [ ] Add every new workflow asset to `plans/workflow_files_allowlist.txt`, including:
  - the three new `plans/lint_*_facade.sh` scripts
  - the three new `plans/*_facade_symbols.txt` allowlists
  - the three new `plans/tests/test_lint_*_facade.sh` test scripts
- [ ] Update `plans/tests/test_workflow_allowlist_coverage.sh` if the repo’s workflow-surface convention requires newly critical files to be pinned in the required list.
- [ ] Keep all new workflow checks deterministic and fail closed.

## Verification plan

### Pre-flight sanity check
- [ ] Confirm the current facade shape before editing:
  - `crates/soldier_core/src/risk/mod.rs`
  - `crates/soldier_core/src/venue/mod.rs`
  - `crates/soldier_infra/src/lib.rs`
- [ ] Expected state: private `mod api;` plus `pub use api::*;` and no `pub mod` leakage.

### Targeted checks during implementation
- [ ] `cargo build -p soldier_core`
- [ ] `plans/lint_execution_facade.sh`
- [ ] `plans/tests/test_lint_execution_facade.sh`
- [ ] `plans/lint_risk_facade.sh`
- [ ] `plans/lint_venue_facade.sh`
- [ ] `plans/lint_soldier_infra_facade.sh`
- [ ] `cargo test -p soldier_core --lib`
- [ ] `cargo test -p soldier_infra --lib`
- [ ] `cargo test -p soldier_core --test test_execution_facade_public`
- [ ] `cargo test -p soldier_core --test test_risk_facade_public`
- [ ] `cargo test -p soldier_core --test test_venue_facade_public`
- [ ] `cargo test -p soldier_infra --test test_soldier_infra_facade_public`
- [ ] `./plans/lib/rust_gates.sh` in quick-compatible mode once the new facade smoke tests and lints are wired

### Workflow / harness verification
- [ ] `./plans/workflow_verify.sh` once the harness-file changes are in place
- [ ] `./plans/preflight.sh`
- [ ] `./plans/verify.sh quick`
- [ ] `./plans/verify.sh full` before any `passes=true` flip
- [ ] `./plans/prd_set_pass.sh` only after the full verify artifacts are green and valid

## Non-goals
- No public rename from `RecordedBeforeDispatchGate` to `PreDispatchRecorder`.
- No new public `execution/runtime.rs` abstraction in this story.
- No broader refactor of open/pipeline internals beyond the routing boundary extraction.

## Assumptions
- `risk`, `venue`, and `soldier_infra` already have the intended private-module facade shape; if that assumption is false, stop and rescope before adding lint/tests.
- The existing execution facade test pattern is the source-of-truth template for new facade public/completeness tests.
- If local full verify is blocked by a dirty worktree, follow the repo dirty-worktree policy and rely on CI rather than forcing `VERIFY_ALLOW_DIRTY=1`.
