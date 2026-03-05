use std::collections::HashSet;

use super::test_support_helpers_tests::{
    FailingWalGate, StubWalGate, gate_results_all_passing_failclosed_wal,
};

use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults, GateStep,
    build_order_intent_with_wal_gate,
};
use crate::execution::reject_reason::reject_reason_from_chokepoint;
use crate::execution::{
    GateRejectCodes, RecordedBeforeDispatchGate, RejectReasonCode, reject_reason_registry,
    reject_reason_registry_contains,
};
use crate::risk::RiskState;

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

fn serialize_reason_code_or_panic(code: &RejectReasonCode) -> String {
    match serde_json::to_string(code) {
        Ok(json) => json,
        Err(err) => panic!("serialization failed for {code:?}: {err}"),
    }
}

fn deserialize_reason_code_or_panic(json: &str, context: &str) -> RejectReasonCode {
    match serde_json::from_str(json) {
        Ok(code) => code,
        Err(err) => panic!("deserialization failed for {context}: {err}"),
    }
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
fn test_registry_contains_all_generated_enum_variants() {
    let registry = reject_reason_registry();
    assert_eq!(
        registry,
        RejectReasonCode::ALL,
        "reject_reason_registry must expose generated RejectReasonCode::ALL"
    );

    let unique: HashSet<&'static str> = registry.iter().map(|code| code.as_str()).collect();
    assert_eq!(
        unique.len(),
        registry.len(),
        "generated reject reason registry contains duplicate as_str tokens"
    );
}

#[test]
fn test_registry_contains_contract_minimum_set() {
    // Mechanical verify expects this contract-minimum anchor test name.
    // Keep the set small and representative of OPEN gate, fee gate, and WAL gate coverage.
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

#[test]
fn test_reject_reason_serde_round_trip() {
    let code = RejectReasonCode::NetEdgeTooLow;
    let json = serialize_reason_code_or_panic(&code);
    assert_eq!(json, r#""NET_EDGE_TOO_LOW""#);

    let deserialized = deserialize_reason_code_or_panic(&json, "NET_EDGE_TOO_LOW");
    assert_eq!(deserialized, code);

    let code2 = RejectReasonCode::InsufficientDepthWithinBudget;
    let json2 = serialize_reason_code_or_panic(&code2);
    assert_eq!(json2, r#""INSUFFICIENT_DEPTH_WITHIN_BUDGET""#);
    let deserialized2 =
        deserialize_reason_code_or_panic(&json2, "INSUFFICIENT_DEPTH_WITHIN_BUDGET");
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
        let json = serialize_reason_code_or_panic(&code);
        assert_eq!(json, expected_json, "serde output mismatch for {code:?}");
        let deserialized = deserialize_reason_code_or_panic(&json, code.as_str());
        assert_eq!(deserialized, code, "round-trip mismatch for {code:?}");
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

#[test]
fn test_as_str_matches_serde_output_for_all_variants() {
    for code in RejectReasonCode::ALL {
        let as_str = code.as_str();
        assert!(!as_str.is_empty(), "as_str() returned empty for {:?}", code);
        assert!(
            !code.wire_str().is_empty(),
            "wire_str() returned empty for {:?}",
            code
        );

        let json = serde_json::to_string(code)
            .unwrap_or_else(|e| panic!("serde serialization failed for {:?}: {}", code, e));
        let deserialized: RejectReasonCode = serde_json::from_str(&json)
            .unwrap_or_else(|e| panic!("serde deserialization failed for {:?}: {}", code, e));
        assert_eq!(
            *code, deserialized,
            "serde round-trip mismatch for {:?}",
            code
        );
    }
}
