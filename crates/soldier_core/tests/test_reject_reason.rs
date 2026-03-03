#[path = "test_stubs.rs"]
mod test_stubs;
use test_stubs::{FailingWalGate, StubWalGate, gate_results_all_passing_failclosed_wal};

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateRejectCodes, GateResults,
    GateStep, RecordedBeforeDispatchGate, RejectReasonCode, build_order_intent_with_wal_gate,
    reject_reason_from_chokepoint, reject_reason_registry_contains,
};
use soldier_core::risk::RiskState;

fn build_chokepoint_result(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    gates: &GateResults,
    wal_gate: &mut dyn RecordedBeforeDispatchGate,
) -> ChokeResult {
    let mut metrics = ChokeMetrics::new();
    build_order_intent_with_wal_gate(intent_class, risk_state, &mut metrics, gates, wal_gate)
}

fn build_chokepoint_result_with_stub_wal(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    gates: &GateResults,
) -> ChokeResult {
    let mut wal_gate = StubWalGate;
    build_chokepoint_result(intent_class, risk_state, gates, &mut wal_gate)
}

#[test]
fn test_reject_reason_present_on_pre_dispatch_reject() {
    let gates = gate_results_all_passing_failclosed_wal();

    let result =
        build_chokepoint_result_with_stub_wal(ChokeIntentClass::Open, RiskState::Degraded, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
    let mapped = reject_reason_from_chokepoint(
        &ChokeRejectReason::RiskStateNotHealthy,
        &GateRejectCodes::default(),
    );
    assert_eq!(mapped, RejectReasonCode::MarginHeadroomRejectOpens);
}

#[test]
fn test_reject_reason_in_registry() {
    let code = RejectReasonCode::LiquidityGateNoL2;
    assert!(
        reject_reason_registry_contains(code),
        "reject_reason_code must be a member of RejectReasonCode"
    );
}

#[test]
fn test_preflight_reject_surfaces_preflight_gate_step() {
    let gates = GateResults {
        preflight_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };

    let result =
        build_chokepoint_result_with_stub_wal(ChokeIntentClass::Open, RiskState::Healthy, &gates);

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected {
                gate: GateStep::Preflight,
                ..
            },
            ..
        }
    ));
}

#[test]
fn test_fee_cache_check_surfaces_fee_cache_gate_step() {
    let gates = GateResults {
        fee_cache_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };

    let result =
        build_chokepoint_result_with_stub_wal(ChokeIntentClass::Open, RiskState::Healthy, &gates);

    let reason = match result {
        ChokeResult::Rejected { reason, .. } => reason,
        other => panic!("expected rejection, got {other:?}"),
    };
    assert!(matches!(
        reason,
        ChokeRejectReason::GateRejected {
            gate: GateStep::FeeCacheCheck,
            ..
        }
    ));

    let mapped = reject_reason_from_chokepoint(
        &reason,
        &GateRejectCodes {
            fee_cache: Some(RejectReasonCode::FeeCacheStale),
            ..GateRejectCodes::default()
        },
    );
    assert_eq!(mapped, RejectReasonCode::FeeCacheStale);
}

#[test]
fn test_recorded_before_dispatch_surfaces_wal_gate_step() {
    let gates = gate_results_all_passing_failclosed_wal();
    let mut wal_gate = FailingWalGate;

    let result = build_chokepoint_result(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &gates,
        &mut wal_gate,
    );

    let reason = match result {
        ChokeResult::Rejected { reason, .. } => reason,
        other => panic!("expected rejection, got {other:?}"),
    };
    assert!(matches!(
        reason,
        ChokeRejectReason::GateRejected {
            gate: GateStep::RecordedBeforeDispatch,
            ..
        }
    ));

    let mapped = reject_reason_from_chokepoint(
        &reason,
        &GateRejectCodes {
            recorded_before_dispatch: Some(RejectReasonCode::RecordedBeforeDispatchFailed),
            ..GateRejectCodes::default()
        },
    );
    assert_eq!(mapped, RejectReasonCode::RecordedBeforeDispatchFailed);
}

#[test]
fn test_preflight_gate_rejection_maps_to_specific_reason_code() {
    let gates = GateResults {
        preflight_passed: false,
        ..gate_results_all_passing_failclosed_wal()
    };
    let result =
        build_chokepoint_result_with_stub_wal(ChokeIntentClass::Open, RiskState::Healthy, &gates);

    let reason = match result {
        ChokeResult::Rejected { reason, .. } => reason,
        other => panic!("expected rejection, got {other:?}"),
    };
    assert!(matches!(
        reason,
        ChokeRejectReason::GateRejected {
            gate: GateStep::Preflight,
            ..
        }
    ));

    let mapped = reject_reason_from_chokepoint(
        &reason,
        &GateRejectCodes {
            preflight: Some(RejectReasonCode::OrderTypeMarketForbidden),
            ..GateRejectCodes::default()
        },
    );
    assert_eq!(mapped, RejectReasonCode::OrderTypeMarketForbidden);
}

#[test]
fn all_generated_reject_reason_codes_round_trip() {
    for code in RejectReasonCode::ALL {
        assert!(
            reject_reason_registry_contains(*code),
            "RejectReasonCode::ALL member must be in registry: {code:?}"
        );

        let json = serde_json::to_string(code).expect("serialize reject reason");
        let back: RejectReasonCode =
            serde_json::from_str(&json).expect("deserialize reject reason");
        assert_eq!(*code, back, "serde round-trip mismatch for {code:?}");

        assert!(!code.as_str().is_empty(), "empty as_str() for {code:?}");
        assert!(!code.wire_str().is_empty(), "empty wire_str() for {code:?}");
    }
}

#[test]
fn test_reject_reason_serde_round_trip() {
    let code = RejectReasonCode::NetEdgeTooLow;
    let json = serde_json::to_string(&code).expect("serialization failed");
    assert_eq!(json, r#""NET_EDGE_TOO_LOW""#);

    let deserialized: RejectReasonCode =
        serde_json::from_str(&json).expect("deserialization failed");
    assert_eq!(deserialized, code);

    let code2 = RejectReasonCode::InsufficientDepthWithinBudget;
    let json2 = serde_json::to_string(&code2).expect("serialization failed");
    assert_eq!(json2, r#""INSUFFICIENT_DEPTH_WITHIN_BUDGET""#);
    let deserialized2: RejectReasonCode =
        serde_json::from_str(&json2).expect("deserialization failed");
    assert_eq!(deserialized2, code2);
}

/// GAP-FE-001: Serde round-trip for the 3 new reject reason codes.
#[test]
fn test_reject_reason_serde_round_trip_fe001_codes() {
    let cases = [
        (
            RejectReasonCode::PricerInputMissing,
            r#""PRICER_INPUT_MISSING""#,
        ),
        (
            RejectReasonCode::PricerInputInvalid,
            r#""PRICER_INPUT_INVALID""#,
        ),
        (RejectReasonCode::GateCascadeSkip, r#""GATE_CASCADE_SKIP""#),
    ];
    for (code, expected_json) in cases {
        let json = serde_json::to_string(&code).expect("serialization failed");
        assert_eq!(json, expected_json, "serde output mismatch for {code:?}");
        let deserialized: RejectReasonCode =
            serde_json::from_str(&json).expect("deserialization failed");
        assert_eq!(deserialized, code, "round-trip mismatch for {code:?}");
    }
}

#[test]
fn test_registry_contains_contract_minimum_set() {
    let required = [
        RejectReasonCode::MarginHeadroomRejectOpens,
        RejectReasonCode::OrderTypeMarketForbidden,
        RejectReasonCode::FeeCacheStale,
        RejectReasonCode::RecordedBeforeDispatchFailed,
    ];
    for code in required {
        assert!(
            reject_reason_registry_contains(code),
            "reject_reason_registry missing required contract code {code:?}"
        );
    }
}

/// AT-201: unknown external actions MUST be classified as Open at the intake boundary.
/// This test proves the gate side of AT-201: Open-classified intents are blocked by OPEN gates.
///
/// NOTE: The "unknown action → Open classification" step happens at the external API /
/// deserialization boundary (before soldier_core). That boundary is responsible for
/// defaulting unknown action strings to ChokeIntentClass::Open (fail-closed). This test
/// proves that if that classification is correct, the downstream gates enforce correctly.
/// The reason code is MarginHeadroomRejectOpens (RiskStateNotHealthy path).
#[test]
fn test_at201_open_classified_intent_blocked_by_open_gates() {
    // Open classification (assigned to unknown actions at the intake boundary) + Degraded → blocked
    let mut m_open = ChokeMetrics::new();
    let mut wal_gate = StubWalGate;
    let result_open = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut m_open,
        &gate_results_all_passing_failclosed_wal(),
        &mut wal_gate,
    );
    assert!(
        matches!(
            result_open,
            ChokeResult::Rejected {
                reason: ChokeRejectReason::RiskStateNotHealthy,
                ..
            }
        ),
        "Open (default for unknown actions) + Degraded must be rejected"
    );
    assert_eq!(m_open.approved_total(), 0, "OPEN dispatch count must be 0");
    assert!(
        reject_reason_registry_contains(RejectReasonCode::MarginHeadroomRejectOpens),
        "MarginHeadroomRejectOpens must be part of RejectReasonCode registry"
    );

    // Contrast: Close (explicitly risk-reducing) is NOT blocked by Degraded
    let mut m_close = ChokeMetrics::new();
    let mut wal_gate = StubWalGate;
    let result_close = build_order_intent_with_wal_gate(
        ChokeIntentClass::Close,
        RiskState::Degraded,
        &mut m_close,
        &gate_results_all_passing_failclosed_wal(),
        &mut wal_gate,
    );
    assert!(
        matches!(result_close, ChokeResult::Approved { .. }),
        "Close (known risk-reducing) must NOT be blocked when Degraded"
    );
    assert_eq!(
        m_close.approved_total(),
        1,
        "CLOSE dispatch count must be 1"
    );
}
