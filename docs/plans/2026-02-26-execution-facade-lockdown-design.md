# Execution Module Facade Lockdown — Design

**Date:** 2026-02-26
**Scope:** `crates/soldier_core/src/execution/` only (Phase 1)
**Approach:** Option 4 — Split tests by contract vs internals

## Problem

`execution/mod.rs` exports 19 `pub mod` sub-modules with ~120 re-exported symbols.
Every internal wire type (`LiquidityGateInput`, `PricerInput`, `NetEdgeInput`, etc.)
is reachable by any crate. This invites coupling — an AI agent or future crate can
import `execution::gate::some_internal_fn` and nobody notices until refactoring breaks
everything.

Compounding issue: `verify.sh quick` runs `cargo test --workspace --lib`. The ~100
gate-level tests sitting in `crates/soldier_core/tests/` are invisible to the fast
feedback loop. The most important safety tests (fail-closed gates) only run during
`verify.sh full`.

## Principles

1. **Contract is defined by production consumers, not tests.**
   When a test needs `LiquidityGateInput`, the question is not "can we re-export it?"
   It's: "Should any production consumer ever need to construct this type?"
   If the answer is no, keep it private and change the test strategy.

2. **Integration tests must not drag internals into the contract.**
   `crates/soldier_core/tests/common/mod.rs` currently imports gate-level wire types.
   If we blindly require "integration tests must compile using only the facade," we'll
   be tempted to re-export all of that and call it "the contract." That's how deep
   modules die: the public interface becomes a mirror of internals.

3. **The fast feedback loop must include contract tests.**
   If the most valuable contract tests live exclusively in `crates/soldier_core/tests/`
   and `verify.sh quick` skips them, the fast loop can pass while the contract is broken.
   That's a TOC constraint violation.

## Public API Decision — Phased Approach

**Phase 1 (this design): Facade + module privacy only.**
Wire types (`LiquidityGateInput`, `PricerInput`, `NetEdgeInput`, etc.) remain `pub`.
Module paths become private (`pub mod` → `mod`). All external access goes through the
facade (`execution::{...}` only). This gives boundary protection now with zero
compilation risk.

**Why not `pub` → `pub(crate)` in Phase 1?** `OpenRuntimeInput`, `IntentPipelineInput`,
and `AssembledPipelineParams` embed gate wire types as public fields. Making those field
types `pub(crate)` while the containing structs remain `pub` will not compile — Rust
requires public struct fields to use public types. Hiding wire types requires either
making those structs opaque or replacing them with contract-level input types, both of
which are Phase 2 work.

**Phase 2 (future design): Contract input types + wire type internalization.**
Introduce `ExecutionInput` / `ExecutionEngine::decide()` that does not expose gate
inputs. Only then do gate wire types become `pub(crate)`. This is the proper deep-module
boundary — see §12.

## Goals

1. **Compiler-enforced privacy**: internal modules become `mod` (not `pub mod`).
   External crates cannot reach gate internals via deep module paths.
2. **Centralized facade**: all public re-exports live in `api.rs`.
   Wire types remain `pub` in their source files but are **unreachable outside
   `soldier_core`** because their parent modules are private (`mod`, not `pub mod`)
   and they are **not re-exported** in `api.rs`. Phase 2 converts them to
   `pub(crate)` for defense-in-depth.
3. **Fast feedback**: gate unit tests move next to the code (`#[cfg(test)]`), running
   in `verify.sh quick` (`--lib`).
4. **Contract-only integration tests**: `crates/soldier_core/tests/` imports only
   from the facade. Black-box, not white-box.
5. **Contract tests in the fast loop**: `verify.sh quick` gains a smoke-contract lane
   that runs high-value contract integration tests.

## Design

### 1. Module Visibility — `pub mod` → `mod`

```rust
// crates/soldier_core/src/execution/mod.rs

//! Execution module facade.
//! Public API is defined in `api.rs` — read that file first.

pub mod api;                    // the only public surface

mod base_gates;
mod build_order_intent;
mod dispatch_map;
mod gate;
mod gate_outcome;
mod gates;
mod group;
mod intent_assembly;
mod inventory_skew;
mod label;
mod open_runtime;
mod order_size;
mod pipeline;
mod post_only_guard;
mod preflight;
mod pricer;
mod quantize;
mod reject_reason;
mod tlsm;

// Re-export public API at module level for backwards compat
// with contract-level imports like `execution::Side`.
pub use api::*;
```

Public re-exports live in `api.rs`. No new public exports may be added outside
`api.rs`.

**Telemetry helpers — contract decision:** `with_intent_trace_ids()` and
`take_execution_metric_lines()` are currently `pub fn` in `mod.rs`, but their
only callers are integration tests in `soldier_core/tests/` (4 test files — all
in the "must move" table). Zero callers in `soldier_infra`. Zero production callers.
**These are not contract.** In Step 2, when those test files move to `#[cfg(test)]`
unit tests, change both functions to `pub(crate)`. The moved tests retain access
(same crate). `emit_execution_metric_line` is already `pub(crate)` and stays.

### 2. Public Facade — `api.rs` (contract types only)

**Phase 1 contract has two tiers:**

- **Execution contract** = chokepoint boundary (WAL-safe `build_order_intent_with_*`,
  `ChokeResult`, `GateResults`, `RejectReasonCode`) + lifecycle primitives needed by
  `soldier_infra` and contract-level integration tests (`Tlsm*`, `AtomicGroup*`,
  `Label*`, `Side`, `OrderSize`, `RecordedBeforeDispatchGate`). Deprecated chokepoint
  functions (`build_order_intent`, `build_order_intent_with_reject_reason_code`) are
  excluded — clippy `-D warnings` flags any consumer.
- **Pipeline contract** = none. Pipeline wiring (`evaluate_intent_pipeline`,
  `IntentPipelineInput`, gate wire types, assembly params) is internal. Unit-tested
  only. Not in the facade.

This split forces test placement: if a test needs pipeline internals, it's a unit
test. If it tests through the chokepoint or lifecycle primitives, it's a contract
integration test.

The decision tree for each symbol:

```
Should any production consumer or contract integration test need this type?
├── YES (chokepoint/lifecycle) → export in api.rs, freeze it
└── NO  (pipeline wiring)      → omit from api.rs, unit-test only
```

**Critical finding:** `IntentPipelineInput`, `OpenRuntimeInput`, and
`AssembledPipelineParams` all contain gate-level wire types as fields
(`liquidity: Option<LiquidityGateInput>`, `net_edge_input: NetEdgeInput`, etc.).
These are internal wiring, not contract. In Phase 1, they remain `pub` (because
their field types must also be `pub`), but are **not re-exported in `api.rs`** and
are unreachable through the facade since their parent modules are private.
Phase 2 introduces contract input types that replace these structs, enabling
`pub` → `pub(crate)` on wire types.

```rust
// crates/soldier_core/src/execution/api.rs

//! # Execution Pipeline — Public API
//!
//! This file defines the complete public surface of the execution module.
//! If a type is not re-exported here, it is an internal implementation detail.
//!
//! RULE: The contract is defined by production consumers, not tests.
//! A type is public only if an external crate needs it in production
//! or in a contract-level integration test that stays in tests/.
//!
//! RULE: crates/soldier_core/tests/* may only import execution symbols
//! through this facade — never via execution::<submodule>::... deep paths.
//! (Tests may freely import from other top-level modules like `risk`,
//! `venue`, `idempotency`, etc.)
//! Anything needing gate-internal types belongs in #[cfg(test)] unit tests.
//!
//! RULE: Signature closure. Every exported item must be signature-closed:
//! if you export a function, every type in its public signature (arguments +
//! return type) must also be reachable through this facade — directly or via
//! std/primitives. If you don't want a dependency type public, remove the
//! function from the facade; don't fight Rust.

// ── Chokepoint Boundary (10 symbols) ──
pub use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult,
    GateResults, GateStep, RecordedBeforeDispatchGate,
    build_gate_results,
    build_order_intent_with_wal_gate,
    build_order_intent_with_optional_wal_gate,
};
// CUT: build_order_intent — deprecated (accepts precomputed wal_recorded, bypasses
//      real WAL append). Callers should use build_order_intent_with_wal_gate or
//      build_order_intent_with_optional_wal_gate. Remains accessible inside crate.
// CUT: build_order_intent_with_reject_reason_code — #[deprecated] (wraps deprecated
//      build_order_intent). Exporting it contaminates the facade: clippy -D warnings
//      in verify.sh full will flag any test that references it. WAL-safe chokepoint
//      functions are the only non-deprecated contract entry points.
// CUT: GateSequenceResult, gate_sequence_total (sole consumer test_gate_ordering → must-move)

// ── Reject Reason (4 symbols) ──
pub use super::reject_reason::{
    GateRejectCodes, RejectReasonCode,
    reject_reason_registry, reject_reason_registry_contains,
};
// CUT: reject_reason_from_chokepoint (zero external consumers)
// CUT: PipelineResult (return type of excluded evaluate_intent_pipeline)

// ── Gate Outcome ──
// CUT: GateOutcome (sole consumer test_gate_outcome → must-move; source: gate_outcome module)

// ── Domain Primitives (2 symbols) ──
pub use super::quantize::Side;
pub use super::order_size::OrderSize;
// CUT: build_order_size — returns Result<OrderSize, OrderSizeError>, sole consumers are
//      must-move tests. Principle #1: contract defined by production consumers, not tests.
// CUT: OrderSizeInput — only useful with build_order_size (also cut)
// CUT: OrderSizeError — return type of cut build_order_size
// CUT: DispatchConsistencyProof, DispatchRequest, ValidatedDispatch (zero external consumers)
// CUT: IntentClass (sole consumer test_dispatch_map → must-move)

// ── Label (6 symbols) ──
pub use super::label::{
    LABEL_MAX_LEN, LabelError, LabelInput,
    derive_gid12, derive_sid8, encode_label,
};
// CUT: decode_label — returns Result<ParsedLabel, LabelError>; ParsedLabel has zero
//      external production consumers. Moving decode_label internal keeps the facade clean.
// CUT: ParsedLabel — return type of cut decode_label

// ── Group Atomicity (9 symbols) ──
pub use super::group::{
    AtomicGroup, GroupConfig, GroupError, GroupLock,
    GroupState, GroupStateTransition, LegResult,
    LockAcquisitionResult,
    try_acquire_group_lock,
};
// CUT: persist_before_dispatch — signature requires `&mut dyn GroupPersistence` (trait cut).
//      Zero external production consumers. Internal-only.
// CUT: GroupPersistence — trait, zero external implementors
// CUT: InMemoryGroupPersistence — concrete impl of GroupPersistence (cut trait). Its only
//      external consumer is test_atomic_group.rs which calls persist_before_dispatch (also
//      cut). Orphaned in the facade without the trait. Persistence tests move to group.rs
//      #[cfg(test)] unit tests where InMemoryGroupPersistence remains accessible.
// CUT: group_lock_timeout_total, group_mixed_failed_total, group_persist_fail_total
//      (sole consumer test_static_rejection_counters → must-move; §10: metrics not contract)

// ── Trade Lifecycle State Machine (8 symbols) ──
pub use super::tlsm::{
    OooCategory, PersistedTransition, Tlsm,
    TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink,
    TransitionResult,
};
// CUT: NoopTransitionSink (zero external consumers — test utility, move to #[cfg(test)])
// CUT: ooo_count, ooo_total (sole consumer test_tlsm; §10: metrics not contract)
```

**Signature-closure audit checklist** — applied during the design of `api.rs` above:

| Exported item | Signature types | All reachable? | Action |
|---------------|----------------|----------------|--------|
| `build_order_intent_with_wal_gate` | `ChokeIntentClass`, `RiskState`¹, `ChokeMetrics`, `GateResults`, `RecordedBeforeDispatchGate` | Yes | — |
| `build_order_intent_with_optional_wal_gate` | Same + `Option<&mut dyn RecordedBeforeDispatchGate>` | Yes | — |
| `build_gate_results` | returns `GateResults`, args are primitives | Yes | — |
| `build_order_intent` | `ChokeMetrics`, `GateResults`, `bool` (wal_recorded) | ~~Yes~~ | **CUT** — deprecated, bypasses WAL |
| `build_order_intent_with_reject_reason_code` | `RejectReasonCode`, `GateRejectCodes`, `ChokeResult` | Yes | **CUT** — `#[deprecated]`, wraps deprecated `build_order_intent`; clippy `-D warnings` flags any consumer |
| `build_order_size` | `OrderSizeInput` → `Result<OrderSize, OrderSizeError>` | No (`OrderSizeError` cut) | **CUT** — zero production consumers |
| `decode_label` | returns `Result<ParsedLabel, LabelError>` | No (`ParsedLabel` cut) | **CUT** — zero production consumers |
| `persist_before_dispatch` | `&mut dyn GroupPersistence` | No (`GroupPersistence` cut) | **CUT** — zero production consumers |
| All other exports | primitives, `String`, `Result`, already-exported types | Yes | — |

¹ `RiskState` is public from `soldier_core::risk`, not from `execution::api`. That's fine — it's reachable.

**Excluded from facade** — unreachable via `execution::{...}` since parent modules
are private; `pub` → `pub(crate)` deferred to Phase 2:

| Category | Types excluded from facade | Reason |
|----------|--------------------------|--------|
| **Chokepoint internals** | `GateSequenceResult`, `gate_sequence_total` | Sole consumer test_gate_ordering → must-move |
| **Pipeline types** | `PipelineResult`, `GateOutcome`, `IntentPipelineInput`, `IntentPipelineMetrics`, `QuantizePipelineInput`, `evaluate_intent_pipeline` | Return type / input of excluded functions; zero surviving consumers |
| **Assembly wiring** | `AssembledPipelineParams`, `SizingParams`, `assemble_sizing`, `choke_intent_to_dispatch`, `evaluate_assembled_pipeline`, `AssemblySizingError`, `AssembledSizing` | Internal pipeline wiring |
| **OPEN runtime wiring** | `OpenRuntimeInput`, `OpenRuntimeMetrics`, `OpenRuntimeOutput`, `build_open_intent_with_assembly`, `build_open_order_intent_runtime`, `settle_pending_on_tlsm_terminal` | Internal pipeline wiring |
| **Liquidity gate** | `LiquidityGateInput`, `LiquidityGateResult`, `LiquidityGateDecision`, `LiquidityGateRejectReason`, `LiquidityGateMetadata`, `LiquidityGateMetrics`, `GateIntentClass`, `L2BookSnapshot`, `L2Level`, `evaluate_liquidity_gate`, `expected_slippage_bps_samples`, `liquidity_gate_reject_total` | Gate internals |
| **Net edge gate** | `NetEdgeInput`, `NetEdgeResult`, `NetEdgeRejectReason`, `NetEdgeMetrics`, `evaluate_net_edge`, `net_edge_reject_total` | Gate internals |
| **Pricer gate** | `PricerInput`, `PricerResult`, `PricerRejectReason`, `PricerMetrics`, `compute_limit_price`, `pricer_reject_total` | Gate internals |
| **Quantize gate** | `QuantizeConstraints`, `QuantizeError`, `QuantizeMetrics`, `QuantizeStaticRejectReason`, `QuantizedValues`, `quantize`, `quantize_reject_total` (`Side` stays public) | Gate internals |
| **Preflight gate** | `PreflightInput`, `PreflightResult`, `PreflightReject`, `PreflightMetrics`, `OrderType`, `preflight_intent`, `preflight_reject_total` | Gate internals |
| **Base gates** | `BaseGatesInput`, `BaseGatesLegacy`, `BaseGatesMetrics`, `BaseGatesPassed`, `BaseGatesRejection`, `evaluate_base_gates` | Gate internals |
| **Post-only guard** | `PostOnlyInput`, `PostOnlyResult`, `PostOnlyMetrics`, `check_post_only`, `post_only_reject_total` | Gate internals |
| **Inventory skew** | `InventorySkewInput`, `InventorySkewResult`, `InventorySkewRejectReason`, `InventorySkewMetrics`, `evaluate_inventory_skew`, `inventory_skew_reject_total` | Gate internals |
| **Dispatch map** | `DispatchConsistencyProof`, `DispatchRequest`, `ValidatedDispatch`, `IntentClass`, `DispatchMapError`, `CONTRACTS_AMOUNT_MATCH_TOLERANCE`, `MismatchMetrics`, `map_to_dispatch`, `validate_and_dispatch` | Zero consumers or must-move only |
| **Domain types** | `OrderSizeError`, `OrderSizeInput`, `build_order_size`, `ParsedLabel`, `decode_label` | Signature-closure: `build_order_size` returns `OrderSizeError` (cut); `decode_label` returns `ParsedLabel` (cut). Zero production consumers for both functions. |
| **Group internals** | `GroupPersistence`, `persist_before_dispatch`, `group_lock_timeout_total`, `group_mixed_failed_total`, `group_persist_fail_total` | `persist_before_dispatch` requires `&mut dyn GroupPersistence` (cut trait). Metrics §10 rule. |
| **Chokepoint deprecated** | `build_order_intent`, `build_order_intent_with_reject_reason_code` | Both `#[deprecated]`. `build_order_intent` bypasses WAL; `_with_reject_reason_code` wraps it. Exporting deprecated functions contaminates the facade: clippy `-D warnings` flags any consumer in `verify.sh full`. |
| **Group orphaned** | `InMemoryGroupPersistence` | Concrete impl of `GroupPersistence` (cut trait). Sole external consumer is `test_atomic_group.rs` `persist_before_dispatch` tests (also cut). Orphaned without the trait — keeping it in the facade invites reimport of the trait. |
| **TLSM internals** | `NoopTransitionSink`, `ooo_count`, `ooo_total` | Test utility zero consumers; metrics §10 rule |
| **Reject reason** | `reject_reason_from_chokepoint` | Zero external consumers |

### 3. Internal Wire Types — Phase 1 vs Phase 2

**Phase 1 (this design):** Wire types remain `pub` in their source files. Privacy
is enforced structurally — their parent modules are `mod` (not `pub mod`), so external
crates cannot reach them. Within `soldier_core`, they remain fully accessible for
pipeline wiring and `#[cfg(test)]` unit tests. Integration tests in `tests/` also
cannot reach them (module is private), which is the forcing function for test moves.

**Phase 2 (future):** Once contract-level input types (`ExecutionInput` /
`ExecutionEngine::decide()`) replace the pipeline wiring structs, then wire types
can become `pub(crate)`:

```rust
// Phase 2 ONLY (gate.rs) — after contract input types exist
pub(crate) struct LiquidityGateInput { ... }
pub(crate) fn evaluate_liquidity_gate(...) -> LiquidityGateResult { ... }
```

**Do not attempt `pub` → `pub(crate)` in Phase 1.** `OpenRuntimeInput`,
`IntentPipelineInput`, and `AssembledPipelineParams` embed these types as public
fields. Making field types `pub(crate)` while the containing struct is `pub` is a
compile error.

### 4. Move Tests — `tests/` → `#[cfg(test)]` Unit Tests

Each integration test file that touches internal wire types gets moved next to the code
it tests. These tests immediately start running in `verify.sh quick`.

**Tests that MUST move** (they construct internal wire types):

| Integration test file | Move to |
|----------------------|---------|
| `tests/test_liquidity_gate.rs` | `src/execution/gate.rs` `#[cfg(test)] mod tests` |
| `tests/test_net_edge_gate.rs` | `src/execution/gates.rs` `#[cfg(test)] mod tests` |
| `tests/test_pricer.rs` | `src/execution/pricer.rs` `#[cfg(test)] mod tests` |
| `tests/test_quantize.rs` | `src/execution/quantize.rs` `#[cfg(test)] mod tests` |
| `tests/test_preflight.rs` | `src/execution/preflight.rs` `#[cfg(test)] mod tests` |
| `tests/test_post_only_guard.rs` | `src/execution/post_only_guard.rs` `#[cfg(test)] mod tests` |
| `tests/test_inventory_skew.rs` | `src/execution/inventory_skew.rs` `#[cfg(test)] mod tests` |
| `tests/test_base_gates.rs` | `src/execution/base_gates.rs` `#[cfg(test)] mod tests` |
| `tests/test_gate_outcome.rs` | `src/execution/gate_outcome.rs` `#[cfg(test)] mod tests` |
| `tests/test_order_size.rs` | `src/execution/order_size.rs` `#[cfg(test)] mod tests` |
| `tests/test_label.rs` | `src/execution/label.rs` `#[cfg(test)] mod tests` |
| `tests/test_dispatch_map.rs` | `src/execution/dispatch_map.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_assembly.rs` | `src/execution/intent_assembly.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_pipeline.rs` | `src/execution/pipeline.rs` `#[cfg(test)] mod tests` |
| `tests/test_open_runtime_wiring.rs` | `src/execution/open_runtime.rs` `#[cfg(test)] mod tests` |
| `tests/test_static_rejection_counters.rs` | Split — see counter mapping table below |
| `tests/test_rejection_side_effects.rs` | Split: gate parts → gate files, pipeline parts → `pipeline.rs` |
| `tests/test_gate_ordering.rs` | `src/execution/build_order_intent.rs` `#[cfg(test)] mod tests` |
| `tests/test_intent_determinism.rs` | `src/execution/pipeline.rs` `#[cfg(test)]` — uses `PricerInput`, `QuantizeConstraints` (pipeline-level determinism) |
| `tests/test_intent_id_propagation.rs` | `src/execution/pipeline.rs` `#[cfg(test)]` — uses `PricerInput`, `QuantizeConstraints` (pipeline-level ID threading) |
| `tests/test_missing_config.rs` | `src/execution/pipeline.rs` `#[cfg(test)]` — builds full gate inputs (pipeline-level missing-input behavior) |
| `tests/common/mod.rs` | **Delete.** Helpers split per-module into `#[cfg(test)]` blocks. |
| `tests/prop_net_edge.rs` | `src/execution/gates.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |
| `tests/prop_liquidity_gate.rs` | `src/execution/gate.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |
| `tests/prop_quantize.rs` | `src/execution/quantize.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |
| `tests/prop_label.rs` | `src/execution/label.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |
| `tests/prop_tlsm.rs` | `src/execution/tlsm.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |
| `tests/prop_pipeline_gi001.rs` | `src/execution/pipeline.rs` `#[cfg(test)]` — throttled via `PROPTEST_CASES` |

**Property tests and the quick loop:** Moving `prop_*` tests into `#[cfg(test)]`
modules means they run under `cargo test --workspace --lib` (quick mode). Proptest
defaults can be non-trivial and risk turning "quick" into "medium."
**Mitigation:** Throttle proptest case count via environment variable. Do **not** use
`#[ignore]` (runs all ignored tests workspace-wide in full mode) or feature gates
(adds Cargo.toml complexity for no benefit).

```bash
# quick mode — proptests run but are fast (~32 cases each)
export PROPTEST_CASES="${PROPTEST_CASES:-32}"
cargo test --workspace --lib --locked

# full mode — proptests run with full budget (~1000 cases)
export PROPTEST_CASES="${PROPTEST_CASES:-1000}"
cargo test --workspace --all-features --locked
```

Proptests stay unignored and always run. Quick stays quick (32 cases adds ~2s).
Full stays complete (1000 cases — `rust_gates.sh` already sets this in full mode).
Quick mode today runs **zero** prop test cases (they live in `tests/`, skipped by
`--lib`). After migration, quick runs 32 per file — strictly better coverage.

**Global counter race condition:** Counter functions like `inventory_skew_reject_total()`
use process-global static atomics (e.g., `AtomicU64`). Integration test files get
separate binaries with isolated memory. Unit tests under `--lib` share a single binary
with parallel threads — meaning counter assertions like `assert_eq!(counter, 1)` will
flake when another thread's rejection increments the same global.
**Fix: Global test lock for counter assertions (zero dependencies).**

Add a single `Mutex` in each gate module's `#[cfg(test)]` block. Any test that
reads or asserts global counter values must hold the lock. This serializes only
counter tests (microsecond operations) — all other tests remain parallel.

```rust
// In each gate module's #[cfg(test)] block:
#[cfg(test)]
static METRICS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[test]
fn test_reject_increments_counter() {
    let _g = METRICS_TEST_LOCK.lock().unwrap();
    let before = inventory_skew_reject_total();
    // ... trigger rejection ...
    assert_eq!(inventory_skew_reject_total() - before, 1);
}
```

**Why not delta assertions alone?** Delta assertions (`after - before`) reduce
flake probability but don't eliminate it — a parallel thread can increment between
the `before` read and the operation. The `Mutex` makes counter tests deterministic
with zero new crate dependencies. Serialization cost is negligible (counter tests
are microsecond operations).

**Why not `serial_test` crate?** Adds a dependency for something a stdlib `Mutex`
handles. If the project later adopts `serial_test` for other reasons, these locks
can be replaced with `#[serial]` attributes.

**`test_static_rejection_counters.rs` split mapping:**

| Counter tests (fn names) | Target module | Counter function |
|--------------------------|---------------|------------------|
| `test_inventory_skew_*` (3 tests) | `src/execution/inventory_skew.rs` | `inventory_skew_reject_total` |
| `test_pricer_*` (2 tests) | `src/execution/pricer.rs` | `pricer_reject_total` |
| `test_quantize_*` (3 tests) | `src/execution/quantize.rs` | `quantize_reject_total` |
| `test_post_only_*` (3 tests) | `src/execution/post_only_guard.rs` | `post_only_reject_total` |
| `test_group_*` (3 tests) | `src/execution/group.rs` | `group_lock_timeout_total`, `group_mixed_failed_total`, `group_persist_fail_total` |
| `test_fee_staleness_*` (3 tests) | **Keep in `tests/`** — uses `risk` module, not execution internals |
| `test_margin_gate_*` (2 tests) | **Keep in `tests/`** — uses `risk` module |
| `test_pending_exposure_*` (2 tests) | **Keep in `tests/`** — uses `risk` module |
| `test_exposure_budget_*` (3 tests) | **Keep in `tests/`** — uses `risk` module |

After the split, rename the remaining integration test file to
`tests/test_static_rejection_counters_risk.rs` (10 tests, risk-only imports).

**Tests that stay in `tests/`** (use only contract types):

| Integration test file | Why it stays |
|----------------------|-------------|
| `tests/test_tlsm.rs` | TLSM types are contract-level. **Partial rewrite needed:** imports `ooo_count`, `ooo_total` (CUT from facade, §10 metrics rule). Move metric-asserting tests to `tlsm.rs` `#[cfg(test)]` unit tests; keep only lifecycle/contract tests in this file. |
| `tests/test_atomic_group.rs` | Group types are contract-level. **Rewrite required:** `persist_before_dispatch`, `GroupPersistence`, and `InMemoryGroupPersistence` are all CUT from the facade. Move `persist_before_dispatch_success_records_group` and `persist_before_dispatch_failure_must_abort` to `group.rs` `#[cfg(test)]` unit tests (where `InMemoryGroupPersistence` remains accessible). Keep only contract-level tests in this file: lock behavior (`try_acquire_group_lock`), state transitions (`GroupState`, `GroupStateTransition`), atomicity invariants. |
| `tests/test_reject_reason.rs` | RejectReasonCode is contract-level. **Minor fix needed:** imports `common::gate_results_all_passing` — replace with `test_stubs::gate_results_all_passing_failclosed_wal()` (see §4b) before `common/mod.rs` is deleted in Step 2. |
| `tests/adversarial_gi_enforcement.rs` | Highest-value contract test. **Must be rewritten in this migration** (see §4a below). Currently calls `evaluate_intent_pipeline()` directly (excluded from facade) and depends on `common::base_open_input()` which constructs `IntentPipelineInput` with internal wire types. Rewrite to use chokepoint surface only (`build_order_intent_with_*`, `GateResults`, `RejectReasonCode`). Pipeline-level assertions (e.g., "missing liquidity input → LiquidityGateNoL2") move to `pipeline.rs` unit tests. |
| `tests/test_dispatch_chokepoint.rs` | Architectural constraint test (file scanning) |
| `tests/test_idempotency.rs` | Uses `idempotency` module, not execution internals |
| `tests/test_label_match.rs` | Uses `recovery` module |
| `tests/test_capabilities.rs` | Uses `venue` module |
| `tests/test_margin_gate.rs` | Uses `risk` module |
| `tests/test_fee_staleness.rs` | Uses `risk` module |
| `tests/test_pending_exposure.rs` | Uses `risk` module |
| `tests/test_exposure_budget.rs` | Uses `risk` module |
| `tests/test_instrument_kind_mapping.rs` | Uses `venue` module |
| `tests/test_instrument_cache_ttl.rs` | Uses `venue` module |
| `tests/test_expiry_guard.rs` | Uses `venue` module |
| `tests/test_recorded_before_dispatch_gate.rs` | Uses `RecordedBeforeDispatchGate` (public). **Minor fix needed:** imports `common::gate_results_all_passing` — replace with `test_stubs::gate_results_all_passing_failclosed_wal()` (see §4b) before `common/mod.rs` is deleted in Step 2. |

### 4a. `adversarial_gi_enforcement.rs` — Chokepoint-Level Rewrite

This test currently calls `evaluate_intent_pipeline()` directly and imports
`IntentPipelineMetrics` — both excluded from the facade. It also depends on
`common::base_open_input()` which constructs `IntentPipelineInput` with internal
wire types (`LiquidityGateInput`, `NetEdgeInput`, `PricerInput`). This contradicts
"pipeline wiring is not contract."

**Fix: rewrite to chokepoint-level contract surface using strangler fig approach.**

To prevent coverage gaps, add new chokepoint-level tests alongside existing pipeline
tests first (both run, verify coverage), THEN remove old tests. This is the safest
migration path for the highest-value contract tests.

The 15 pipeline tests (GI-001, GI-002, GI-004, GI-009, GI-017) must be rewritten
to exercise the contract through chokepoint functions.

**Assertion-level migration mapping:**

| Current test fn | Key assertion | Moves to | Notes |
|----------------|---------------|----------|-------|
| `gi_001_blocks_open_when_risk_degraded` | `ChokeRejectReason::RiskStateNotHealthy` | chokepoint (stays) | intent_class=Open, risk_state=Degraded |
| `gi_001_blocks_open_when_risk_maintenance` | `ChokeRejectReason::RiskStateNotHealthy` | chokepoint (stays) | intent_class=Open, risk_state=Maintenance |
| `gi_001_blocks_open_when_risk_kill` | `ChokeRejectReason::RiskStateNotHealthy` | chokepoint (stays) | intent_class=Open, risk_state=Kill |
| `gi_001_allows_open_when_risk_healthy` | `ChokeResult::Approved` | chokepoint (stays) | baseline: all gates pass |
| `gi_002_open_class_applies_risk_state_gate` | `RiskStateNotHealthy` | chokepoint (stays) | Open + Degraded → reject |
| `gi_002_close_class_skips_risk_state_gate` | no `MarginHeadroomRejectOpens` | chokepoint (stays) | Close + Degraded → not rejected by risk |
| `gi_002_cancel_only_always_approved` | `Approved`, trace=[DispatchAuth] | chokepoint (stays) | CancelOnly + Kill → approved |
| `gi_004_blocks_open_without_wal_recorded` | `GateStep::RecordedBeforeDispatch` reject | chokepoint (stays) | use FailingWalGate stub |
| `gi_004_allows_open_with_wal_recorded` | `Approved`, trace has WAL step | chokepoint (stays) | use StubWalGate |
| `gi_009_blocks_open_when_fee_cache_missing` | `FeeCacheCheck` reject | chokepoint (stays) | `fee_cache_passed: false` in gate_results |
| `gi_009_blocks_open_when_fee_cache_hard_stale` | rejected | chokepoint (stays) | `fee_cache_passed: false` |
| `gi_009_allows_open_when_fee_cache_fresh` | `Approved` | chokepoint (stays) | `fee_cache_passed: true` |
| `gi_017_close_bypasses_liquidity_gate` | not rejected by liquidity codes | chokepoint (stays) | Close + `liquidity_gate_passed: false` → still approved |
| `gi_017_close_bypasses_net_edge_gate` | not rejected by net edge codes | chokepoint (stays) | Close + `net_edge_passed: false` → still approved |
| `gi_017_open_fails_without_liquidity` | `reject_reason_code == LiquidityGateNoL2` | **pipeline.rs unit test** | Asserts pipeline-specific reject reason unavailable at chokepoint level |

**Key insight:** All tests except `gi_017_open_fails_without_liquidity` can be fully
expressed at chokepoint level. That one test asserts `LiquidityGateNoL2` (a gate-internal
reject reason), so it moves to `pipeline.rs` `#[cfg(test)]`.

```rust
// BEFORE (calls excluded pipeline entrypoint):
use soldier_core::execution::{evaluate_intent_pipeline, IntentPipelineMetrics, ...};
let result = evaluate_intent_pipeline(&input, &mut metrics);

// AFTER (uses facade-only chokepoint surface):
use soldier_core::execution::{
    build_gate_results, build_order_intent_with_wal_gate,
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult,
    GateResults, RecordedBeforeDispatchGate,
};
use soldier_core::risk::RiskState;

// Shared contract-level stubs (see §4b — tests/test_stubs.rs)
mod test_stubs;
use test_stubs::StubWalGate;

// Verify exact parameter names against build_order_intent.rs before coding.
// Shape:
//   intent_class: ChokeIntentClass   — Open / Close / Cancel
//   risk_state:   RiskState           — Healthy / Degraded / Maintenance / Kill
//   metrics:      &mut ChokeMetrics   — mutable metrics handle
//   gate_results: &GateResults        — pre-built per-gate pass/fail flags
//   wal_gate:     &mut dyn RecordedBeforeDispatchGate
let gate_results = build_gate_results(/* per-gate pass/fail booleans */);
// NOTE: Verify ChokeMetrics construction — may require ::new() or explicit fields
// rather than ::default(). Check build_order_intent.rs before coding.
let mut metrics = ChokeMetrics::default();
let mut wal = StubWalGate;

let result = build_order_intent_with_wal_gate(
    ChokeIntentClass::Open,
    RiskState::Degraded,
    &mut metrics,
    &gate_results,
    &mut wal,
);

match result {
    ChokeResult::Rejected { reason, .. } => {
        assert!(matches!(reason, ChokeRejectReason::RiskStateNotHealthy));
    }
    other => panic!("expected rejection, got {other:?}"),
}
```

**Important:** The call shape above is illustrative — verify the actual
`build_order_intent_with_wal_gate` signature in `build_order_intent.rs`
before writing the migration PR. The key constraint is: only import types that
exist in `api.rs`.

**What this tests and what it does not:** Chokepoint-level tests exercise the
decision logic (intent class × risk state × gate pass/fail → accept/reject).
They return `ChokeRejectReason` (high-level reason), **not** gate-internal
reject details like `LiquidityGateNoL2`. Pipeline-level assertions that test
specific gate reject reasons (e.g., "missing `LiquidityGateInput` →
`LiquidityGateNoL2`", "missing `NetEdgeInput` → `NetEdgeMissingInput`") are
valuable but must move to `pipeline.rs` `#[cfg(test)]` unit tests — they
cannot be expressed through the chokepoint surface.

**Two-layer coverage requirement (MANDATORY — prevents spec holes):**

The current `adversarial_gi_enforcement.rs` tests the full pipeline: domain inputs
→ bool derivation → chokepoint decision. The rewrite splits this into two layers
that **both** must have test coverage:

| Layer | What it proves | Where tested | Example |
|-------|---------------|-------------|---------|
| **Layer 1: Bool derivation** | Domain inputs → correct bool in `GateResults` | `pipeline.rs`, `base_gates.rs`, or individual gate `#[cfg(test)]` unit tests | "stale `FeeCacheSnapshot` → `fee_cache_passed = false`" |
| **Layer 2: Bool consumption** | `GateResults` bools → correct chokepoint accept/reject | `adversarial_gi_enforcement.rs` (facade-only) | "`fee_cache_passed = false` → reject at `GateStep::FeeCacheCheck`" |

Without Layer 1, the pipeline could compute `fee_cache_passed = true` on a stale
snapshot and no test would catch it — the chokepoint test would pass because it
only sees pre-built booleans.

**Required Layer 1 unit tests per GI guard** (in `pipeline.rs` or `base_gates.rs`
`#[cfg(test)]`):

| GI guard | Bool field | Derivation module | Required Layer 1 unit test |
|----------|-----------|-------------------|---------------------------|
| GI-001/002 | N/A | `risk_state` is a direct input to chokepoint, not derived from `GateResults` | Not needed — Layer 2 suffices |
| GI-004 | `wal_recorded` | WAL gate trait (`record_before_dispatch()`) | Covered by `StubWalGate`/`FailingWalGate` at chokepoint level — the trait contract IS the derivation |
| GI-009 | `fee_cache_passed` | `base_gates.rs` → `evaluate_fee_staleness()` | **Must add**: stale snapshot → `fee_cache_passed = false`; fresh → `true` |
| GI-009 | `expiry_guard_passed` | `base_gates.rs` → expiry check | **Must add**: expired instrument → `false`; valid → `true` |
| GI-017 | `liquidity_gate_passed` | `pipeline.rs`/`open_runtime.rs` → `evaluate_liquidity_gate()` | Existing gate tests cover derivation; **must add** pipeline-level: `None` input → `liquidity_gate_passed = false` |
| GI-017 | `net_edge_passed` | `pipeline.rs`/`open_runtime.rs` → `evaluate_net_edge()` | Same as liquidity: **must add** pipeline-level `None` input → `false` |
| — | `preflight_passed` | `base_gates.rs` → `preflight_intent()` | Covered by existing `test_preflight.rs` moves |
| — | `quantize_passed` | `base_gates.rs` → `quantize()` | Covered by existing `test_quantize.rs` moves |
| — | `pricer_passed` | `pipeline.rs`/`open_runtime.rs` → `compute_limit_price()` | Covered by existing `test_pricer.rs` moves |

**Implementation rule for Step 2:** When moving a GI test from pipeline-level to
chokepoint-level, the implementer MUST verify that a Layer 1 unit test exists for
every bool that the old test was implicitly deriving. If no Layer 1 test exists,
write one in the derivation module's `#[cfg(test)]` before removing the old
pipeline-level test. The strangler fig sub-commit `2-gi-a` MUST include both the
new chokepoint test AND any required Layer 1 tests; sub-commit `2-gi-b` may only
remove old tests after both layers are proven.

The 4 hash tests (GI-020) use `compute_intent_hash()` from `idempotency` — these
are already facade-clean and stay unchanged.

### 4b. `tests/test_stubs.rs` — Shared Contract-Level Stubs

After deleting `common/mod.rs` (which leaked internals), a new shared module holds
facade-compliant test implementations. **This module may only import from the facade
(`soldier_core::execution::{...}`) — never gate-internal types.**

```rust
// crates/soldier_core/tests/test_stubs.rs
use soldier_core::execution::{
    build_gate_results, GateResults, RecordedBeforeDispatchGate,
};

/// Stub WAL gate for contract-level tests that need the WAL-safe path.
pub struct StubWalGate;
impl RecordedBeforeDispatchGate for StubWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> { Ok(()) }
}

/// Failing WAL gate for GI-004 tests that verify WAL rejection.
pub struct FailingWalGate;
impl RecordedBeforeDispatchGate for FailingWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        Err("wal append failed".to_string())
    }
}

/// All-passing gate results with fail-closed WAL.
/// WAL field is `false` so tests that forget to pass a StubWalGate fail-closed.
pub fn gate_results_all_passing_failclosed_wal() -> GateResults {
    build_gate_results(
        true,  // preflight_passed
        true,  // quantize_passed
        true,  // dispatch_consistency_passed
        true,  // fee_cache_passed
        true,  // expiry_guard_passed
        true,  // liquidity_gate_passed
        true,  // net_edge_passed
        true,  // pricer_passed
        false, // wal_recorded — overridden by wal_gate adapter at runtime
        None,  // requested_qty
        None,  // max_dispatch_qty
    )
}
```

Consumers: `adversarial_gi_enforcement.rs`, `test_reject_reason.rs`,
`test_recorded_before_dispatch_gate.rs` (and any future contract tests).

### 5. `tests/common/mod.rs` — The Coupling Vector

This shared helper module currently constructs gate-level wire types
(`LiquidityGateInput`, `NetEdgeInput`, `PricerInput`, `L2BookSnapshot`, etc.)
for use by integration tests. It is the primary vector through which internals
leak into the contract surface.

**Fix:** Delete `common/mod.rs`. Each gate's test builders become `#[cfg(test)]`
helpers inside the gate's source file:

```rust
// src/execution/gate.rs
#[cfg(test)]
pub(crate) mod test_builders {
    use super::*;

    pub(crate) fn default_liquidity_input() -> LiquidityGateInput {
        LiquidityGateInput { /* defaults */ }
    }
}
```

These builders use `super::*` and are visible within the crate under `#[cfg(test)]`.
If a unit test in `pricer.rs` needs a `LiquidityGateInput` for a wiring test,
it imports `crate::execution::gate::test_builders::default_liquidity_input`.

### 6. Inline vs Sibling Test Files

For modules where the unit tests are large (>200 lines), use the sibling pattern:

```rust
// src/execution/gate.rs
#[cfg(test)]
#[path = "gate_tests.rs"]
mod gate_tests;

// src/execution/gate_tests.rs — same visibility as inline, cleaner file
```

**Why `#[path]`:** Without the attribute, `mod gate_tests;` inside `gate.rs` makes
Rust look for `gate/gate_tests.rs` (a subdirectory), not the sibling file
`gate_tests.rs`. The `#[path]` attribute overrides this to point at the sibling.

This keeps the source file readable while still getting `--lib` coverage.

### 7. TOC Fix — Smoke-Contract Lane in `verify.sh`

Problem: `verify.sh quick` runs `cargo test --workspace --lib`, which skips
`crates/soldier_core/tests/`. After this refactor, only contract tests remain
there, but they're still invisible to the fast loop.

**Fix: Add a `smoke` lane immediately after the existing
`cargo test --workspace --lib --locked` invocation in the script that implements
Rust quick mode (`plans/lib/rust_gates.sh` or whichever file contains the quick
branch). Keep `--locked` consistent with surrounding commands.**

```bash
# plans/lib/rust_gates.sh — quick branch, add after `cargo test --workspace --lib --locked`:

# ── Smoke contract tests (facade-only integration tests) ──
cargo test -p soldier_core --locked --test test_facade_completeness
cargo test -p soldier_core --locked --test adversarial_gi_enforcement
cargo test -p soldier_core --locked --test test_dispatch_chokepoint
cargo test -p soldier_core --locked --test test_reject_reason
cargo test -p soldier_core --locked --test test_tlsm
```

Selection rationale:
- `test_facade_completeness` — compile-time proof that all api.rs symbols are reachable
- `adversarial_gi_enforcement` — chokepoint-level GI guards (rewritten in §4a)
- `test_dispatch_chokepoint` — architectural invariant scan (updated in §8a)
- `test_reject_reason` — reject code registry completeness
- `test_tlsm` — lifecycle state machine contract

This adds seconds, not minutes. The constraint (fast contract feedback) is
directly elevated.

**Modes become:**

| Mode | What runs |
|------|-----------|
| `quick` | `--lib` + smoke contract tests (5 integration tests) + facade lint |
| `full` | Everything (unchanged) |

### 8. Cross-Crate Impact

**Production code (`soldier_infra`):** Two files import 4 unique symbols:
- `src/wal.rs`: `RecordedBeforeDispatchGate`
- `src/store/ledger.rs`: `TlsmTransitionSink` (trait impl), `PersistedTransition`,
  `TlsmState` (fully-qualified `soldier_core::execution::TlsmState::*` in
  `map_core_tlsm_state`)

All 4 symbols are in the facade. Zero breakage.

**Integration tests (`soldier_infra/tests/`):** Two files import 5 unique symbols:
- `test_dispatch_durability.rs` — `RecordedBeforeDispatchGate`. No change.
- `test_ledger_replay.rs` — `Tlsm`, `TlsmEvent`, `TlsmState`, `TransitionResult`. No change.

Total: 7 unique symbols across 4 files, all facade-level.

### 8a. Architectural Scan Tests — Required Updates

`test_dispatch_chokepoint.rs` contains 9 architectural constraint tests that use
string matching on source files. One will break after this refactor:

**`test_chokepoint_reexported_from_execution` (line 308–322):**
Asserts `mod.rs` contains `"pub mod build_order_intent"`. After Step 4, this becomes
`mod build_order_intent` — test fails.

**Fix:** Replace string-match with compile-time contract check. Reference only
non-deprecated functions to avoid clippy `-D warnings` failures in `verify.sh full`.
Both `build_order_intent` and `build_order_intent_with_reject_reason_code` are
`#[deprecated]` — referencing either in a test triggers clippy warnings. The
WAL-safe functions are the only non-deprecated chokepoint entry points:
```rust
#[test]
fn chokepoint_is_publicly_reachable() {
    // Proves the chokepoint functions are reachable through the facade.
    // Fails at compile time if the re-export is removed.
    // Only references non-deprecated entry points.
    let _ = soldier_core::execution::build_order_intent_with_wal_gate;
    let _ = soldier_core::execution::build_order_intent_with_optional_wal_gate;
    let _ = soldier_core::execution::build_gate_results;
}
```

**`test_dispatch_chokepoint_no_direct_exchange_client_usage` (line 137–197):**
Scans for 6 forbidden dispatch symbols (`DispatchRequest`, `dispatch_map::`, etc.)
and whitelists 4 files: `dispatch_map.rs`, `build_order_intent.rs`,
`intent_assembly.rs`, `mod.rs`. After Step 3, `mod.rs` no longer contains these
symbols (old re-exports deleted). After Step 4, `api.rs` exists but does **not**
contain dispatch symbols (they are CUT from the facade — see §2). The scan will
not flag either file. The existing `mod.rs` whitelist entry becomes inert but
harmless. **No whitelist change is required.**

These fixes belong in Step 4 (same commit as the `pub mod` → `mod` flip).

### 9. Proof Step — Compiler Enforcement

After the refactor, deep module path imports fail at compile time:

```rust
// crates/soldier_infra/src/some_new_file.rs
use soldier_core::execution::gate::LiquidityGateInput;
//                            ^^^^ error: module `gate` is private
```

Facade-level imports work for contract types:

```rust
use soldier_core::execution::Side;              // OK — in api.rs
use soldier_core::execution::RejectReasonCode;  // OK — in api.rs
use soldier_core::execution::Tlsm;              // OK — in api.rs
```

**Phase 1 limitation:** Wire types not in `api.rs` (like `LiquidityGateInput`) are
still technically `pub` in their source files, but unreachable because their parent
modules are private. The lint gate (Step 5 of migration) enforces that no one adds
`pub mod gate;` back. Phase 2 makes them `pub(crate)` for defense-in-depth.

### 10. Metrics as Contract — Explicit Decision

Counter functions like `liquidity_gate_reject_total()` are currently tested in
integration tests. After this refactor, they're internal.

**Rule:** Observability counters are NOT part of the contract unless explicitly
declared. Individual gate counter functions (`liquidity_gate_reject_total`,
`pricer_reject_total`, etc.) are internal observability. Tests that assert
specific counter values belong next to the gate code.

**Metrics sink types that appear in exported signatures are contract by necessity.**
`ChokeMetrics` is exported because the chokepoint functions require `&mut ChokeMetrics`
in their signatures (signature closure). This does not make counter functions contract
— only the sink type itself. Phase 2 can reduce this surface by hiding metrics behind
a trait (`&mut dyn MetricsSink`).

**No observability counters are contract in Phase 1.** This includes
`gate_sequence_total`, which is explicitly CUT from the facade (see §2 — sole
consumer `test_gate_ordering` is a must-move). Counters may be elevated to contract
status in a future phase if a `/status` contract spec depends on specific values.
Until then: unit-test only.

### 11. Migration Order

Each step is a standalone commit for clean bisection. Steps must be done in order.
**Every intermediate commit must compile and pass `cargo test --workspace`.**

**Rollback:** Each step is a single atomic commit. Rollback is `git revert <commit>`.
No migration state files or cleanup needed.

**Step 0: Pre-flight baseline (single commit — branch creation only).**
Create branch `refactor/execution-facade-lockdown` from the integration branch.
Run `verify.sh quick` and `verify.sh full` — both must pass before any code changes.
Snapshot current deep-import usage and validate CUT assumptions:
```bash
# Informational baseline only — this regex is intentionally broad (matches method
# calls like TlsmState::new() alongside real deep imports like gate::LiquidityGateInput).
# The authoritative deep-import check is the lint in Step 6 which anchors to `use` statements.
rg 'execution::\w+::' crates/ --type rust -c > /tmp/deep-import-baseline.txt
# Validate build_order_intent has zero consumers outside execution/:
rg -n 'build_order_intent\(' crates/ --type rust \
  -g'!crates/soldier_core/src/execution/**' \
  -g'!crates/soldier_core/tests/**'
# ^ Must return zero matches. If anything outside execution uses it, add migration to Step 2.
```
This baseline lets you diff after Step 4 to confirm all deep paths are gone.

Green checks:
```bash
git checkout -b refactor/execution-facade-lockdown
./plans/verify.sh quick   # must pass
./plans/verify.sh full    # must pass
rg 'execution::\w+::' crates/ --type rust -c > /tmp/deep-import-baseline.txt
# baseline file exists and is non-empty
test -s /tmp/deep-import-baseline.txt
```

**Step 1a: Add `api.rs` skeleton + compile-check test (single commit).**
Create `api.rs` with contract-type re-exports. Add `pub mod api;` to `mod.rs`.
Do **not** add `pub use api::*;` yet — existing `pub use` blocks in `mod.rs`
still re-export the same names, and `pub use api::*` would conflict (`E0252`).
At this point `execution::api::Side` works, but `execution::Side` still routes
through the old re-exports. Zero behavioral change.

Also add a compile-check test that imports every `api.rs` symbol, proving facade
completeness without requiring import churn in existing test files:

```rust
// crates/soldier_core/tests/test_facade_completeness.rs
//! Compile-time proof that every api.rs symbol is reachable.
//! If api.rs drops a re-export, this file fails to compile.
#[allow(unused_imports)]
use soldier_core::execution::api::{
    // ── Chokepoint Boundary (10 symbols) ──
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult,
    GateResults, GateStep, RecordedBeforeDispatchGate,
    build_gate_results,
    build_order_intent_with_wal_gate,
    build_order_intent_with_optional_wal_gate,
    // CUT: build_order_intent_with_reject_reason_code (#[deprecated])
    // ── Reject Reason (4 symbols) ──
    GateRejectCodes, RejectReasonCode,
    reject_reason_registry, reject_reason_registry_contains,
    // ── Domain Primitives (2 symbols) ──
    Side, OrderSize,
    // ── Label (6 symbols) ──
    LABEL_MAX_LEN, LabelError, LabelInput,
    derive_gid12, derive_sid8, encode_label,
    // ── Group Atomicity (9 symbols) ──
    AtomicGroup, GroupConfig, GroupError, GroupLock,
    GroupState, GroupStateTransition, LegResult,
    LockAcquisitionResult,
    try_acquire_group_lock,
    // CUT: InMemoryGroupPersistence (orphaned — GroupPersistence trait cut)
    // ── TLSM (8 symbols) ──
    OooCategory, PersistedTransition, Tlsm,
    TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink,
    TransitionResult,
};

#[test]
fn facade_symbols_reachable() {
    // If this compiles, all 39 symbols are reachable through api.rs.
    // No runtime assertions needed — this is a compile-time contract test.
}
```

This test replaces the old Step 1b (which would have migrated staying tests to
`::api::` paths and then reverted them in Step 3 — two diffs, zero net change).

Green checks:
```bash
cargo test -p soldier_core --test test_facade_completeness  # compiles + passes
cargo test --workspace --lib                                 # no regressions
```

**Step 2: Move internal tests + rewrite GI tests + fix staying-test CUT imports (one commit per module).**
Split `tests/common/mod.rs` builders per-module into `#[cfg(test)]` blocks.
Rewrite `adversarial_gi_enforcement.rs` using **strangler fig** (two sub-commits):
  - **2-gi-a:** Add new chokepoint-level test functions alongside existing pipeline
    tests. Both old and new tests run. Verify coverage parity (`cargo test -p
    soldier_core --test adversarial_gi_enforcement` — all old + new tests pass).
  - **2-gi-b:** Remove old pipeline-level tests. Move `gi_017_open_fails_without_liquidity`
    (pipeline-specific assertion) into `pipeline.rs` `#[cfg(test)]` unit tests.
This two-phase approach prevents coverage gaps in the highest-value contract test.
**Before deleting `common/mod.rs`**, create `tests/test_stubs.rs` (see §4b) and fix
staying tests that depend on common/:
- `test_reject_reason.rs`, `test_recorded_before_dispatch_gate.rs`: replace
  `common::gate_results_all_passing()` with `test_stubs::gate_results_all_passing_failclosed_wal()`.
- `adversarial_gi_enforcement.rs`: replace inline `StubWalGate` with
  `test_stubs::StubWalGate`.
Then delete `common/mod.rs`.
**Also in Step 2** — fix staying tests that import CUT symbols (must happen before Step 3):
- `test_tlsm.rs`: move `ooo_count`/`ooo_total` metric assertions to `tlsm.rs`
  `#[cfg(test)]` unit tests. The integration file keeps lifecycle/contract tests only.
- `test_atomic_group.rs`: move `persist_before_dispatch_success_records_group` and
  `persist_before_dispatch_failure_must_abort` to `group.rs` `#[cfg(test)]` unit tests.
  Remove `persist_before_dispatch` and `InMemoryGroupPersistence` imports from the
  integration test file. Keep only contract-level tests (lock behavior, state transitions).
Once all test files that call `with_intent_trace_ids` /
`take_execution_metric_lines` are moved, change both to `pub(crate)` (see §1).
Each move is a standalone commit. Verify with `cargo test --workspace` after each.

Green checks (after all moves complete):
```bash
cargo test --workspace                    # full workspace passes
# Verify common/mod.rs is deleted:
! test -f crates/soldier_core/tests/common/mod.rs
# Verify telemetry helpers are now pub(crate):
rg 'pub\(crate\) fn with_intent_trace_ids' crates/soldier_core/src/execution/mod.rs
rg 'pub\(crate\) fn take_execution_metric_lines' crates/soldier_core/src/execution/mod.rs
# Verify moved tests run under --lib (use partial match — module may be
# named `tests` or a sibling like `gate_tests` depending on §6 choice):
cargo test -p soldier_core --lib -- test_liquidity   # at least one moved gate test runs
```

**Module ordering** (low-coupling → high-coupling, prevents dependency tangles):

1. `label`, `order_size` (leaf modules, no internal cross-deps)
2. `gate` (liquidity), `gates` (net edge), `pricer`, `quantize`, `preflight`
3. `base_gates`, `inventory_skew`, `post_only_guard`
4. `dispatch_map`, `intent_assembly`
5. `pipeline`, `open_runtime` (highest fan-in — depend on most other modules)
6. Splitters: `test_static_rejection_counters`, `test_rejection_side_effects`
7. Property tests (`prop_*.rs`)

**Why Step 2 before Step 3:** Old re-exports still exist in `mod.rs`, so the
remaining integration tests (`test_tlsm.rs`, `test_atomic_group.rs`, etc.) continue
to compile via `soldier_core::execution::LiquidityGateInput` even while must-move
tests are being relocated. Moving tests first eliminates all consumers of non-facade
re-exports, making Step 3 safe.

**Step 2.5: Fix internal sibling imports (single commit).**
Internal execution submodules currently import sibling types through two patterns
that resolve via `mod.rs` re-exports:

1. `use super::{LiquidityGateInput, ...};` — bare `super::` grabs from `mod.rs`
2. `use crate::execution::DispatchConsistencyProof;` — full path through `mod.rs`

After Step 3 replaces the old re-export blocks with `pub use api::*` (contract
types only), any internal import that relied on a now-cut re-export (like
`DispatchConsistencyProof`, `LiquidityGateInput`) will stop compiling.

**Mechanical rule for `crates/soldier_core/src/execution/**`:**

| Pattern | Status |
|---------|--------|
| `use super::<submodule>::Symbol;` | Correct — direct sibling import |
| `use super::{Symbol, ...};` where Symbol is defined in a sibling | **Must fix** — goes through `mod.rs` |
| `use crate::execution::Symbol;` where Symbol is not in `api.rs` | **Must fix** — goes through `mod.rs` |
| `use crate::execution::<submodule>::Symbol;` | Safe — submodule path survives Steps 3+4 |

**Files that need fixing** (verified against current codebase):
- `pipeline.rs:7` — `use crate::execution::DispatchConsistencyProof;` (full path through mod.rs)
- `pipeline.rs:16–22` — `use super::{ ChokeIntentClass, LiquidityGateInput, ... }` (~20 symbols)
- `open_runtime.rs:19–26` — `use super::{ ChokeIntentClass, LiquidityGateInput, ... }` (~28 symbols)
- `open_runtime.rs:14` — `use super::DispatchConsistencyProof;`
- `base_gates.rs:9` — `use super::{ChokeIntentClass, DispatchConsistencyProof};`
- `intent_assembly.rs:18` — `use super::{ChokeIntentClass, ChokeRejectReason, ...};`
- `dispatch_map.rs` — `use crate::execution::OrderSize;` (facade-safe but should normalize to `use super::order_size::OrderSize;`)
- Any file using `use crate::execution::<non-facade-symbol>;`

**Files that do NOT need fixing** (submodule paths — survive re-export removal):
- `base_gates.rs:10–15` — `use crate::execution::build_order_intent::GateStep;` etc. (6 imports via `crate::execution::MODULE::Symbol` — the submodule path resolves through module visibility, not re-exports)
- `post_only_guard.rs:11` — `use crate::execution::quantize::Side;` (same pattern)

These will appear in the proof regex output; ignore them.

**Fix (mechanical, zero behavior change):** Replace with explicit sibling paths:

```rust
// BEFORE (resolves through mod.rs re-exports):
use super::{LiquidityGateInput, evaluate_liquidity_gate, ChokeIntentClass};
use crate::execution::DispatchConsistencyProof;

// AFTER (direct sibling imports — survives re-export removal):
use super::gate::{LiquidityGateInput, evaluate_liquidity_gate};
use super::build_order_intent::ChokeIntentClass;
use super::dispatch_map::DispatchConsistencyProof;
```

Imports already using `super::<submodule>::...` (e.g., `super::gate_outcome::GateOutcome`,
`super::reject_reason::RejectReasonCode`) are already correct and need no changes.

**Proof commands — run before Step 3 to confirm no stale internal imports remain.**
**WARNING: Do NOT rely on the regex commands below.** They miss single-symbol imports
like `use super::DispatchConsistencyProof;` (no brace) and multiline blocks.
**The authoritative check is `cargo check -p soldier_core`** after temporarily
replacing the old re-export blocks with `pub use api::*` in a scratch commit. If it
compiles, all imports are fixed.
```bash
# These are inventory commands (manually inspect output):
rg -n '^\s*use\s+super::\{' crates/soldier_core/src/execution/
rg -n '^\s*use\s+crate::execution::' crates/soldier_core/src/execution/
```

Green checks:
```bash
cargo test -p soldier_core --lib   # internal compilation passes
cargo test --workspace             # full workspace passes
# Verify no bare super::{WireType} imports remain in the 5 files:
! rg 'use super::\{.*LiquidityGateInput' crates/soldier_core/src/execution/pipeline.rs
! rg 'use super::\{.*LiquidityGateInput' crates/soldier_core/src/execution/open_runtime.rs
# Verify no crate::execution:: imports of non-facade symbols:
! rg 'use crate::execution::DispatchConsistencyProof' crates/soldier_core/src/execution/
# AUTHORITATIVE CHECK — temporarily swap re-exports, verify compilation:
# (scratch commit on a throwaway branch, revert after)
# In mod.rs: delete old `pub use` blocks, add `pub use api::*;`
# Then:
cargo check -p soldier_core        # must compile — proves all internal imports survive
# Revert the scratch commit before proceeding to Step 3.
```

**Why Step 2.5 before Step 3:** Without this, Step 3's re-export deletion breaks
internal compilation. `pipeline.rs` and `open_runtime.rs` are the canonical examples
— they import ~45 symbols through bare `super::` that would vanish when the old
re-export blocks are replaced with `pub use api::*`.

**Step 3: Flip re-exports — old blocks → `pub use api::*` (single commit).**
Delete the 19 `pub use` blocks from `mod.rs` and replace with `pub use api::*;`.
Now `execution::Side` routes through `api.rs`. Must be atomic — cannot have
both the old blocks and `pub use api::*` in the same compilation unit.
All consumers of non-facade symbols were either moved in Step 2 or rewritten to
use facade-only types (see staying-test rewrite notes in §4), so nothing breaks.

Green checks:
```bash
cargo test --workspace       # full workspace compiles and passes
# Verify old re-export blocks are gone from mod.rs:
! rg '^pub use super::' crates/soldier_core/src/execution/mod.rs
# Verify api::* re-export is present:
rg 'pub use api::\*' crates/soldier_core/src/execution/mod.rs
```

**Step 4: Flip module visibility — `pub mod` → `mod` + fix architectural tests + handle dead_code warnings (single commit).**
Change all 19 `pub mod` declarations to `mod` (except `api`). Fix any external
imports that used deep module paths (e.g., `execution::gate::...` → `execution::...`).
Wire types remain `pub` in their source files. `pub` → `pub(crate)` is **not** done
here (see §3 — deferred to Phase 2).
Also update `test_dispatch_chokepoint.rs` (see §8a): replace
`test_chokepoint_reexported_from_execution` string match with compile-time
contract check.

**Deprecated `build_order_intent()` in moved tests:** ~94 callsites across must-move
files (`test_gate_ordering.rs` alone has 44) use the deprecated `build_order_intent()`
which bypasses WAL. When these tests move into `#[cfg(test)]` unit tests, clippy
`-D warnings` will flag every call. **Fix per moved test module:** Add
`#[allow(deprecated)]` on the `mod tests` block (not individual callsites — too noisy):
```rust
#[cfg(test)]
#[allow(deprecated)] // Uses build_order_intent() — migrate to WAL-safe in Phase 2
mod tests {
    use super::*;
    // ... moved tests ...
}
```
This is tech debt, not a safety gap — the deprecated function still works, it just
bypasses WAL recording. Phase 2 migrates these callsites to
`build_order_intent_with_wal_gate` as part of the contract input type work.

**Dead-code warning trap:** Once modules become private, `pub fn` items whose only
callers are `#[cfg(test)]` code will trigger `dead_code` warnings during
`cargo build` (no test cfg). Since `verify.sh full` uses `-D warnings`, these become
hard errors. Functions affected include `gate_sequence_total`, counter functions like
`liquidity_gate_reject_total`, and any helper whose only consumers moved in Step 2.
**Fix per function:**
- If truly test-only (e.g., `gate_sequence_total`): mark `#[cfg(test)]` on the
  function itself, or move it into the `#[cfg(test)] mod tests` block.
- If a legitimate production helper not yet wired: add
  `#[allow(dead_code)] // TODO(Phase 2): Wire up in ExecutionEngine`.

Green checks:
```bash
cargo test --workspace                    # compiles and passes
# Verify zero dead_code warnings (catches functions the explicit list missed):
cargo build --workspace 2>&1 | (! grep 'dead_code')
# Verify only api is pub mod:
rg '^pub mod' crates/soldier_core/src/execution/mod.rs
# Should output exactly one line: "pub mod api;"
# Verify no banned deep module imports outside execution/.
# Anchored to `use` statements; [a-z_] matches module names (snake_case),
# not type names (PascalCase like TlsmState::Created).
! rg -n '^\s*(pub\s+)?use\s+soldier_core::execution::[a-z_][a-z0-9_]*::' crates/ \
  --type rust \
  -g'!crates/soldier_core/src/execution/**' \
  -g'!crates/soldier_core/tests/test_facade_completeness.rs'
# Verify architectural test updated:
cargo test -p soldier_core --test test_dispatch_chokepoint -- chokepoint_is_publicly_reachable
```

**Step 5: Add smoke lane + proptest throttle to `verify.sh quick` (single commit).**
After `cargo test --workspace --lib`, run highest-value contract tests:
`test_facade_completeness`, `adversarial_gi_enforcement`,
`test_dispatch_chokepoint`, `test_reject_reason`, `test_tlsm`.

Also ensure `plans/lib/rust_gates.sh` sets `PROPTEST_CASES` before the `--lib`
invocation so moved property tests don't inflate quick-mode runtime:
```bash
# quick branch — before cargo test --workspace --lib:
export PROPTEST_CASES="${PROPTEST_CASES:-32}"
```
Without this, proptest uses its compiled default (typically 256 cases), not 32.

Green checks:
```bash
./plans/verify.sh quick   # now runs --lib + 5 smoke contract tests
# Verify smoke tests are listed in rust_gates.sh:
rg 'test_facade_completeness' plans/lib/rust_gates.sh
rg 'adversarial_gi_enforcement' plans/lib/rust_gates.sh
rg 'test_dispatch_chokepoint' plans/lib/rust_gates.sh
rg 'test_reject_reason' plans/lib/rust_gates.sh
rg 'test_tlsm' plans/lib/rust_gates.sh
```

**Step 6: Add enforcement gate — `plans/lint_execution_facade.sh` (single commit).**
Concrete lint script, run in both quick and full modes:

```bash
#!/usr/bin/env bash
set -euo pipefail

MOD="crates/soldier_core/src/execution/mod.rs"

# 1) Only api is a public module (catches pub mod, pub(crate) mod, pub(super) mod)
PUB_MODS="$(rg -n '^\s*pub(\([^)]+\))?\s+mod\s+' "$MOD" || true)"
echo "$PUB_MODS" | rg -q 'pub mod api;' || { echo "Missing: pub mod api;"; exit 1; }
if echo "$PUB_MODS" | rg -v 'pub mod api;' | rg -q '.'; then
  echo "Found unexpected pub mod in execution/mod.rs:"
  echo "$PUB_MODS"
  exit 1
fi

# 2) Ban deep module imports outside execution/
# Anchored to `use`/`pub use` statements to avoid false positives on
# legitimate enum variant paths (e.g., TlsmState::Created).
# [a-z_] matches module names (snake_case), not type names (PascalCase).
if rg -n '^\s*(pub\s+)?use\s+soldier_core::execution::[a-z_][a-z0-9_]*::' crates/ \
  --type rust \
  -g'!crates/soldier_core/src/execution/**' \
  -g'!crates/soldier_core/tests/test_facade_completeness.rs'; then
  echo "Found banned deep execution module imports"
  exit 1
fi

echo "✓ execution facade lint passed"
```

Wire into `plans/lib/rust_gates.sh` (both quick and full branches).

Green checks:
```bash
# Lint passes clean:
bash plans/lint_execution_facade.sh
# Manual regression: temporarily add `pub mod gate;`, expect failure
# Manual regression: temporarily add `pub(crate) mod gate;`, expect failure
```

**Step 7: Verify.**
`verify.sh quick` (now runs gate unit tests + smoke contract tests), then
`verify.sh full`.

Green checks:
```bash
./plans/verify.sh quick   # passes (--lib + smoke lane + enforcement gate)
./plans/verify.sh full    # passes (all tests)
# Final enforcement lint:
bash plans/lint_execution_facade.sh   # ✓ execution facade lint passed
```

**NOT in this migration (Phase 2):** `pub` → `pub(crate)` on wire types. That
requires building contract input types first (see §12).

### 12. Future Work (Not This Design)

- **Phase 2: Contract input types + wire type internalization.** Build
  `ExecutionEngine` with `ExecutionInput { market_snapshot, risk_snapshot,
  intent_request }` where the module internally derives `LiquidityGateInput`,
  `PricerInput`, etc. from domain-level inputs. Integration tests in `tests/`
  would test through `ExecutionEngine::decide()`. **Only after this can wire
  types become `pub(crate)`** — the blocking dependency for true encapsulation.
  Also rewrite `adversarial_gi_enforcement.rs` to use contract inputs instead
  of constructing `IntentPipelineInput` directly.

- **Phase 3: Other modules** — Apply same pattern to `risk/`, `venue/`,
  `idempotency/`, `recovery/`.

- **`test-helpers` feature** — Only introduce if reusable scenario builders are
  needed. Expose scenarios (like `liquidity_reject_scenario() -> ExecutionInput`),
  never internal types. Use `#[cfg(feature = "test-helpers")]` only for builders/
  fixtures, not for exposing wire types directly.

## Non-Goals

- Changing any runtime behavior
- Adding new test *functionality* beyond existing coverage (moved and rewritten
  tests preserve existing coverage at equivalent or higher abstraction levels)
- Modifying CONTRACT.md or specs
- Touching `soldier_infra` module structure
- Building `ExecutionEngine` (Phase 2)
