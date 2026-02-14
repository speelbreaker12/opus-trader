//! Execution types, sizing logic, dispatch mapping, quantization, labeling, and preflight.

use std::cell::RefCell;
use std::collections::VecDeque;

const MAX_EXECUTION_METRIC_LINES: usize = 4096;

pub mod build_order_intent;
pub mod dispatch_map;
pub mod gate;
pub mod gates;
pub mod inventory_skew;
pub mod label;
pub mod open_runtime;
pub mod order_size;
pub mod pipeline;
pub mod post_only_guard;
pub mod preflight;
pub mod pricer;
pub mod quantize;
pub mod reject_reason;
pub mod tlsm;

pub use build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults,
    GateSequenceResult, GateStep, RecordedBeforeDispatchGate, build_gate_results,
    build_order_intent, build_order_intent_with_optional_wal_gate,
    build_order_intent_with_reject_reason_code, build_order_intent_with_wal_gate,
    gate_sequence_total,
};
pub use dispatch_map::{
    CONTRACTS_AMOUNT_MATCH_TOLERANCE, DispatchMapError, DispatchRequest, IntentClass,
    MismatchMetrics, ValidatedDispatch, map_to_dispatch, validate_and_dispatch,
};
pub use gate::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateRejectReason, LiquidityGateResult, evaluate_liquidity_gate,
    expected_slippage_bps_samples, liquidity_gate_reject_total,
};
pub use gates::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
    net_edge_reject_total,
};
pub use inventory_skew::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    InventorySkewSide, evaluate_inventory_skew,
};
pub use label::{
    LABEL_MAX_LEN, LabelError, LabelInput, ParsedLabel, decode_label, derive_gid12, derive_sid8,
    encode_label,
};
pub use open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, OpenRuntimeOutput, build_open_order_intent_runtime,
};
pub use order_size::{OrderSize, OrderSizeError, OrderSizeInput, build_order_size};
pub use pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, PipelineResult, QuantizePipelineInput,
    evaluate_intent_pipeline,
};
pub use post_only_guard::{PostOnlyInput, PostOnlyMetrics, PostOnlyResult, check_post_only};
pub use preflight::{
    OrderType, PreflightInput, PreflightMetrics, PreflightReject, PreflightResult,
    preflight_intent, preflight_reject_total,
};
pub use pricer::{
    PricerInput, PricerMetrics, PricerRejectReason, PricerResult, PricerSide, compute_limit_price,
};
pub use quantize::{
    QuantizeConstraints, QuantizeError, QuantizeMetrics, QuantizedValues, Side, quantize,
};
pub use reject_reason::{
    GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint, reject_reason_registry,
    reject_reason_registry_contains,
};
pub use tlsm::{
    NoopTransitionSink, PersistedTransition, Tlsm, TlsmError, TlsmEvent, TlsmState,
    TlsmTransitionSink, TransitionResult,
};

#[derive(Debug, Clone)]
struct ExecutionTraceIds {
    intent_id: String,
    run_id: String,
}

thread_local! {
    static EXECUTION_TRACE_IDS: RefCell<Option<ExecutionTraceIds>> = const { RefCell::new(None) };
    static EXECUTION_METRIC_LINES: RefCell<VecDeque<String>> = const { RefCell::new(VecDeque::new()) };
}

pub fn with_intent_trace_ids<F, R>(intent_id: &str, run_id: &str, f: F) -> R
where
    F: FnOnce() -> R,
{
    EXECUTION_TRACE_IDS.with(|cell| {
        let previous = cell.borrow_mut().replace(ExecutionTraceIds {
            intent_id: intent_id.to_string(),
            run_id: run_id.to_string(),
        });
        let result = f();
        *cell.borrow_mut() = previous;
        result
    })
}

pub fn take_execution_metric_lines() -> Vec<String> {
    EXECUTION_METRIC_LINES.with(|cell| cell.borrow_mut().drain(..).collect())
}

pub(crate) fn emit_execution_metric_line(metric_name: &str, tail_fields: &str) {
    let trace_ids = EXECUTION_TRACE_IDS.with(|cell| cell.borrow().clone());
    let mut line = String::from(metric_name);
    if let Some(trace) = trace_ids {
        line.push_str(" intent_id=");
        line.push_str(&trace.intent_id);
        line.push_str(" run_id=");
        line.push_str(&trace.run_id);
    }
    if !tail_fields.is_empty() {
        line.push(' ');
        line.push_str(tail_fields);
    }
    tracing::debug!("{line}");
    EXECUTION_METRIC_LINES.with(|cell| {
        let mut lines = cell.borrow_mut();
        if lines.len() >= MAX_EXECUTION_METRIC_LINES {
            lines.pop_front();
        }
        lines.push_back(line);
    });
}

#[cfg(test)]
mod tests {
    use super::{emit_execution_metric_line, take_execution_metric_lines};

    #[test]
    fn execution_metric_buffer_is_bounded() {
        let _ = take_execution_metric_lines();

        for i in 0..5_000 {
            emit_execution_metric_line("execution_metric_buffer_test", &format!("i={i}"));
        }

        let lines = take_execution_metric_lines();
        assert!(
            lines.len() <= 4_096,
            "execution metric buffer should be bounded"
        );
    }
}
