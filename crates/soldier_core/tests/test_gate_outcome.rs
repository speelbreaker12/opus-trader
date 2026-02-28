//! Compatibility anchor for workflow/doc-sync checks.
//!
//! GateOutcome converter coverage now lives in:
//! `crates/soldier_core/src/execution/gate_outcome_tests.rs`
//! and runs in `cargo test --lib` quick mode.

use soldier_core::execution::{
    RejectReasonCode, reject_reason_registry, reject_reason_registry_contains,
};

// Compile-time anchor: if facade exports used by reject-reason registry drift,
// this file fails to compile even though runtime coverage now lives in unit tests.
const _REJECT_REASON_REGISTRY_ANCHOR: fn() -> &'static [RejectReasonCode] = reject_reason_registry;
const _REJECT_REASON_CONTAINS_ANCHOR: fn(RejectReasonCode) -> bool =
    reject_reason_registry_contains;
