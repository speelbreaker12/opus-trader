//! Property-based tests for GI-001: "OPEN intents MUST be blocked when
//! RiskState != Healthy" (CONTRACT.md §2.2).
//!
//! Properties under test:
//! - Open + non-Healthy risk state → Rejected with MarginHeadroomRejectOpens.
//! - Open + Healthy → pipeline does NOT reject at DispatchAuth (may reject elsewhere).
//! - Close/Hedge/CancelOnly + non-Healthy → NOT rejected with MarginHeadroomRejectOpens.

mod common;

use proptest::prelude::*;
use soldier_core::execution::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, GateStep, IntentPipelineMetrics,
    RejectReasonCode, evaluate_intent_pipeline,
};
use soldier_core::risk::RiskState;

fn non_healthy_risk_state() -> impl Strategy<Value = RiskState> {
    prop_oneof![
        Just(RiskState::Degraded),
        Just(RiskState::Maintenance),
        Just(RiskState::Kill),
    ]
}

fn non_open_intent_class() -> impl Strategy<Value = ChokeIntentClass> {
    prop_oneof![
        Just(ChokeIntentClass::Close),
        Just(ChokeIntentClass::Hedge),
        Just(ChokeIntentClass::CancelOnly),
    ]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// GI-001: Open + non-Healthy → Rejected(RiskStateNotHealthy) with
    /// reject_reason_code == MarginHeadroomRejectOpens.
    #[test]
    fn gi001_open_non_healthy_rejected(risk_state in non_healthy_risk_state()) {
        let mut input = common::base_open_input();
        input.risk_state = risk_state;
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Must be Rejected
        match &result.decision {
            ChokeResult::Rejected { reason, gate_trace } => {
                prop_assert!(
                    matches!(reason, ChokeRejectReason::RiskStateNotHealthy),
                    "expected RiskStateNotHealthy, got {:?}", reason
                );
                prop_assert_eq!(
                    gate_trace, &vec![GateStep::DispatchAuth],
                    "expected only DispatchAuth in gate_trace"
                );
            }
            other => {
                prop_assert!(false, "expected Rejected, got {:?}", other);
            }
        }

        // Reject reason code must be MarginHeadroomRejectOpens
        prop_assert_eq!(
            result.reject_reason_code,
            Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "GI-001: reject_reason_code should be MarginHeadroomRejectOpens"
        );

        // Chokepoint metrics: rejected_total should increment
        prop_assert!(
            metrics.chokepoint.rejected_total() > 0,
            "chokepoint rejected_total should be > 0"
        );

        // Preflight metrics should NOT increment (skipped due to short-circuit)
        prop_assert_eq!(
            metrics.preflight.reject_total(), 0,
            "preflight should not have been evaluated"
        );
    }

    /// Open + Healthy → NOT rejected at DispatchAuth (pipeline continues).
    #[test]
    fn open_healthy_passes_dispatch_auth(_dummy in 0..1u8) {
        let input = common::base_open_input();
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Should be Approved (all gates pass in base input)
        match &result.decision {
            ChokeResult::Approved { gate_trace } => {
                // Gate trace should include gates beyond DispatchAuth
                prop_assert!(
                    gate_trace.len() > 1,
                    "healthy open should pass multiple gates, trace={:?}", gate_trace
                );
            }
            ChokeResult::Rejected { reason, .. } => {
                // If rejected, it must NOT be RiskStateNotHealthy
                prop_assert!(
                    !matches!(reason, ChokeRejectReason::RiskStateNotHealthy),
                    "healthy open should not be rejected for RiskStateNotHealthy"
                );
            }
        }

        // Reject reason code should NOT be MarginHeadroomRejectOpens
        prop_assert!(
            result.reject_reason_code != Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "healthy open should not produce MarginHeadroomRejectOpens"
        );
    }

    /// Non-open intents + non-Healthy → NOT rejected with MarginHeadroomRejectOpens.
    /// (GI-001 only applies to Open intents.)
    #[test]
    fn non_open_non_healthy_not_margin_rejected(
        intent_class in non_open_intent_class(),
        risk_state in non_healthy_risk_state(),
    ) {
        let mut input = common::base_open_input();
        input.intent_class = intent_class;
        input.risk_state = risk_state;
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);

        // Should NOT produce MarginHeadroomRejectOpens
        prop_assert!(
            result.reject_reason_code != Some(RejectReasonCode::MarginHeadroomRejectOpens),
            "non-open intent {:?} with risk_state {:?} should not produce MarginHeadroomRejectOpens, got {:?}",
            intent_class, risk_state, result.reject_reason_code
        );
    }
}
