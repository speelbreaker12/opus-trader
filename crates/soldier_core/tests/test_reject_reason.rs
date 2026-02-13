use std::collections::HashSet;

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateResults, RejectReasonCode,
    build_order_intent_with_reject_reason_code, reject_reason_registry,
    reject_reason_registry_contains,
};
use soldier_core::risk::RiskState;

#[test]
fn test_reject_reason_present_on_pre_dispatch_reject() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();

    let (result, code) = build_order_intent_with_reject_reason_code(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
    );

    assert!(matches!(result, ChokeResult::Rejected { .. }));
    assert_eq!(code, Some(RejectReasonCode::MarginHeadroomRejectOpens));
}

#[test]
fn test_reject_reason_in_registry() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults {
        liquidity_gate_passed: false,
        ..GateResults::default()
    };

    let (_, code) = build_order_intent_with_reject_reason_code(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
    );

    let code = code.expect("pre-dispatch reject must include reject_reason_code");
    assert!(
        reject_reason_registry_contains(code),
        "reject_reason_code must be a member of RejectReasonCode"
    );
}

#[test]
fn test_registry_contains_contract_minimum_set() {
    let registry_tokens: HashSet<&'static str> = reject_reason_registry()
        .iter()
        .map(|code| code.as_str())
        .collect();

    let minimum = [
        "TooSmallAfterQuantization",
        "InstrumentMetadataMissing",
        "ChurnBreakerActive",
        "LiquidityGateNoL2",
        "EmergencyCloseNoPrice",
        "ExpectedSlippageTooHigh",
        "NetEdgeTooLow",
        "NetEdgeInputMissing",
        "InventorySkew",
        "InventorySkewDeltaLimitMissing",
        "PendingExposureBudgetExceeded",
        "GlobalExposureBudgetExceeded",
        "ContractsAmountMismatch",
        "MarginHeadroomRejectOpens",
        "OrderTypeMarketForbidden",
        "OrderTypeStopForbidden",
        "LinkedOrderTypeForbidden",
        "PostOnlyWouldCross",
        "RiskIncreasingCancelReplaceForbidden",
        "RateLimitBrownout",
        "InstrumentExpiredOrDelisted",
        "FeedbackLoopGuardActive",
        "LabelTooLong",
    ];

    for token in minimum {
        assert!(
            registry_tokens.contains(token),
            "RejectReasonCode registry missing contract token {token}"
        );
    }
}
