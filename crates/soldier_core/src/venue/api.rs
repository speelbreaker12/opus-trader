//! Public venue facade.
//!
//! This file defines the intended public surface for `soldier_core::venue`.
//! Symbols not re-exported here remain implementation details.
//!
//! **Public:** instrument cache + TTL breach, venue capabilities +
//! feature flags, lifecycle classification + expiry guard,
//! instrument-kind derivation.
//!
//! **Private:** `cache`, `capabilities`, `lifecycle`, `types`.
//!
//! **Tests:** unit tests alongside implementation files; facade completeness
//! in `facade_completeness_contract_tests.rs`; integration tests under
//! `tests/` covering the public venue surface.

pub use super::cache::{
    CacheLookupResult, CacheTtlBreach, InstrumentCache, MAX_PENDING_BREACH_EVENTS, opens_blocked,
};
pub use super::capabilities::{
    BotFeatureFlags, EvaluatedCapabilities, VenueCapabilities, evaluate_capabilities,
};
pub use super::lifecycle::{
    CancelOutcome, ExpiryGuardInput, ExpiryGuardResult, LifecycleDecision, LifecycleErrorClass,
    LifecycleIntent, LifecycleTerminalReason, ReconcileScope, RetryDirective, VenueLifecycleError,
    classify_lifecycle_error, evaluate_expiry_guard,
};
pub use super::types::{InstrumentKind, InstrumentKindInput, derive_instrument_kind};
