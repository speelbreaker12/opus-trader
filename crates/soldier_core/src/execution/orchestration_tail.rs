//! Shared chokepoint tail used by both the generic pipeline and OPEN runtime.

use crate::risk::RiskState;

#[allow(deprecated)] // PrecomputedWalGate is a migration shim (GAP-FE-004)
use super::build_order_intent::PrecomputedWalGate;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateResults, build_order_intent_with_wal_gate,
};
use super::reject_reason::{GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint};

#[derive(Debug, Clone, PartialEq)]
pub(crate) struct OrchestrationTailResult {
    pub decision: ChokeResult,
    pub reject_reason_code: Option<RejectReasonCode>,
}

pub(crate) fn run_orchestration_tail(
    intent_class: ChokeIntentClass,
    risk_state: RiskState,
    chokepoint_metrics: &mut ChokeMetrics,
    gate_results: &GateResults,
    gate_reject_codes: &GateRejectCodes,
) -> OrchestrationTailResult {
    #[allow(deprecated)] // PrecomputedWalGate is a migration shim (GAP-FE-004)
    let mut wal_gate = PrecomputedWalGate {
        recorded: gate_results.wal_recorded,
    };
    let decision = build_order_intent_with_wal_gate(
        intent_class,
        risk_state,
        chokepoint_metrics,
        gate_results,
        &mut wal_gate,
    );
    let reject_reason_code = if let ChokeResult::Rejected { reason, .. } = &decision {
        Some(reject_reason_from_chokepoint(reason, gate_reject_codes))
    } else {
        None
    };

    OrchestrationTailResult {
        decision,
        reject_reason_code,
    }
}
