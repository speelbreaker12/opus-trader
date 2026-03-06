//! Intent pipeline wiring for the execution chokepoint.
//!
//! This module provides a production-path orchestration function that calls
//! the shared base gate evaluator (gates 1-6) then OPEN-specific gates (7-10),
//! and finally the chokepoint gate-order evaluator.

use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use crate::venue::{BotFeatureFlags, ExpiryGuardInput, VenueCapabilities};

use super::base_gates::{BaseGatesInput, BaseGatesLegacy, BaseGatesMetrics, evaluate_base_gates};
#[allow(deprecated)] // PrecomputedWalGate is a migration shim (GAP-FE-004)
use super::build_order_intent::PrecomputedWalGate;
use super::build_order_intent::build_gate_results_from_dispatch_proof;
use super::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateStep, build_order_intent_with_wal_gate,
};
use super::dispatch_map::DispatchConsistencyProof;
use super::gate::{LiquidityGateInput, LiquidityGateMetrics, evaluate_liquidity_gate};
use super::gate_outcome::GateOutcome;
use super::gates::{NetEdgeInput, NetEdgeMetrics, evaluate_net_edge};
use super::preflight::{PreflightInput, PreflightMetrics};
use super::pricer::{PricerInput, PricerMetrics, compute_limit_price};
use super::quantize::{QuantizeConstraints, QuantizeMetrics, Side};
use super::reject_reason::{GateRejectCodes, RejectReasonCode, reject_reason_from_chokepoint};

/// Quantize inputs required by the execution pipeline.
#[derive(Debug, Clone)]
pub(crate) struct QuantizePipelineInput {
    pub raw_qty: f64,
    pub raw_limit_price: f64,
    pub side: Side,
    pub constraints: QuantizeConstraints,
}

/// Inputs required to run the end-to-end execution pipeline.
#[derive(Debug, Clone)]
pub(crate) struct IntentPipelineInput<'a> {
    pub intent_class: ChokeIntentClass,
    pub risk_state: RiskState,
    pub preflight: PreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizePipelineInput,
    pub dispatch_consistency: DispatchConsistencyProof,
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
pub(crate) struct PipelineResult {
    pub decision: ChokeResult,
    pub reject_reason_code: Option<RejectReasonCode>,
}

/// Evaluate the execution pipeline and return the chokepoint decision.
///
/// The function remains fail-closed: any missing OPEN-path input marks that
/// gate as failed before chokepoint evaluation.
///
/// Gates 1-6 are evaluated via the shared `evaluate_base_gates()` to
/// eliminate dual-orchestration drift risk with `open_runtime.rs`.
pub(crate) fn evaluate_intent_pipeline(
    input: &IntentPipelineInput<'_>,
    metrics: &mut IntentPipelineMetrics,
) -> PipelineResult {
    // ── Gates 1-6: shared base gate evaluator ───────────────────────────
    let base_input = BaseGatesInput {
        intent_class: input.intent_class,
        risk_state: input.risk_state,
        preflight: input.preflight.clone(),
        venue_capabilities: input.venue_capabilities.clone(),
        bot_feature_flags: input.bot_feature_flags.clone(),
        quantize: input.quantize.clone(),
        dispatch_consistency: input.dispatch_consistency,
        fee_snapshot: input.fee_snapshot.clone(),
        fee_config: input.fee_config.clone(),
        expiry_guard: input.expiry_guard,
    };

    let mut base_metrics = BaseGatesMetrics::new();
    let base_result = evaluate_base_gates(&base_input, &mut base_metrics);

    // Transfer metrics from base gates to pipeline metrics.
    // This is an intentional overwrite, not a merge: IntentPipelineMetrics is created
    // fresh per call (single-use). Callers must not reuse a metrics instance across
    // evaluations — each call to evaluate_intent_pipeline() expects a clean metrics struct.
    metrics.preflight = base_metrics.preflight;
    metrics.quantize = base_metrics.quantize;
    metrics.fee = base_metrics.fee;

    // Extract legacy gate bools and reject codes
    let (
        preflight_passed,
        quantize_passed,
        dispatch_consistency_passed,
        fee_cache_passed,
        expiry_guard_passed,
        preflight_reject_code,
        quantize_reject_code,
        fee_cache_reject_code,
        expiry_guard_reject_code,
    ) = match &base_result {
        Ok(proof) => {
            let legacy = BaseGatesLegacy::from(proof);
            (
                legacy.preflight_passed,
                legacy.quantize_passed,
                legacy.dispatch_consistency_passed,
                legacy.fee_cache_passed,
                legacy.expiry_guard_passed,
                legacy.preflight_reject_code,
                legacy.quantize_reject_code,
                legacy.fee_cache_reject_code,
                legacy.expiry_guard_reject_code,
            )
        }
        Err(rejection) => {
            let legacy = BaseGatesLegacy::from(rejection);
            (
                legacy.preflight_passed,
                legacy.quantize_passed,
                legacy.dispatch_consistency_passed,
                legacy.fee_cache_passed,
                legacy.expiry_guard_passed,
                legacy.preflight_reject_code,
                legacy.quantize_reject_code,
                legacy.fee_cache_reject_code,
                legacy.expiry_guard_reject_code,
            )
        }
    };

    // ── Gates 7-9: OPEN-specific gates ──────────────────────────────────
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
        && dispatch_consistency_passed
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
            // Cascade: liquidity failed, so net_edge is skipped (not a genuine missing input).
            net_edge_passed = false;
            net_edge_reject_code = Some(RejectReasonCode::GateCascadeSkip);
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
                    pricer_reject_code = Some(RejectReasonCode::PricerInputMissing);
                    false
                }
            };
        } else {
            // Cascade: net_edge failed (or was skipped), so pricer is skipped.
            pricer_passed = false;
            pricer_reject_code = Some(RejectReasonCode::GateCascadeSkip);
        }
    }

    // ── Build chokepoint input ──────────────────────────────────────────
    let gate_results = build_gate_results_from_dispatch_proof(
        input.intent_class,
        preflight_passed,
        quantize_passed,
        input.dispatch_consistency,
        fee_cache_passed,
        expiry_guard_passed,
        liquidity_gate_passed,
        net_edge_passed,
        pricer_passed,
        input.wal_recorded, // Note: dead in the WAL adapter path (PrecomputedWalGate is the authority); kept for GateRejectCodes sidecar
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

    // TODO(Phase 2): migrate open_runtime.rs GateResults construction to use GateOutcome converters.
    #[allow(deprecated)] // PrecomputedWalGate is a migration shim (GAP-FE-004)
    let mut wal_gate = PrecomputedWalGate {
        recorded: input.wal_recorded,
    };
    let decision = build_order_intent_with_wal_gate(
        input.intent_class,
        input.risk_state,
        &mut metrics.chokepoint,
        &gate_results,
        &mut wal_gate,
    );
    let reject_reason_code = if let ChokeResult::Rejected { reason, .. } = &decision {
        Some(reject_reason_from_chokepoint(reason, &gate_reject_codes))
    } else {
        None
    };

    PipelineResult {
        decision,
        reject_reason_code,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::execution::preflight::OrderType;
    use crate::execution::quantize::Side;
    use crate::venue::{InstrumentKind, LifecycleIntent};

    fn base_open_input() -> IntentPipelineInput<'static> {
        IntentPipelineInput {
            intent_class: ChokeIntentClass::Open,
            risk_state: RiskState::Healthy,
            preflight: PreflightInput {
                instrument_kind: InstrumentKind::Option,
                order_type: OrderType::Limit,
                has_trigger: false,
                linked_order_type: None,
                linked_orders_allowed: false,
                post_only_input: None,
            },
            venue_capabilities: VenueCapabilities::default(),
            bot_feature_flags: BotFeatureFlags::default(),
            quantize: QuantizePipelineInput {
                raw_qty: 1.0,
                raw_limit_price: 100.0,
                side: Side::Buy,
                constraints: QuantizeConstraints {
                    tick_size: 0.1,
                    amount_step: 0.1,
                    min_amount: 0.1,
                },
            },
            dispatch_consistency: DispatchConsistencyProof::no_contracts(),
            fee_snapshot: FeeCacheSnapshot {
                fee_rate: 0.0005,
                fee_model_cached_at_ts_ms: Some(1_000_000),
                now_ms: 1_010_000,
            },
            fee_config: FeeStalenessConfig::default(),
            expiry_guard: Some(ExpiryGuardInput {
                now_ms: 1_000_000,
                expiration_timestamp_ms: Some(2_000_000),
                expiry_delist_buffer_s: 60,
                intent: LifecycleIntent::Open,
                instrument_kind: Some(InstrumentKind::LinearFuture),
            }),
            liquidity: Some(LiquidityGateInput {
                order_qty: 1.0,
                is_buy: true,
                intent_class: crate::execution::gate::GateIntentClass::Open,
                is_marketable: true,
                l2_snapshot: Some(crate::execution::gate::L2BookSnapshot {
                    asks: vec![crate::execution::gate::L2Level {
                        price: 100.0,
                        qty: 10.0,
                    }],
                    bids: vec![],
                    timestamp_ms: 1_009_000,
                }),
                now_ms: 1_010_000,
                l2_book_snapshot_max_age_ms: 5_000,
                max_slippage_bps: 10.0,
            }),
            net_edge: Some(NetEdgeInput {
                gross_edge_usd: Some(10.0),
                fee_usd: Some(2.0),
                expected_slippage_usd: Some(1.0),
                min_edge_usd: Some(2.0),
            }),
            pricer: Some(PricerInput {
                fair_price: 100.0,
                gross_edge_usd: 10.0,
                min_edge_usd: 2.0,
                fee_estimate_usd: 2.0,
                qty: 1.0,
                side: Side::Buy,
            }),
            wal_recorded: true,
            requested_qty: Some(1.0),
            max_dispatch_qty: Some(1.0),
        }
    }

    #[test]
    fn test_none_liquidity_input_fails() {
        let mut input = base_open_input();
        input.liquidity = None;
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);
        assert_eq!(
            result.reject_reason_code,
            Some(RejectReasonCode::LiquidityGateNoL2)
        );
    }

    #[test]
    fn test_none_net_edge_input_fails() {
        let mut input = base_open_input();
        input.net_edge = None;
        let mut metrics = IntentPipelineMetrics::new();

        let result = evaluate_intent_pipeline(&input, &mut metrics);
        assert_eq!(
            result.reject_reason_code,
            Some(RejectReasonCode::NetEdgeInputMissing)
        );
    }
}

#[cfg(test)]
#[path = "pipeline_integration_tests.rs"]
mod pipeline_integration_tests;

#[cfg(test)]
#[path = "pipeline_intent_determinism_tests.rs"]
mod pipeline_intent_determinism_tests;

#[cfg(test)]
#[path = "pipeline_intent_id_propagation_tests.rs"]
mod pipeline_intent_id_propagation_tests;

#[cfg(test)]
#[path = "pipeline_missing_config_tests.rs"]
mod pipeline_missing_config_tests;

#[cfg(test)]
#[path = "pipeline_prop_gi001_tests.rs"]
mod pipeline_prop_gi001_tests;

#[cfg(test)]
#[path = "pipeline_rejection_side_effects_tests.rs"]
mod pipeline_rejection_side_effects_tests;
