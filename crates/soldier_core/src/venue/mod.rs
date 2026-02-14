//! Venue-related types, derivation logic, instrument cache, and capabilities.

pub mod cache;
pub mod capabilities;
pub mod lifecycle;
pub mod types;

pub use cache::{
    CacheLookupResult, CacheTtlBreach, InstrumentCache, MAX_PENDING_BREACH_EVENTS, opens_blocked,
};
pub use capabilities::{
    BotFeatureFlags, EvaluatedCapabilities, VenueCapabilities, evaluate_capabilities,
};
pub use lifecycle::{
    CancelOutcome, ExpiryGuardInput, ExpiryGuardResult, LifecycleDecision, LifecycleErrorClass,
    LifecycleIntent, LifecycleTerminalReason, ReconcileScope, RetryDirective, VenueLifecycleError,
    classify_lifecycle_error, evaluate_expiry_guard,
};
pub use types::{InstrumentKind, InstrumentKindInput, derive_instrument_kind};
