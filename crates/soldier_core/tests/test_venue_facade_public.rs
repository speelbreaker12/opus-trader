//! External-surface smoke tests for `soldier_core::venue`.

#[allow(unused_imports)]
use soldier_core::venue::{
    BotFeatureFlags, CacheLookupResult, CacheTtlBreach, CancelOutcome, EvaluatedCapabilities,
    ExpiryGuardInput, ExpiryGuardResult, InstrumentCache, InstrumentKind, InstrumentKindInput,
    LifecycleDecision, LifecycleErrorClass, LifecycleIntent, LifecycleTerminalReason,
    MAX_PENDING_BREACH_EVENTS, ReconcileScope, RetryDirective, VenueCapabilities,
    VenueLifecycleError, classify_lifecycle_error, derive_instrument_kind, evaluate_capabilities,
    evaluate_expiry_guard, opens_blocked,
};

#[test]
fn venue_facade_symbols_publicly_reachable() {
    let capabilities =
        evaluate_capabilities(&VenueCapabilities::default(), &BotFeatureFlags::default());
    assert!(!capabilities.linked_orders_allowed);

    let derived = derive_instrument_kind(&InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_linear: true,
        is_perpetual: true,
    });
    assert_eq!(derived, Some(InstrumentKind::LinearFuture));
}
