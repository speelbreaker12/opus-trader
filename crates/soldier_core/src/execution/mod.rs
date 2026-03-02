//! Execution types, sizing logic, dispatch mapping, quantization, labeling, and preflight.

use std::cell::RefCell;
use std::collections::VecDeque;

const MAX_EXECUTION_METRIC_LINES: usize = 4096;

// ─── Metric name constants ─────────────────────────────────────────────
// Shared across modules to prevent string-literal drift.
pub(crate) const METRIC_GATE_SEQUENCE_TOTAL: &str = "gate_sequence_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_LIQUIDITY_GATE_REJECT: &str = "liquidity_gate_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_NET_EDGE_REJECT: &str = "net_edge_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_EXPECTED_SLIPPAGE_BPS: &str = "expected_slippage_bps";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_QUANTIZE_REJECT: &str = "quantize_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_PRICER_REJECT: &str = "pricer_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_INVENTORY_SKEW_REJECT: &str = "inventory_skew_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_POST_ONLY_REJECT: &str = "post_only_reject_total";
pub(crate) const METRIC_FEE_STALENESS_REJECT: &str = "fee_staleness_hard_stale_total";
pub(crate) const METRIC_MARGIN_GATE_REJECT: &str = "margin_gate_reject_total";
pub(crate) const METRIC_PENDING_EXPOSURE_REJECT: &str = "pending_exposure_reject_total";
pub(crate) const METRIC_EXPOSURE_BUDGET_REJECT: &str = "exposure_budget_reject_total";
pub(crate) const METRIC_GROUP_LOCK_TIMEOUT: &str = "group_lock_timeout_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_GROUP_PERSIST_FAIL: &str = "group_persist_fail_total";
pub(crate) const METRIC_GROUP_MIXED_FAILED: &str = "group_mixed_failed_total";
#[allow(dead_code)] // Reserved for expiry guard instrumentation
pub(crate) const METRIC_EXPIRY_GUARD_REJECT: &str = "expiry_guard_reject_total";
#[allow(dead_code)] // Phase-1 facade lockdown: consumed by internal modules.
pub(crate) const METRIC_PREFLIGHT_REJECT: &str = "preflight_reject_total";

mod api;

// NOTE: During Phase-1 facade lockdown these modules are intentionally private.
// Keep `dead_code` allowances item-scoped so dead-symbol drift remains visible.
#[cfg_attr(not(test), allow(dead_code))]
mod base_gates;
#[cfg_attr(not(test), allow(dead_code))]
mod build_order_intent;
#[cfg_attr(not(test), allow(dead_code))]
mod dispatch_map;
#[cfg_attr(not(test), allow(dead_code))]
mod domain_model;
#[cfg_attr(not(test), allow(dead_code))]
mod engine;
#[cfg_attr(not(test), allow(dead_code))]
mod gate;
#[cfg_attr(not(test), allow(dead_code))]
mod gate_outcome;
#[cfg_attr(not(test), allow(dead_code))]
mod gates;
#[cfg_attr(not(test), allow(dead_code))]
mod group;
#[cfg_attr(not(test), allow(dead_code))]
mod intent_assembly;
#[cfg_attr(not(test), allow(dead_code))]
mod inventory_skew;
#[cfg_attr(not(test), allow(dead_code))]
mod label;
#[cfg_attr(not(test), allow(dead_code))]
mod open_runtime;
#[cfg_attr(not(test), allow(dead_code))]
mod order_size;
#[cfg_attr(not(test), allow(dead_code))]
mod pipeline;
#[cfg_attr(not(test), allow(dead_code))]
mod post_only_guard;
#[cfg_attr(not(test), allow(dead_code))]
mod preflight;
#[cfg_attr(not(test), allow(dead_code))]
mod pricer;
#[cfg_attr(not(test), allow(dead_code))]
mod quantize;
mod reject_reason;
#[cfg_attr(not(test), allow(dead_code))]
mod tlsm;

#[cfg(test)]
mod adversarial_gi_enforcement_tests;
#[cfg(test)]
mod dispatch_chokepoint_contract_tests;
#[cfg(test)]
mod facade_completeness_contract_tests;
#[cfg(test)]
mod recorded_before_dispatch_gate_tests;
#[cfg(test)]
mod reject_reason_contract_tests;
#[cfg(test)]
mod test_support_tests;

pub use api::*;

#[derive(Debug, Clone)]
struct ExecutionTraceIds {
    intent_id: String,
    run_id: String,
}

thread_local! {
    static EXECUTION_TRACE_IDS: RefCell<Option<ExecutionTraceIds>> = const { RefCell::new(None) };
    static EXECUTION_METRIC_LINES: RefCell<VecDeque<String>> = const { RefCell::new(VecDeque::new()) };
}

#[cfg(test)]
pub(crate) static METRICS_TEST_LOCK: std::sync::Mutex<()> = std::sync::Mutex::new(());

#[allow(dead_code)] // Phase-1 facade lockdown: currently consumed by unit/integration tests.
pub(crate) fn with_intent_trace_ids<F, R>(intent_id: &str, run_id: &str, f: F) -> R
where
    F: FnOnce() -> R,
{
    // Manual Drop guard ensures trace IDs are restored even if `f()` panics.
    struct RestoreGuard {
        previous: Option<ExecutionTraceIds>,
    }
    impl Drop for RestoreGuard {
        fn drop(&mut self) {
            EXECUTION_TRACE_IDS.with(|cell| {
                *cell.borrow_mut() = self.previous.take();
            });
        }
    }

    EXECUTION_TRACE_IDS.with(|cell| {
        let previous = cell.borrow_mut().replace(ExecutionTraceIds {
            intent_id: intent_id.to_string(),
            run_id: run_id.to_string(),
        });
        let _guard = RestoreGuard { previous };
        f()
    })
}

#[allow(dead_code)] // Phase-1 facade lockdown: currently consumed by unit/integration tests.
pub(crate) fn take_execution_metric_lines() -> Vec<String> {
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

#[cfg(test)]
mod api_completeness_tests {
    #[allow(unused_imports)]
    use super::api::{
        AtomicGroup, CancelOnlyExecutionInput, ChokeIntentClass, ChokeMetrics, ChokeRejectReason,
        ChokeResult, CloseExecutionInput, ExecutionDecision, ExecutionEngine, ExecutionInput,
        ExecutionRuntime, GateRejectCodes, GateResults, GateStep, GroupConfig, GroupError,
        GroupLock, GroupState, GroupStateTransition, HedgeExecutionInput, LABEL_MAX_LEN,
        LabelError, LabelInput, LegResult, LockAcquisitionResult, OooCategory, OpenExecutionInput,
        OpenMetadata, OrderSize, PersistedTransition, RecordedBeforeDispatchGate, RejectReasonCode,
        Side, Tlsm, TlsmError, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
        build_gate_results, build_order_intent_with_optional_wal_gate,
        build_order_intent_with_wal_gate, derive_gid12, derive_sid8, encode_label,
        open_runtime_to_decision, pipeline_result_to_decision, reject_reason_from_chokepoint,
        reject_reason_registry, reject_reason_registry_contains, try_acquire_group_lock,
    };

    #[test]
    fn api_module_exports_all_facade_symbols() {}
}
