//! Tests for intent assembly (sizing + dispatch mapping integration).
//!
//! Dispatch causality: these tests prove that assembly failures
//! (unknown instrument kind, NaN qty, dispatch mismatch) result in
//! fail-closed rejection with dispatch_count=0.
//!
//! Cross-reference: unit-level sizing tests in test_order_size.rs;
//! unit-level mapping tests in test_dispatch_map.rs.

mod common;

use soldier_core::execution::{
    AssembledPipelineParams, AssemblySizingError, ChokeIntentClass, ChokeResult,
    IntentPipelineMetrics, MismatchMetrics, RejectReasonCode, SizingParams,
    assemble_sizing, choke_intent_to_dispatch, evaluate_assembled_pipeline,
};
use soldier_core::execution::dispatch_map::IntentClass;
use soldier_core::risk::RiskState;
use soldier_core::venue::InstrumentKindInput;

use common::base_open_input;

// ─── assemble_sizing unit tests ─────────────────────────────────────────

/// Fail-closed: all metadata flags false → UnknownInstrumentKind.
/// No valid InstrumentKind can be derived from empty metadata.
#[test]
fn test_assembly_unknown_kind_fails_closed() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let mut mismatch = MismatchMetrics::new();

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);
    assert_eq!(result, Err(AssemblySizingError::UnknownInstrumentKind));
}

/// Fail-closed: NaN canonical_qty → InvalidOrderSize error.
/// NaN bypasses all finite checks, so build_order_size must reject it.
#[test]
fn test_assembly_nan_qty_fails_closed() {
    let meta = InstrumentKindInput {
        is_option: true,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: f64::NAN,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let mut mismatch = MismatchMetrics::new();

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);
    assert!(
        matches!(result, Err(AssemblySizingError::InvalidOrderSize(_))),
        "NaN qty must be rejected as InvalidOrderSize, got {result:?}"
    );
}

/// Fail-closed: Inf canonical_qty → InvalidOrderSize error.
/// Inf could theoretically produce different behavior than NaN if intermediate
/// computations convert Inf to a finite value before the is_finite() check.
#[test]
fn test_assembly_inf_qty_fails_closed() {
    let meta = InstrumentKindInput {
        is_option: true,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: f64::INFINITY,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let mut mismatch = MismatchMetrics::new();

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);
    assert!(
        matches!(result, Err(AssemblySizingError::InvalidOrderSize(_))),
        "Inf qty must be rejected as InvalidOrderSize, got {result:?}"
    );
}

/// Dispatch mismatch: mismatched contracts/amount → dispatch_consistency fails,
/// risk_state_degraded=true. When fed into the pipeline, dispatch count must be 0.
#[test]
fn test_assembly_mismatch_sets_degraded() {
    // Use a perpetual with a contract_multiplier that will create a mismatch.
    // canonical_qty = 10_000 USD, contract_multiplier = 10, so contracts = 1000.
    // But the order size will have contracts = Some(1000) which SHOULD match.
    // To create a MISMATCH: use a multiplier that doesn't divide evenly and
    // creates a delta > 0.001 tolerance.
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: false,
    };
    // With contract_multiplier = 7.0: contracts = round(10000/7) = 1429
    // contracts_implied = 1429 * 7 = 10003. delta = |10003 - 10000| / 10000 = 0.0003 < 0.001
    // That's within tolerance. We need a bigger mismatch.
    // Use canonical_qty=10.0, multiplier=3.0: contracts = round(10/3) = 3
    // contracts_implied = 3 * 3 = 9. delta = |9-10|/10 = 0.1 >> 0.001
    let params = SizingParams {
        canonical_qty: 10.0,
        index_price: 50_000.0,
        contract_multiplier: Some(3.0),
    };
    let mut mismatch = MismatchMetrics::new();

    let result = assemble_sizing(&meta, &params, IntentClass::Open, &mut mismatch);
    let assembled = result.expect("sizing should succeed (mismatch is in dispatch, not sizing)");

    assert!(
        !assembled.dispatch_consistency.passed(),
        "dispatch consistency must fail on contract/amount mismatch"
    );
    assert!(
        assembled.risk_state_degraded,
        "risk_state_degraded must be true on dispatch mismatch"
    );

    // Now prove pipeline rejects: feed the mismatch into evaluate_assembled_pipeline.
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut pipeline_metrics = IntentPipelineMetrics::new();
    let mut mismatch2 = MismatchMetrics::new();

    let pipeline_result = evaluate_assembled_pipeline(
        &meta,
        &params,
        &mut mismatch2,
        remaining,
        &mut pipeline_metrics,
    );

    // Mismatch → risk_state_degraded → effective Degraded → OPEN blocked at DispatchAuth.
    assert!(
        matches!(pipeline_result.decision, ChokeResult::Rejected { .. }),
        "OPEN must be rejected when assembly detects dispatch mismatch"
    );
    assert_eq!(
        pipeline_metrics.chokepoint.approved_total(),
        0,
        "dispatch count must be 0 when assembly mismatch degrades risk state"
    );
    // Devil's advocate mutation guard: verify rejection is specifically from DispatchAuth
    // (via Degraded risk state override), not from the dispatch consistency gate.
    assert_eq!(
        pipeline_result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens),
        "rejection must come from DispatchAuth (Degraded override), not dispatch consistency gate"
    );
}

// ─── evaluate_assembled_pipeline integration ────────────────────────────

/// Assembly failure (unknown kind) → pipeline returns AssemblyFailed, dispatch=0.
#[test]
fn test_assembled_pipeline_unknown_kind_rejects() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Rejected { .. }),
        "unknown instrument kind must produce Rejected"
    );
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::AssemblyFailed),
        "reject reason must be AssemblyFailed"
    );
    // Dispatch causality: assembly failure must prevent dispatch.
    assert_eq!(
        metrics.chokepoint.approved_total(),
        0,
        "dispatch count must be 0 when assembly fails (unknown instrument kind)"
    );
}

// ─── CancelOnly bypass ──────────────────────────────────────────────────

/// CancelOnly must bypass assembly even when metadata is invalid.
/// This prevents urgent cancellations from being blocked by sizing failures.
#[test]
fn test_assembled_pipeline_cancel_only_bypasses_assembly() {
    // Invalid metadata that would fail assembly for any other intent class.
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: f64::NAN,
        index_price: f64::NAN,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::CancelOnly,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    // CancelOnly must be approved even with garbage metadata/sizing.
    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "CancelOnly must bypass assembly and be approved, got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "CancelOnly must produce exactly 1 approved dispatch"
    );
}

// ─── Close/Hedge through assembled pipeline ─────────────────────────────

/// Close intent with valid assembly → Approved.
/// Proves Close passes through the full pipeline when metadata is valid.
#[test]
fn test_assembled_pipeline_close_valid_assembly_approved() {
    let meta = InstrumentKindInput {
        is_option: true,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Close,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "Close with valid assembly must be approved, got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "Close must produce exactly 1 approved dispatch"
    );
}

/// Close intent with assembly failure → bypasses assembly, approved.
/// CSP Invariant F / AT-1049: risk-reducing intents must not be blocked
/// by metadata/sizing failures. Close falls through to the pipeline with
/// no_contracts() consistency.
#[test]
fn test_assembled_pipeline_close_assembly_failure_bypasses() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Close,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "Close must bypass assembly failure (CSP Invariant F), got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "Close must produce exactly 1 approved dispatch even when assembly fails"
    );
}

/// Hedge intent with valid assembly → Approved.
#[test]
fn test_assembled_pipeline_hedge_valid_assembly_approved() {
    let meta = InstrumentKindInput {
        is_option: true,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Hedge,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "Hedge with valid assembly must be approved, got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "Hedge must produce exactly 1 approved dispatch"
    );
}

/// Hedge intent with assembly failure → bypasses assembly, approved.
/// Same as Close: CSP Invariant F requires risk-reducing bypass.
#[test]
fn test_assembled_pipeline_hedge_assembly_failure_bypasses() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: false,
        is_perpetual: false,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 1.0,
        index_price: 50_000.0,
        contract_multiplier: None,
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Hedge,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "Hedge must bypass assembly failure (CSP Invariant F), got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "Hedge must produce exactly 1 approved dispatch even when assembly fails"
    );
}

/// Close intent with dispatch mismatch → Gate 4 skipped, approved.
/// CSP Invariant F / AT-104: risk-reducing intents skip DispatchConsistency.
/// The mismatch degrades risk state (Healthy → Degraded), but Close bypasses
/// DispatchAuth and Gate 4, so it is still approved.
#[test]
fn test_assembled_pipeline_close_mismatch_bypasses_dispatch_consistency() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 10.0,
        index_price: 50_000.0,
        contract_multiplier: Some(3.0),
    };
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Close,
        risk_state: RiskState::Healthy,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    // Close bypasses Gate 4 (DispatchConsistency) — risk-reducing intents
    // must not be blocked by AT-920 contract mismatch.
    assert!(
        matches!(result.decision, ChokeResult::Approved { .. }),
        "Close must bypass dispatch mismatch (Gate 4 skipped), got {:?}",
        result.decision
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        1,
        "Close dispatch count must be 1 (mismatch does not block risk-reducing intents)"
    );
}

// ─── RiskState severity preservation ─────────────────────────────────────

/// Kill risk state must NOT be downgraded to Degraded by assembly mismatch.
///
/// Regression test: evaluate_assembled_pipeline previously overwrote Kill→Degraded
/// unconditionally when risk_state_degraded=true, losing higher-severity signals.
/// The correct behavior (matching open_runtime.rs) is: only escalate Healthy→Degraded.
///
/// Note: Kill/Degraded/Maintenance all produce MarginHeadroomRejectOpens in the
/// current pipeline, so the reject reason alone cannot distinguish the bug.
/// The code-level fix (only override Healthy→Degraded) is verified by review.
/// This test documents the invariant and ensures Kill+mismatch blocks opens.
#[test]
fn test_assembled_pipeline_kill_not_downgraded_by_mismatch() {
    // Mismatch-inducing params (same as test_assembly_mismatch_sets_degraded).
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 10.0,
        index_price: 50_000.0,
        contract_multiplier: Some(3.0),
    };

    // Caller reports Kill — assembly mismatch must NOT downgrade to Degraded.
    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Kill,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    // Kill → OPEN must be rejected at DispatchAuth (Kill blocks all opens).
    assert!(
        matches!(result.decision, ChokeResult::Rejected { .. }),
        "OPEN with Kill risk_state must be rejected"
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        0,
        "dispatch count must be 0 when risk_state is Kill"
    );
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens),
        "Kill must block opens at DispatchAuth"
    );
}

/// Maintenance risk state must also be preserved through assembly mismatch.
#[test]
fn test_assembled_pipeline_maintenance_not_downgraded_by_mismatch() {
    let meta = InstrumentKindInput {
        is_option: false,
        is_future: true,
        is_perpetual: true,
        is_linear: false,
    };
    let params = SizingParams {
        canonical_qty: 10.0,
        index_price: 50_000.0,
        contract_multiplier: Some(3.0),
    };

    let base = base_open_input();
    let remaining = AssembledPipelineParams {
        intent_class: ChokeIntentClass::Open,
        risk_state: RiskState::Maintenance,
        preflight: base.preflight,
        venue_capabilities: base.venue_capabilities,
        bot_feature_flags: base.bot_feature_flags,
        quantize: base.quantize,
        fee_snapshot: base.fee_snapshot,
        fee_config: base.fee_config,
        expiry_guard: base.expiry_guard,
        liquidity: base.liquidity,
        net_edge: base.net_edge,
        pricer: base.pricer,
        wal_recorded: base.wal_recorded,
        requested_qty: base.requested_qty,
        max_dispatch_qty: base.max_dispatch_qty,
    };
    let mut metrics = IntentPipelineMetrics::new();
    let mut mismatch = MismatchMetrics::new();

    let result = evaluate_assembled_pipeline(&meta, &params, &mut mismatch, remaining, &mut metrics);

    assert!(
        matches!(result.decision, ChokeResult::Rejected { .. }),
        "OPEN with Maintenance risk_state must be rejected"
    );
    assert_eq!(
        metrics.chokepoint.approved_total(),
        0,
        "dispatch count must be 0 when risk_state is Maintenance"
    );
    assert_eq!(
        result.reject_reason_code,
        Some(RejectReasonCode::MarginHeadroomRejectOpens),
        "Maintenance must block opens at DispatchAuth"
    );
}

// ─── choke_intent_to_dispatch mapping ────────────────────────────────────

/// Table-driven test: verify all 4 ChokeIntentClass variants map correctly.
#[test]
fn test_choke_intent_to_dispatch_mapping() {
    let cases = [
        (ChokeIntentClass::Open, IntentClass::Open),
        (ChokeIntentClass::Close, IntentClass::Close),
        (ChokeIntentClass::Hedge, IntentClass::Hedge),
        (ChokeIntentClass::CancelOnly, IntentClass::Cancel),
    ];

    for (choke, expected_dispatch) in cases {
        let actual = choke_intent_to_dispatch(choke);
        assert_eq!(
            actual, expected_dispatch,
            "choke_intent_to_dispatch({choke:?}) should map to {expected_dispatch:?}"
        );
    }
}
