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

/// Dispatch mismatch: mismatched contracts/amount → dispatch_consistency_passed=false,
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
        !assembled.dispatch_consistency_passed,
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
