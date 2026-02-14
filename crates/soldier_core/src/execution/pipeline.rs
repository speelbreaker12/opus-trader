//! Intent pipeline wiring for the execution chokepoint.
//!
//! This module provides a production-path orchestration function that calls
//! preflight, quantization, fee staleness, liquidity, net-edge, pricer, and
//! finally the chokepoint gate-order evaluator.

use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState, evaluate_fee_staleness};
use crate::venue::{BotFeatureFlags, VenueCapabilities, evaluate_capabilities};

use super::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateRejectCodes, LiquidityGateInput,
    LiquidityGateMetrics, LiquidityGateRejectReason, LiquidityGateResult, NetEdgeInput,
    NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, PreflightInput, PreflightMetrics,
    PreflightReject, PreflightResult, PricerInput, PricerMetrics, PricerRejectReason, PricerResult,
    QuantizeConstraints, QuantizeError, QuantizeMetrics, RejectReasonCode, Side,
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

    if !dispatch_auth_short_circuit {
        let preflight_result = preflight_intent(&preflight_input, &mut metrics.preflight);
        (preflight_passed, preflight_reject_code) = match preflight_result {
            PreflightResult::Allowed => (true, None),
            PreflightResult::Rejected(reason) => (
                false,
                Some(match reason {
                    PreflightReject::OrderTypeMarketForbidden => {
                        RejectReasonCode::OrderTypeMarketForbidden
                    }
                    PreflightReject::OrderTypeStopForbidden => {
                        RejectReasonCode::OrderTypeStopForbidden
                    }
                    PreflightReject::LinkedOrderTypeForbidden => {
                        RejectReasonCode::LinkedOrderTypeForbidden
                    }
                    PreflightReject::PostOnlyWouldCross => RejectReasonCode::PostOnlyWouldCross,
                }),
            ),
        };

        if preflight_passed {
            let quantize_result = quantize(
                input.quantize.raw_qty,
                input.quantize.raw_limit_price,
                input.quantize.side,
                &input.quantize.constraints,
                &mut metrics.quantize,
            );
            (quantize_passed, quantize_reject_code) = match quantize_result {
                Ok(_) => (true, None),
                Err(reason) => (
                    false,
                    Some(match reason {
                        QuantizeError::TooSmallAfterQuantization { .. } => {
                            RejectReasonCode::TooSmallAfterQuantization
                        }
                        QuantizeError::InstrumentMetadataMissing { .. }
                        | QuantizeError::InvalidInput { .. } => {
                            RejectReasonCode::InstrumentMetadataMissing
                        }
                    }),
                ),
            };
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
    let mut liquidity_gate_reject_code = None;
    let mut net_edge_reject_code = None;
    let mut pricer_reject_code = None;

    let open_path_active = input.intent_class == ChokeIntentClass::Open
        && input.risk_state == RiskState::Healthy
        && preflight_passed
        && quantize_passed
        && input.dispatch_consistency_passed
        && fee_cache_passed;

    if open_path_active {
        liquidity_gate_passed = match input.liquidity.as_ref() {
            Some(liquidity_input) => {
                let liquidity_result =
                    evaluate_liquidity_gate(liquidity_input, &mut metrics.liquidity);
                match liquidity_result {
                    LiquidityGateResult::Allowed { .. } => true,
                    LiquidityGateResult::Rejected { reason, .. } => {
                        liquidity_gate_reject_code = Some(match reason {
                            LiquidityGateRejectReason::LiquidityGateNoL2 => {
                                RejectReasonCode::LiquidityGateNoL2
                            }
                            LiquidityGateRejectReason::InsufficientDepthWithinBudget
                            | LiquidityGateRejectReason::ExpectedSlippageTooHigh => {
                                RejectReasonCode::ExpectedSlippageTooHigh
                            }
                            LiquidityGateRejectReason::InsufficientDepthWithinBudget => {
                                RejectReasonCode::InsufficientDepthWithinBudget
                            }
                        });
                        false
                    }
                }
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
                    match net_edge_result {
                        NetEdgeResult::Allowed { .. } => true,
                        NetEdgeResult::Rejected { reason, .. } => {
                            net_edge_reject_code = Some(match reason {
                                NetEdgeRejectReason::NetEdgeTooLow => {
                                    RejectReasonCode::NetEdgeTooLow
                                }
                                NetEdgeRejectReason::NetEdgeInputMissing => {
                                    RejectReasonCode::NetEdgeInputMissing
                                }
                            });
                            false
                        }
                    }
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
                    match pricer_result {
                        PricerResult::LimitPrice { .. } => true,
                        PricerResult::Rejected { reason, .. } => {
                            pricer_reject_code = Some(match reason {
                                PricerRejectReason::NetEdgeTooLow => {
                                    RejectReasonCode::NetEdgeTooLow
                                }
                                PricerRejectReason::InvalidInput => {
                                    RejectReasonCode::NetEdgeInputMissing
                                }
                            });
                            false
                        }
                    }
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
        liquidity_gate: liquidity_gate_reject_code,
        net_edge_gate: net_edge_reject_code,
        pricer: pricer_reject_code,
    };

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
