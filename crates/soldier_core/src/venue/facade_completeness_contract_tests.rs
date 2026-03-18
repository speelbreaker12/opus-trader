//! Compile-time proof that intended facade symbols are reachable via
//! `crate::venue::{...}`.

#[allow(unused_imports)]
use crate::venue::{
    BotFeatureFlags, CacheLookupResult, CacheTtlBreach, CancelOutcome, EvaluatedCapabilities,
    ExpiryGuardInput, ExpiryGuardResult, InstrumentCache, InstrumentKind, InstrumentKindInput,
    LifecycleDecision, LifecycleErrorClass, LifecycleIntent, LifecycleTerminalReason,
    MAX_PENDING_BREACH_EVENTS, ReconcileScope, RetryDirective, VenueCapabilities,
    VenueLifecycleError, classify_lifecycle_error, derive_instrument_kind, evaluate_capabilities,
    evaluate_expiry_guard, opens_blocked,
};

#[test]
fn facade_symbols_reachable_via_venue_facade() {
    let capabilities =
        evaluate_capabilities(&VenueCapabilities::default(), &BotFeatureFlags::default());
    assert!(!capabilities.linked_orders_allowed);
}
