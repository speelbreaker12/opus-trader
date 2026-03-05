//! Execution engine: single public entrypoint for intent evaluation.
//!
//! PR1 scope keeps delegation paths intact:
//! - OPEN -> `build_open_order_intent_runtime`
//! - CLOSE/HEDGE/CANCEL_ONLY -> `evaluate_intent_pipeline`

use crate::execution::ChokeResult::{Approved as ChokeApproved, Rejected as ChokeRejected};
use crate::execution::open_runtime::{
    OpenRuntimeInput, OpenRuntimeMetrics, OpenRuntimeOutput, build_open_order_intent_runtime,
};
use crate::execution::pipeline::{
    IntentPipelineInput, IntentPipelineMetrics, evaluate_intent_pipeline,
};
use crate::execution::{
    ChokeIntentClass, ChokeMetrics, ChokeRejectReason, ChokeResult, GateRejectCodes, GateStep,
    RejectReasonCode, reject_reason_from_chokepoint,
};
use crate::risk::{MarginGateMode, PendingExposureBook, ReservationId, RiskState};

const REJECT_REASON_PENDING_EXPOSURE_OVERFILL: &str = "PENDING_EXPOSURE_OVERFILL";
const REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED: &str =
    "PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED";
const REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT: &str = "GLOBAL_EXPOSURE_BUDGET_REJECT";

// ─── Public API ─────────────────────────────────────────────────────────

#[derive(Debug, Clone)]
pub struct OpenExecutionInput<'a> {
    pub input: OpenRuntimeInput<'a>,
    pub gate_reject_codes: GateRejectCodes,
}

#[derive(Debug, Clone)]
pub struct CloseExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

#[derive(Debug, Clone)]
pub struct HedgeExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

#[derive(Debug, Clone)]
pub struct CancelOnlyExecutionInput<'a> {
    pub input: IntentPipelineInput<'a>,
}

/// Execution input discriminated by intent class.
#[derive(Debug, Clone)]
#[allow(clippy::large_enum_variant)] // Keep borrowed, allocation-free call path in PR1.
pub enum ExecutionInput<'a> {
    Open(OpenExecutionInput<'a>),
    Close(CloseExecutionInput<'a>),
    Hedge(HedgeExecutionInput<'a>),
    CancelOnly(CancelOnlyExecutionInput<'a>),
}

/// Execution decision: approved or rejected.
#[derive(Debug, Clone, PartialEq)]
pub enum ExecutionDecision {
    Approved {
        gate_trace: Vec<GateStep>,
        open_metadata: Option<OpenMetadata>,
    },
    Rejected {
        code: RejectReasonCode,
        step: GateStep,
        detail: String,
    },
}

/// OPEN-path metadata surfaced in `ExecutionDecision::Approved`.
#[derive(Debug, Clone, PartialEq)]
pub struct OpenMetadata {
    pub pending_reservation_id: Option<ReservationId>,
    pub effective_risk_state: RiskState,
    pub adjusted_min_edge_usd: Option<f64>,
    pub mode_hint: MarginGateMode,
}

/// Runtime state shared across one or more `evaluate` calls.
#[derive(Debug, Default)]
pub struct ExecutionRuntime<'a> {
    pub pending_exposure_book: Option<&'a PendingExposureBook>,
    pub choke_metrics: ChokeMetrics,
    pub open_runtime_metrics: OpenRuntimeMetrics,
    pub pipeline_metrics: IntentPipelineMetrics,
}

impl<'a> ExecutionRuntime<'a> {
    pub fn new(pending_exposure_book: Option<&'a PendingExposureBook>) -> Self {
        Self {
            pending_exposure_book,
            choke_metrics: ChokeMetrics::new(),
            open_runtime_metrics: OpenRuntimeMetrics::default(),
            pipeline_metrics: IntentPipelineMetrics::new(),
        }
    }
}

/// Execution engine: delegates to legacy orchestration paths while exposing
/// one public entrypoint.
pub struct ExecutionEngine;

impl ExecutionEngine {
    pub fn new() -> Self {
        Self
    }

    pub fn decide<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        match input {
            ExecutionInput::Open(open_input) => {
                let Some(pending_book) = runtime.pending_exposure_book else {
                    return missing_runtime_dependency_decision(
                        "pending_exposure_book",
                        GateStep::LiquidityGate,
                    );
                };

                runtime.choke_metrics = ChokeMetrics::new();
                runtime.open_runtime_metrics = OpenRuntimeMetrics::default();
                let output = build_open_order_intent_runtime(
                    &open_input.input,
                    pending_book,
                    &mut runtime.choke_metrics,
                    &mut runtime.open_runtime_metrics,
                );
                open_runtime_to_decision(&output, &open_input.gate_reject_codes)
            }
            ExecutionInput::Close(close_input) => {
                self.evaluate_pipeline_variant(&close_input.input, ChokeIntentClass::Close, runtime)
            }
            ExecutionInput::Hedge(hedge_input) => {
                self.evaluate_pipeline_variant(&hedge_input.input, ChokeIntentClass::Hedge, runtime)
            }
            ExecutionInput::CancelOnly(cancel_only_input) => self.evaluate_pipeline_variant(
                &cancel_only_input.input,
                ChokeIntentClass::CancelOnly,
                runtime,
            ),
        }
    }

    /// Compatibility alias kept during Upgrade 1B transition.
    pub fn evaluate<'input, 'runtime>(
        &self,
        input: &ExecutionInput<'input>,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        self.decide(input, runtime)
    }

    fn evaluate_pipeline_variant<'input, 'runtime>(
        &self,
        input: &IntentPipelineInput<'input>,
        intent_class: ChokeIntentClass,
        runtime: &mut ExecutionRuntime<'runtime>,
    ) -> ExecutionDecision {
        runtime.pipeline_metrics = IntentPipelineMetrics::new();
        let result = if input.intent_class == intent_class {
            evaluate_intent_pipeline(input, &mut runtime.pipeline_metrics)
        } else {
            let mut normalized = input.clone();
            normalized.intent_class = intent_class;
            evaluate_intent_pipeline(&normalized, &mut runtime.pipeline_metrics)
        };
        pipeline_result_to_decision(
            result.decision,
            result.reject_reason_code,
            &GateRejectCodes::default(),
        )
    }
}

impl Default for ExecutionEngine {
    fn default() -> Self {
        Self::new()
    }
}

// ─── Public Conversion Helpers ──────────────────────────────────────────

pub fn pipeline_result_to_decision(
    result: ChokeResult,
    reject_code: Option<RejectReasonCode>,
    gate_reject_codes: &GateRejectCodes,
) -> ExecutionDecision {
    match result {
        ChokeApproved { gate_trace } => ExecutionDecision::Approved {
            gate_trace,
            open_metadata: None,
        },
        ChokeRejected { reason, .. } => {
            let (step, detail) = extract_step_and_detail(&reason);
            let code = reject_code
                .unwrap_or_else(|| reject_reason_from_chokepoint(&reason, gate_reject_codes));
            ExecutionDecision::Rejected { code, step, detail }
        }
    }
}

pub fn open_runtime_to_decision(
    output: &OpenRuntimeOutput,
    gate_reject_codes: &GateRejectCodes,
) -> ExecutionDecision {
    match &output.choke_result {
        ChokeApproved { gate_trace } => ExecutionDecision::Approved {
            gate_trace: gate_trace.clone(),
            open_metadata: Some(OpenMetadata {
                pending_reservation_id: output.pending_reservation_id.clone(),
                effective_risk_state: output.effective_risk_state,
                adjusted_min_edge_usd: output.adjusted_min_edge_usd,
                mode_hint: output.mode_hint,
            }),
        },
        ChokeRejected { reason, .. } => {
            let (step, detail) = extract_step_and_detail(reason);
            let code = map_open_runtime_reject_code(reason, gate_reject_codes);
            ExecutionDecision::Rejected { code, step, detail }
        }
    }
}

// ─── Internal Helpers ───────────────────────────────────────────────────

fn map_open_runtime_reject_code(
    reason: &ChokeRejectReason,
    gate_reject_codes: &GateRejectCodes,
) -> RejectReasonCode {
    if let ChokeRejectReason::GateRejected {
        gate: GateStep::LiquidityGate,
        reason: detail,
    } = reason
    {
        return match detail.as_str() {
            REJECT_REASON_PENDING_EXPOSURE_OVERFILL
            | REJECT_REASON_PENDING_EXPOSURE_INSTRUMENT_NOT_REGISTERED => {
                RejectReasonCode::PendingExposureBudgetExceeded
            }
            REJECT_REASON_GLOBAL_EXPOSURE_BUDGET_REJECT => {
                RejectReasonCode::GlobalExposureBudgetExceeded
            }
            _ => reject_reason_from_chokepoint(reason, gate_reject_codes),
        };
    }

    reject_reason_from_chokepoint(reason, gate_reject_codes)
}

fn missing_runtime_dependency_decision(
    dependency: &'static str,
    step: GateStep,
) -> ExecutionDecision {
    ExecutionDecision::Rejected {
        code: RejectReasonCode::AssemblyFailed,
        step,
        detail: format!("missing runtime dependency: {dependency}"),
    }
}

fn extract_step_and_detail(reason: &ChokeRejectReason) -> (GateStep, String) {
    match reason {
        ChokeRejectReason::RiskStateNotHealthy => {
            (GateStep::DispatchAuth, "RiskState not Healthy".to_string())
        }
        ChokeRejectReason::GateRejected { gate, reason } => (*gate, reason.clone()),
        ChokeRejectReason::AssemblyFailed => {
            (GateStep::DispatchAuth, "Assembly failed".to_string())
        }
    }
}

#[cfg(test)]
#[path = "engine_parity_tests.rs"]
mod engine_parity_tests;
