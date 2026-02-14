//! Execution types, sizing logic, dispatch mapping, quantization, labeling, and preflight.

use std::cell::RefCell;
use std::collections::VecDeque;

pub mod build_order_intent;
pub mod dispatch_map;
pub mod gate;
pub mod gates;
pub mod label;
pub mod order_size;
pub mod pipeline;
pub mod post_only_guard;
pub mod preflight;
pub mod pricer;
pub mod quantize;
pub mod tlsm;

pub use build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateResults,
    GateSequenceResult, GateStep, build_gate_results, build_order_intent, gate_sequence_total,
};
pub use dispatch_map::{
    CONTRACTS_AMOUNT_MATCH_TOLERANCE, DispatchMapError, DispatchRequest, IntentClass,
    MismatchMetrics, ValidatedDispatch, map_to_dispatch, validate_and_dispatch,
};
pub use gate::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateRejectReason, LiquidityGateResult, evaluate_liquidity_gate,
};
pub use gates::{
    NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge,
};
pub use label::{
    LABEL_MAX_LEN, LabelError, LabelInput, ParsedLabel, decode_label, derive_gid12, derive_sid8,
    encode_label,
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
pub use tlsm::{Tlsm, TlsmEvent, TlsmState, TransitionResult};

#[derive(Debug, Clone)]
struct ExecutionTraceIds {
    intent_id: String,
    run_id: String,
}

thread_local! {
    static EXECUTION_TRACE_IDS: RefCell<Option<ExecutionTraceIds>> = const { RefCell::new(None) };
    static EXECUTION_METRIC_LINES: RefCell<VecDeque<String>> = const { RefCell::new(VecDeque::new()) };
}

const EXECUTION_METRIC_LINES_MAX: usize = 512;

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
    eprintln!("{line}");
    EXECUTION_METRIC_LINES.with(|cell| {
        let mut lines = cell.borrow_mut();
        lines.push_back(line);
        if lines.len() > EXECUTION_METRIC_LINES_MAX {
            let _ = lines.pop_front();
        }
    });
}
