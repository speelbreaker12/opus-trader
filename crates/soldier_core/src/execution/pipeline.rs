//! Intent pipeline wiring for the execution chokepoint.
//!
//! This module provides a production-path orchestration function that calls
//! preflight, quantization, fee staleness, liquidity, net-edge, pricer, and
//! finally the chokepoint gate-order evaluator.

use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState, evaluate_fee_staleness};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, LifecycleIntent, VenueCapabilities, evaluate_capabilities,
    evaluate_expiry_guard,
};

use super::gate_outcome::GateOutcome;
#[allow(deprecated)] // TODO: migrate to build_order_intent_with_wal_gate()
use super::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateRejectCodes, GateStep, LiquidityGateInput,
    LiquidityGateMetrics, NetEdgeInput, NetEdgeMetrics, PreflightInput, PreflightMetrics,
    PricerInput, PricerMetrics, QuantizeConstraints, QuantizeMetrics, RejectReasonCode, Side,
    build_gate_results, build_order_intent_with_reject_reason_code, compute_limit_price,
    evaluate_liquidity_gate, evaluate_net_edge, preflight_intent, quantize,
};

/// Quantize inputs required by the execution pipeline.
#[derive(Debug, Clone)]
pub struct QuantizePipelineInput {
    pub raw_qty: f64,
    pub raw_limit_price: f64,
    pub side: Side,
    pub constraints: QuantizeConstraints,
}

/// Inputs required to run the end-to-end execution pipeline.
#[derive(Debug, Clone)]
pub struct IntentPipelineInput<'a> {
    pub intent_class: ChokeIntentClass,
    pub risk_state: RiskState,
    pub preflight: PreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizePipelineInput,
    pub dispatch_consistency_passed: bool,
    pub fee_snapshot: FeeCacheSnapshot,
    pub fee_config: FeeStalenessConfig,
    pub expiry_guard: Option<ExpiryGuardInput>,
    pub liquidity: Option<LiquidityGateInput>,
    pub net_edge: Option<NetEdgeInput>,
    pub pricer: Option<PricerInput>,
    pub wal_recorded: bool,
    pub requested_qty: Option<f64>,
    pub max_dispatch_qty: Option<f64>,
}

/// Aggregated metrics for the execution pipeline.
#[derive(Debug, Default)]
pub struct IntentPipelineMetrics {
    pub preflight: PreflightMetrics,
    pub quantize: QuantizeMetrics,
    pub fee: crate::risk::FeeMetrics,
    pub liquidity: LiquidityGateMetrics,
    pub net_edge: NetEdgeMetrics,
    pub pricer: PricerMetrics,
    pub chokepoint: ChokeMetrics,
}

impl IntentPipelineMetrics {
    pub fn new() -> Self {
        Self::default()
    }
}

/// Pipeline decision wrapper.
///
/// The chokepoint module remains the only source of functions that return
/// `ChokeResult` directly.
#[derive(Debug, Clone, PartialEq)]
pub struct PipelineResult {
    pub decision: ChokeResult,
    pub reject_reason_code: Option<RejectReasonCode>,
}

/// Evaluate the execution pipeline and return the chokepoint decision.
///
/// The function remains fail-closed: any missing OPEN-path input marks that
/// gate as failed before chokepoint evaluation.
pub fn evaluate_intent_pipeline(
    input: &IntentPipelineInput<'_>,
    metrics: &mut IntentPipelineMetrics,
) -> PipelineResult {
    let evaluated_caps = evaluate_capabilities(&input.venue_capabilities, &input.bot_feature_flags);
    let mut preflight_input = input.preflight.clone();
    preflight_input.linked_orders_allowed = evaluated_caps.linked_orders_allowed;

    // Mirror chokepoint early-exit behavior so downstream gate metrics are not
    // emitted for intents that never reach those gates.
    let dispatch_auth_short_circuit = input.intent_class == ChokeIntentClass::CancelOnly
        || (input.intent_class == ChokeIntentClass::Open && input.risk_state != RiskState::Healthy);

    let mut preflight_passed = true;
    let mut preflight_reject_code = None;
    let mut quantize_passed = true;
    let mut quantize_reject_code = None;
    let mut fee_cache_passed = true;
    let mut fee_cache_reject_code = None;
    let mut expiry_guard_passed = true;
    let mut expiry_guard_reject_code = None;

    if !dispatch_auth_short_circuit {
        let preflight_result = preflight_intent(&preflight_input, &mut metrics.preflight);
        let preflight_outcome = GateOutcome::from_preflight(GateStep::Preflight, &preflight_result);
        (preflight_passed, preflight_reject_code) = preflight_outcome.to_legacy();

        if preflight_passed {
            let quantize_result = quantize(
                input.quantize.raw_qty,
                input.quantize.raw_limit_price,
                input.quantize.side,
                &input.quantize.constraints,
                &mut metrics.quantize,
            );
            let quantize_outcome = GateOutcome::from_quantize(GateStep::Quantize, &quantize_result);
            (quantize_passed, quantize_reject_code) = quantize_outcome.to_legacy();
        }

        if preflight_passed && quantize_passed && input.dispatch_consistency_passed {
            let fee_eval = evaluate_fee_staleness(&input.fee_snapshot, &input.fee_config);
            let fee_outcome = GateOutcome::from_fee_eval(GateStep::FeeCacheCheck, &fee_eval);
            (fee_cache_passed, fee_cache_reject_code) = fee_outcome.to_legacy();
            if !fee_cache_passed {
                metrics.fee.record_refresh_fail();
            }
        }

        // Expiry guard: evaluate after fee cache check.
        // Derive LifecycleIntent from intent_class to prevent drift between
        // the pipeline's intent classification and the guard's input.
        if preflight_passed
            && quantize_passed
            && input.dispatch_consistency_passed
            && fee_cache_passed
        {
            let lifecycle_intent = match input.intent_class {
                ChokeIntentClass::Open => LifecycleIntent::Open,
                ChokeIntentClass::Close => LifecycleIntent::Close,
                ChokeIntentClass::Hedge => LifecycleIntent::Hedge,
                // CancelOnly is short-circuited by dispatch_auth above;
                // mapped here for exhaustiveness.
                ChokeIntentClass::CancelOnly => LifecycleIntent::Cancel,
            };

            if let Some(ref expiry_input) = input.expiry_guard {
                // Override the caller-provided intent with the authoritative one
                let corrected_input = ExpiryGuardInput {
                    intent: lifecycle_intent,
                    ..*expiry_input
                };
                let expiry_result = evaluate_expiry_guard(&corrected_input);
                let expiry_outcome =
                    GateOutcome::from_expiry_guard(GateStep::ExpiryGuard, &expiry_result);
                (expiry_guard_passed, expiry_guard_reject_code) = expiry_outcome.to_legacy();
            } else if lifecycle_intent == LifecycleIntent::Open {
                // FAIL-CLOSED: missing expiry data blocks OPEN intents
                expiry_guard_passed = false;
                expiry_guard_reject_code = Some(RejectReasonCode::InstrumentExpiredOrDelisted);
            }
        }
    }

    let mut liquidity_gate_passed = true;
    let mut net_edge_passed = true;
    let mut pricer_passed = true;
    let mut liquidity_gate_reject_code = None;
    let mut net_edge_reject_code = None;
    let mut pricer_reject_code = None;

    let open_path_active = input.intent_class == ChokeIntentClass::Open
        && input.risk_state == RiskState::Healthy
        && preflight_passed
        && quantize_passed
        && input.dispatch_consistency_passed
        && fee_cache_passed
        && expiry_guard_passed;

    if open_path_active {
        liquidity_gate_passed = match input.liquidity.as_ref() {
            Some(liquidity_input) => {
                let liquidity_result =
                    evaluate_liquidity_gate(liquidity_input, &mut metrics.liquidity);
                let liquidity_outcome =
                    GateOutcome::from_liquidity(GateStep::LiquidityGate, &liquidity_result);
                let (passed, code) = liquidity_outcome.to_legacy();
                liquidity_gate_reject_code = code;
                passed
            }
            None => {
                liquidity_gate_reject_code = Some(RejectReasonCode::LiquidityGateNoL2);
                false
            }
        };

        if liquidity_gate_passed {
            net_edge_passed = match input.net_edge.as_ref() {
                Some(net_edge_input) => {
                    let net_edge_result = evaluate_net_edge(net_edge_input, &mut metrics.net_edge);
                    let net_edge_outcome =
                        GateOutcome::from_net_edge(GateStep::NetEdgeGate, &net_edge_result);
                    let (passed, code) = net_edge_outcome.to_legacy();
                    net_edge_reject_code = code;
                    passed
                }
                None => {
                    net_edge_reject_code = Some(RejectReasonCode::NetEdgeInputMissing);
                    false
                }
            };
        } else {
            net_edge_passed = false;
            net_edge_reject_code = Some(RejectReasonCode::NetEdgeInputMissing);
        }

        if net_edge_passed {
            pricer_passed = match input.pricer.as_ref() {
                Some(pricer_input) => {
                    let pricer_result = compute_limit_price(pricer_input, &mut metrics.pricer);
                    let pricer_outcome = GateOutcome::from_pricer(GateStep::Pricer, &pricer_result);
                    let (passed, code) = pricer_outcome.to_legacy();
                    pricer_reject_code = code;
                    passed
                }
                None => {
                    pricer_reject_code = Some(RejectReasonCode::NetEdgeInputMissing);
                    false
                }
            };
        } else {
            pricer_passed = false;
            pricer_reject_code = Some(RejectReasonCode::NetEdgeInputMissing);
        }
    }

    let gate_results = build_gate_results(
        preflight_passed,
        quantize_passed,
        input.dispatch_consistency_passed,
        fee_cache_passed,
        expiry_guard_passed,
        liquidity_gate_passed,
        net_edge_passed,
        pricer_passed,
        input.wal_recorded,
        input.requested_qty,
        input.max_dispatch_qty,
    );

    let gate_reject_codes = GateRejectCodes {
        preflight: preflight_reject_code,
        quantize: quantize_reject_code,
        fee_cache: fee_cache_reject_code,
        expiry_guard: expiry_guard_reject_code,
        liquidity_gate: liquidity_gate_reject_code,
        net_edge_gate: net_edge_reject_code,
        recorded_before_dispatch: if input.wal_recorded {
            None
        } else {
            Some(RejectReasonCode::RecordedBeforeDispatchFailed)
        },
        pricer: pricer_reject_code,
    };

    // TODO(Phase 2): migrate to build_order_intent_with_wal_gate() to prevent WAL bypass.
    // TODO(Phase 2): migrate open_runtime.rs GateResults construction to use GateOutcome converters.
    #[allow(deprecated)]
    let (decision, reject_reason_code) = build_order_intent_with_reject_reason_code(
        input.intent_class,
        input.risk_state,
        &mut metrics.chokepoint,
        &gate_results,
        &gate_reject_codes,
    );

    PipelineResult {
        decision,
        reject_reason_code,
    }
}
