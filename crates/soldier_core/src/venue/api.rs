//! Public venue façade.
//!
//! This file intentionally enumerates the `soldier_core::venue` public surface.

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
