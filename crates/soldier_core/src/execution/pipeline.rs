//! Intent pipeline wiring for the execution chokepoint.
//!
//! This module provides a production-path orchestration function that calls
//! preflight, quantization, fee staleness, liquidity, net-edge, pricer, and
//! finally the chokepoint gate-order evaluator.

use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState, evaluate_fee_staleness};
use crate::venue::{BotFeatureFlags, VenueCapabilities, evaluate_capabilities};

use super::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, LiquidityGateInput, LiquidityGateMetrics,
    LiquidityGateResult, NetEdgeInput, NetEdgeMetrics, NetEdgeResult, PreflightInput,
    PreflightMetrics, PreflightResult, PricerInput, PricerMetrics, PricerResult,
    QuantizeConstraints, QuantizeMetrics, Side, build_gate_results, build_order_intent,
    compute_limit_price, evaluate_liquidity_gate, evaluate_net_edge, preflight_intent, quantize,
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
    let mut quantize_passed = true;
    let mut fee_cache_passed = true;

    if !dispatch_auth_short_circuit {
        preflight_passed = matches!(
            preflight_intent(&preflight_input, &mut metrics.preflight),
            PreflightResult::Allowed
        );

        if preflight_passed {
            quantize_passed = quantize(
                input.quantize.raw_qty,
                input.quantize.raw_limit_price,
                input.quantize.side,
                &input.quantize.constraints,
                &mut metrics.quantize,
            )
            .is_ok();
        }

        if preflight_passed && quantize_passed && input.dispatch_consistency_passed {
            let fee_eval = evaluate_fee_staleness(&input.fee_snapshot, &input.fee_config);
            fee_cache_passed = fee_eval.risk_state == RiskState::Healthy;
            if !fee_cache_passed {
                metrics.fee.record_refresh_fail();
            }
        }
    }

    let mut liquidity_gate_passed = true;
    let mut net_edge_passed = true;
    let mut pricer_passed = true;

    let open_path_active = input.intent_class == ChokeIntentClass::Open
        && input.risk_state == RiskState::Healthy
        && preflight_passed
        && quantize_passed
        && input.dispatch_consistency_passed
        && fee_cache_passed;

    if open_path_active {
        liquidity_gate_passed = match input.liquidity.as_ref() {
            Some(liquidity_input) => matches!(
                evaluate_liquidity_gate(liquidity_input, &mut metrics.liquidity),
                LiquidityGateResult::Allowed { .. }
            ),
            None => false,
        };

        if liquidity_gate_passed {
            net_edge_passed = match input.net_edge.as_ref() {
                Some(net_edge_input) => matches!(
                    evaluate_net_edge(net_edge_input, &mut metrics.net_edge),
                    NetEdgeResult::Allowed { .. }
                ),
                None => false,
            };
        } else {
            net_edge_passed = false;
        }

        if net_edge_passed {
            pricer_passed = match input.pricer.as_ref() {
                Some(pricer_input) => matches!(
                    compute_limit_price(pricer_input, &mut metrics.pricer),
                    PricerResult::LimitPrice { .. }
                ),
                None => false,
            };
        } else {
            pricer_passed = false;
        }
    }

    let gate_results = build_gate_results(
        preflight_passed,
        quantize_passed,
        input.dispatch_consistency_passed,
        fee_cache_passed,
        liquidity_gate_passed,
        net_edge_passed,
        pricer_passed,
        input.wal_recorded,
        input.requested_qty,
        input.max_dispatch_qty,
    );

    PipelineResult {
        decision: build_order_intent(
            input.intent_class,
            input.risk_state,
            &mut metrics.chokepoint,
            &gate_results,
        ),
    }
}
