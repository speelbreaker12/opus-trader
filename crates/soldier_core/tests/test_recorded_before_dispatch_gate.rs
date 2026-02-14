//! Tests for runtime RecordedBeforeDispatch gate helpers.

use soldier_core::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults,
    RecordedBeforeDispatchGate, build_order_intent_with_optional_wal_gate,
    build_order_intent_with_wal_gate,
};
use soldier_core::risk::RiskState;

struct StubWalGate {
    should_succeed: bool,
    call_count: usize,
}

impl RecordedBeforeDispatchGate for StubWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.call_count += 1;
        if self.should_succeed {
            Ok(())
        } else {
            Err("wal append failed".to_string())
        }
    }
}

#[test]
fn test_optional_wal_gate_missing_is_fail_closed() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();

    let result = build_order_intent_with_optional_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        None,
    );

    match result {
        ChokeResult::Rejected { reason, .. } => match reason {
            ChokeRejectReason::GateRejected { gate, .. } => {
                assert_eq!(format!("{gate:?}"), "RecordedBeforeDispatch")
            }
            other => panic!("unexpected reject reason: {other:?}"),
        },
        other => panic!("expected rejected, got {other:?}"),
    }
}

#[test]
fn test_wal_gate_failure_rejects() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();
    let mut wal_gate = StubWalGate {
        should_succeed: false,
        call_count: 0,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(matches!(result, ChokeResult::Rejected { .. }));
    assert_eq!(wal_gate.call_count, 1);
}

#[test]
fn test_wal_gate_success_allows() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();
    let mut wal_gate = StubWalGate {
        should_succeed: true,
        call_count: 0,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(matches!(result, ChokeResult::Approved { .. }));
    assert_eq!(wal_gate.call_count, 1);
}

#[test]
fn test_wal_gate_not_called_when_risk_state_rejects_early() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults::default();
    let mut wal_gate = StubWalGate {
        should_succeed: true,
        call_count: 0,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Degraded,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::RiskStateNotHealthy,
            ..
        }
    ));
    assert_eq!(wal_gate.call_count, 0);
}

#[test]
fn test_wal_gate_not_called_when_preflight_rejects_early() {
    let mut metrics = ChokeMetrics::new();
    let gates = GateResults {
        preflight_passed: false,
        ..GateResults::default()
    };
    let mut wal_gate = StubWalGate {
        should_succeed: true,
        call_count: 0,
    };

    let result = build_order_intent_with_wal_gate(
        ChokeIntentClass::Open,
        RiskState::Healthy,
        &mut metrics,
        &gates,
        &mut wal_gate,
    );

    assert!(matches!(
        result,
        ChokeResult::Rejected {
            reason: ChokeRejectReason::GateRejected { .. },
            ..
        }
    ));
    assert_eq!(wal_gate.call_count, 0);
}
