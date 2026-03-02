//! Compile-time proof that intended facade symbols are reachable via
//! `soldier_core::execution::{...}`.

#[allow(unused_imports)]
use crate::execution::{
    AtomicGroup, ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateRejectCodes,
    GateResults, GateStep, GroupConfig, GroupError, GroupLock, GroupState, GroupStateTransition,
    LABEL_MAX_LEN, LabelError, LabelInput, LegResult, LockAcquisitionResult, OooCategory,
    OrderSize, PersistedTransition, RecordedBeforeDispatchGate, RejectReasonCode, Side, Tlsm,
    TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult, build_gate_results,
    build_order_intent_with_optional_wal_gate, build_order_intent_with_wal_gate, derive_gid12,
    derive_sid8, encode_label, reject_reason_from_chokepoint, reject_reason_registry,
    reject_reason_registry_contains, try_acquire_group_lock,
};

#[test]
fn facade_symbols_reachable() {
    let gates = build_gate_results(
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        true,
        Some(1.0),
        Some(1.0),
    );
    assert!(gates.preflight_passed);
    assert!(gates.pricer_passed);
    assert!(gates.wal_recorded);

    let registry = reject_reason_registry();
    assert!(
        !registry.is_empty(),
        "reject reason registry must not be empty"
    );
    assert!(
        reject_reason_registry_contains(RejectReasonCode::RecordedBeforeDispatchFailed),
        "expected RecordedBeforeDispatchFailed in facade reject reason registry"
    );

    let mapped = reject_reason_from_chokepoint(
        &ChokeRejectReason::RiskStateNotHealthy,
        &GateRejectCodes::default(),
    );
    assert_eq!(mapped, RejectReasonCode::MarginHeadroomRejectOpens);
}
