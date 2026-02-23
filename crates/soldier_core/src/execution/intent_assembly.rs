//! Intent assembly: sizing derivation + dispatch mapping before gate evaluation.
//!
//! Wires `derive_instrument_kind`, `build_order_size`, and `validate_and_dispatch`
//! into a single production-path function that feeds `evaluate_intent_pipeline`.

use super::dispatch_map::{
    DispatchConsistencyProof, IntentClass, MismatchMetrics, validate_and_dispatch,
};
use super::order_size::{OrderSize, OrderSizeInput, build_order_size};
use super::pipeline::{IntentPipelineInput, IntentPipelineMetrics, PipelineResult, evaluate_intent_pipeline};
use super::{
    ChokeIntentClass, ChokeRejectReason, ChokeResult, RejectReasonCode,
};
use crate::risk::{FeeCacheSnapshot, FeeStalenessConfig, RiskState};
use crate::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, VenueCapabilities,
    types::{InstrumentKindInput, derive_instrument_kind},
};
use super::gate::LiquidityGateInput;
use super::pricer::PricerInput;
use super::gates::NetEdgeInput;
use super::pipeline::QuantizePipelineInput;
use super::preflight::PreflightInput;

// ─── Types ──────────────────────────────────────────────────────────────

/// Error from intent assembly (sizing + dispatch mapping).
#[derive(Debug, Clone, PartialEq)]
pub enum AssemblySizingError {
    /// Venue metadata does not map to any known InstrumentKind.
    UnknownInstrumentKind,
    /// OrderSize construction failed (invalid qty, price, or multiplier).
    InvalidOrderSize(String),
}

/// Input parameters for sizing derivation.
#[derive(Debug, Clone)]
pub struct SizingParams {
    /// Canonical quantity in the instrument's native unit.
    pub canonical_qty: f64,
    /// Current index price (BTC/ETH price in USD).
    pub index_price: f64,
    /// Contract multiplier (contract_size from venue metadata).
    pub contract_multiplier: Option<f64>,
}

/// Result of successful intent assembly.
#[derive(Debug, Clone, PartialEq)]
pub struct AssembledSizing {
    /// Derived instrument kind.
    pub instrument_kind: InstrumentKind,
    /// Canonical order sizing.
    pub order_size: OrderSize,
    /// AT-920 dispatch consistency proof.
    pub dispatch_consistency: DispatchConsistencyProof,
    /// Whether assembly detected a degraded condition (mismatch).
    pub risk_state_degraded: bool,
}

/// Pipeline parameters excluding `dispatch_consistency` (derived from assembly).
///
/// Contains all `IntentPipelineInput` fields except `dispatch_consistency`,
/// which is determined by the assembly step.
#[derive(Debug, Clone)]
pub struct AssembledPipelineParams<'a> {
    pub intent_class: ChokeIntentClass,
    pub risk_state: RiskState,
    pub preflight: PreflightInput<'a>,
    pub venue_capabilities: VenueCapabilities,
    pub bot_feature_flags: BotFeatureFlags,
    pub quantize: QuantizePipelineInput,
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

// ─── Helpers ────────────────────────────────────────────────────────────

/// Map chokepoint intent class to dispatch intent class.
pub fn choke_intent_to_dispatch(c: ChokeIntentClass) -> IntentClass {
    match c {
        ChokeIntentClass::Open => IntentClass::Open,
        ChokeIntentClass::Close => IntentClass::Close,
        ChokeIntentClass::Hedge => IntentClass::Hedge,
        ChokeIntentClass::CancelOnly => IntentClass::Cancel,
    }
}

// ─── Assembly ───────────────────────────────────────────────────────────

/// Derive instrument kind, build order size, and validate dispatch consistency.
///
/// This wires `derive_instrument_kind`, `build_order_size`, and
/// `validate_and_dispatch` into a single production-path function.
///
/// On success, returns the assembled sizing with dispatch consistency result.
/// On error, returns fail-closed `AssemblySizingError`.
pub fn assemble_sizing(
    meta: &InstrumentKindInput,
    params: &SizingParams,
    intent: IntentClass,
    mismatch_metrics: &mut MismatchMetrics,
) -> Result<AssembledSizing, AssemblySizingError> {
    // Step 1: Derive instrument kind from venue metadata.
    let instrument_kind = derive_instrument_kind(meta)
        .ok_or(AssemblySizingError::UnknownInstrumentKind)?;

    // Step 2: Build canonical order sizing.
    let osi = OrderSizeInput {
        instrument_kind,
        canonical_qty: params.canonical_qty,
        index_price: params.index_price,
        contract_multiplier: params.contract_multiplier,
    };
    let order_size = build_order_size(&osi)
        .map_err(|e| AssemblySizingError::InvalidOrderSize(format!("{e:?}")))?;

    // Step 3: Validate dispatch consistency (AT-920).
    let (dispatch_consistency, risk_state_degraded) =
        match validate_and_dispatch(&order_size, instrument_kind, intent, params.contract_multiplier, mismatch_metrics) {
            Ok(ref validated) => (DispatchConsistencyProof::from_validated(validated), false),
            Err(_) => (DispatchConsistencyProof::unchecked(false), true),
        };

    Ok(AssembledSizing {
        instrument_kind,
        order_size,
        dispatch_consistency,
        risk_state_degraded,
    })
}

// ─── Pipeline integration ───────────────────────────────────────────────

/// Assemble sizing, then evaluate the full intent pipeline.
///
/// This is the production entry point that wires orphaned functions
/// (`derive_instrument_kind`, `build_order_size`, `validate_and_dispatch`)
/// into the pipeline path.
///
/// Assembly failure is fail-closed: returns `Rejected` with `AssemblyFailed`.
///
/// **CancelOnly bypass**: CancelOnly intents skip assembly entirely and go
/// straight to the pipeline, where the chokepoint short-circuits to Approved.
/// This prevents metadata/sizing failures from blocking urgent cancellations.
///
/// **Metrics note**: Assembly failures return `PipelineResult` before the
/// chokepoint is reached, so `metrics.chokepoint.rejected_total` is not
/// incremented. This is intentional: `rejected_total` tracks chokepoint-level
/// rejections, not pre-chokepoint assembly failures. Assembly failures are
/// observable via the `tracing::warn!` log and the `AssemblyFailed` reject
/// reason code in the returned `PipelineResult`.
pub fn evaluate_assembled_pipeline(
    meta: &InstrumentKindInput,
    sizing_params: &SizingParams,
    mismatch_metrics: &mut MismatchMetrics,
    remaining: AssembledPipelineParams<'_>,
    metrics: &mut IntentPipelineMetrics,
) -> PipelineResult {
    // CancelOnly intents bypass assembly: cancels must never be blocked by
    // metadata/sizing failures. The chokepoint short-circuits CancelOnly to
    // Approved after Gate 1 (DispatchAuth).
    if remaining.intent_class == ChokeIntentClass::CancelOnly {
        let pipeline_input = IntentPipelineInput {
            intent_class: remaining.intent_class,
            risk_state: remaining.risk_state,
            preflight: remaining.preflight,
            venue_capabilities: remaining.venue_capabilities,
            bot_feature_flags: remaining.bot_feature_flags,
            quantize: remaining.quantize,
            dispatch_consistency: DispatchConsistencyProof::no_contracts(),
            fee_snapshot: remaining.fee_snapshot,
            fee_config: remaining.fee_config,
            expiry_guard: remaining.expiry_guard,
            liquidity: remaining.liquidity,
            net_edge: remaining.net_edge,
            pricer: remaining.pricer,
            wal_recorded: remaining.wal_recorded,
            requested_qty: remaining.requested_qty,
            max_dispatch_qty: remaining.max_dispatch_qty,
        };
        return evaluate_intent_pipeline(&pipeline_input, metrics);
    }

    // Step 1: Convert intent class for dispatch mapping.
    let intent = choke_intent_to_dispatch(remaining.intent_class);

    // Step 2: Assemble sizing (derive kind + build size + validate dispatch).
    //
    // Close/Hedge bypass on assembly failure (CSP Invariant F / AT-1049):
    // Risk-reducing intents must never be blocked by metadata/sizing failures.
    // On assembly Err, Close/Hedge fall through to the pipeline with
    // no_contracts() consistency (skipping Gate 4) so the chokepoint can
    // approve them. Open intents fail-closed with AssemblyFailed.
    let assembled = match assemble_sizing(meta, sizing_params, intent, mismatch_metrics) {
        Ok(assembled) => assembled,
        Err(e) if remaining.intent_class == ChokeIntentClass::Close
              || remaining.intent_class == ChokeIntentClass::Hedge =>
        {
            tracing::warn!(
                ?e,
                intent_class = ?remaining.intent_class,
                "assembly failed for risk-reducing intent — bypassing (CSP Invariant F)"
            );
            let pipeline_input = IntentPipelineInput {
                intent_class: remaining.intent_class,
                risk_state: remaining.risk_state,
                preflight: remaining.preflight,
                venue_capabilities: remaining.venue_capabilities,
                bot_feature_flags: remaining.bot_feature_flags,
                quantize: remaining.quantize,
                dispatch_consistency: DispatchConsistencyProof::no_contracts(),
                fee_snapshot: remaining.fee_snapshot,
                fee_config: remaining.fee_config,
                expiry_guard: remaining.expiry_guard,
                liquidity: remaining.liquidity,
                net_edge: remaining.net_edge,
                pricer: remaining.pricer,
                wal_recorded: remaining.wal_recorded,
                requested_qty: remaining.requested_qty,
                max_dispatch_qty: remaining.max_dispatch_qty,
            };
            return evaluate_intent_pipeline(&pipeline_input, metrics);
        }
        Err(e) => {
            tracing::warn!(?e, "intent assembly failed — rejecting fail-closed");
            return PipelineResult {
                decision: ChokeResult::Rejected {
                    reason: ChokeRejectReason::AssemblyFailed,
                    gate_trace: vec![],
                },
                reject_reason_code: Some(RejectReasonCode::AssemblyFailed),
            };
        }
    };

    // Step 3: Determine effective risk state.
    // If assembly detected a mismatch AND caller was Healthy, override to Degraded.
    // If caller was already Kill/Maintenance/Degraded, preserve the higher severity.
    // Matches the open_runtime.rs pattern: only escalate Healthy → Degraded.
    let effective_risk_state = if assembled.risk_state_degraded
        && remaining.risk_state == RiskState::Healthy
    {
        RiskState::Degraded
    } else {
        remaining.risk_state
    };

    // Step 4: Build full pipeline input from assembly result + remaining params.
    let pipeline_input = IntentPipelineInput {
        intent_class: remaining.intent_class,
        risk_state: effective_risk_state,
        preflight: remaining.preflight,
        venue_capabilities: remaining.venue_capabilities,
        bot_feature_flags: remaining.bot_feature_flags,
        quantize: remaining.quantize,
        dispatch_consistency: assembled.dispatch_consistency,
        fee_snapshot: remaining.fee_snapshot,
        fee_config: remaining.fee_config,
        expiry_guard: remaining.expiry_guard,
        liquidity: remaining.liquidity,
        net_edge: remaining.net_edge,
        pricer: remaining.pricer,
        wal_recorded: remaining.wal_recorded,
        requested_qty: remaining.requested_qty,
        max_dispatch_qty: remaining.max_dispatch_qty,
    };

    // Step 5: Evaluate the full gate pipeline.
    evaluate_intent_pipeline(&pipeline_input, metrics)
}
