//! Tests for process-lifetime static rejection counters (Layer 1 observability).
//!
//! Each test verifies that calling a gate with reject-inducing inputs increments
//! the corresponding static counter. Because static counters are shared across
//! all tests in the process, we test *increment* behavior (counter increases by
//! at least 1) rather than absolute values.

use soldier_core::execution::{
    InventorySkewInput, InventorySkewMetrics, InventorySkewRejectReason, InventorySkewResult,
    PostOnlyInput, PostOnlyMetrics, PostOnlyResult, PricerInput, PricerMetrics,
    PricerRejectReason, PricerResult, QuantizeConstraints, QuantizeError, QuantizeMetrics,
    QuantizeStaticRejectReason, Side, check_post_only, compute_limit_price,
    evaluate_inventory_skew, inventory_skew_reject_total, post_only_reject_total,
    pricer_reject_total, quantize, quantize_reject_total,
};

use soldier_core::execution::{
    GroupConfig, GroupLock, InMemoryGroupPersistence, AtomicGroup,
    group_lock_timeout_total, group_mixed_failed_total, group_persist_fail_total,
    persist_before_dispatch, try_acquire_group_lock,
};

use soldier_core::risk::{
    ExposureBudgetInput, ExposureBudgetMetrics, ExposureBudgetResult,
    ExposureBudgetStaticRejectReason, ExposureBucket, FeeCacheSnapshot,
    FeeStaleness, FeeStalenessConfig, MarginGateDecision, MarginGateInput, MarginGateMetrics,
    PendingExposureBook, PendingExposureMetrics, PendingExposureResult, ReservationId,
    evaluate_fee_staleness, evaluate_global_exposure_budget, evaluate_margin_headroom_gate,
    exposure_budget_reject_total, fee_staleness_hard_stale_total, margin_gate_reject_total,
    pending_exposure_reject_total,
};

// ─── Inventory Skew ─────────────────────────────────────────────────────

#[test]
fn test_inventory_skew_missing_delta_limit_reject_counter() {
    let before = inventory_skew_reject_total(
        InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
    );
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: 0.0,
        pending_delta: 0.0,
        delta_limit: None, // missing → reject
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after = inventory_skew_reject_total(
        InventorySkewRejectReason::InventorySkewDeltaLimitMissing,
    );
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_inventory_skew_nan_reject_counter() {
    let before = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    let mut metrics = InventorySkewMetrics::new();
    let input = InventorySkewInput {
        current_delta: f64::NAN, // NaN → reject
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 2.0,
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_inventory_skew_edge_below_adjusted_reject_counter() {
    let before = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    let mut metrics = InventorySkewMetrics::new();
    // High bias (long 90 of 100 limit) with Buy side → tightened edge requirement
    let input = InventorySkewInput {
        current_delta: 90.0,
        pending_delta: 0.0,
        delta_limit: Some(100.0),
        side: Side::Buy,
        min_edge_usd: 1.0,
        net_edge_usd: 0.5, // below adjusted min_edge → reject
        limit_price: 100.0,
        tick_size: 0.01,
        inventory_skew_k: 0.5,
        inventory_skew_tick_penalty_max: 3,
    };
    let result = evaluate_inventory_skew(&input, &mut metrics);
    assert!(matches!(result, InventorySkewResult::Rejected { .. }));
    let after = inventory_skew_reject_total(InventorySkewRejectReason::InventorySkewReject);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Pricer ─────────────────────────────────────────────────────────────

#[test]
fn test_pricer_invalid_input_reject_counter() {
    let before = pricer_reject_total(PricerRejectReason::InvalidInput);
    let mut metrics = PricerMetrics::new();
    let input = PricerInput {
        fair_price: f64::NAN, // NaN → reject
        gross_edge_usd: 1.0,
        min_edge_usd: 0.5,
        fee_estimate_usd: 0.1,
        qty: 1.0,
        side: Side::Buy,
    };
    let result = compute_limit_price(&input, &mut metrics);
    assert!(matches!(result, PricerResult::Rejected { reason: PricerRejectReason::InvalidInput, .. }));
    let after = pricer_reject_total(PricerRejectReason::InvalidInput);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_pricer_net_edge_too_low_reject_counter() {
    let before = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    let mut metrics = PricerMetrics::new();
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 0.5,
        min_edge_usd: 1.0, // gross_edge - fees < min_edge → reject
        fee_estimate_usd: 0.1,
        qty: 1.0,
        side: Side::Buy,
    };
    let result = compute_limit_price(&input, &mut metrics);
    assert!(matches!(result, PricerResult::Rejected { reason: PricerRejectReason::NetEdgeTooLow, .. }));
    let after = pricer_reject_total(PricerRejectReason::NetEdgeTooLow);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Quantize ───────────────────────────────────────────────────────────

#[test]
fn test_quantize_too_small_reject_counter() {
    let constraints = QuantizeConstraints {
        tick_size: 0.01,
        amount_step: 1.0,
        min_amount: 10.0,
    };
    let before = quantize_reject_total(QuantizeStaticRejectReason::TooSmall);
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(0.5, 100.0, Side::Buy, &constraints, &mut metrics);
    assert!(matches!(result, Err(QuantizeError::TooSmallAfterQuantization { .. })));
    let after = quantize_reject_total(QuantizeStaticRejectReason::TooSmall);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_quantize_invalid_input_nan_reject_counter() {
    let constraints = QuantizeConstraints {
        tick_size: 0.01,
        amount_step: 1.0,
        min_amount: 1.0,
    };
    let before = quantize_reject_total(QuantizeStaticRejectReason::InvalidInput);
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(f64::NAN, 100.0, Side::Buy, &constraints, &mut metrics);
    assert!(matches!(result, Err(QuantizeError::InvalidInput { .. })));
    let after = quantize_reject_total(QuantizeStaticRejectReason::InvalidInput);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_quantize_missing_metadata_reject_counter() {
    let constraints = QuantizeConstraints {
        tick_size: 0.0, // invalid → MetadataMissing
        amount_step: 1.0,
        min_amount: 1.0,
    };
    let before = quantize_reject_total(QuantizeStaticRejectReason::MetadataMissing);
    let mut metrics = QuantizeMetrics::new();
    let result = quantize(10.0, 100.0, Side::Buy, &constraints, &mut metrics);
    assert!(matches!(result, Err(QuantizeError::InstrumentMetadataMissing { .. })));
    let after = quantize_reject_total(QuantizeStaticRejectReason::MetadataMissing);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Post-Only Guard ────────────────────────────────────────────────────

#[test]
fn test_post_only_cross_reject_counter() {
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price: 100.0,
        best_ask: Some(99.0), // limit >= ask → cross → reject
        best_bid: None,
    };
    let result = check_post_only(&input, &mut metrics);
    assert_eq!(result, PostOnlyResult::Rejected);
    let after = post_only_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_post_only_nan_limit_fail_closed_reject_counter() {
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Buy,
        limit_price: f64::NAN, // NaN → fail-closed reject
        best_ask: Some(100.0),
        best_bid: None,
    };
    let result = check_post_only(&input, &mut metrics);
    assert_eq!(result, PostOnlyResult::Rejected);
    let after = post_only_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_post_only_counter_monotonic() {
    let before = post_only_reject_total();
    let mut metrics = PostOnlyMetrics::new();
    let input = PostOnlyInput {
        post_only: true,
        side: Side::Sell,
        limit_price: 100.0,
        best_ask: None,
        best_bid: Some(101.0), // limit <= bid → cross → reject
    };
    check_post_only(&input, &mut metrics);
    let mid = post_only_reject_total();
    check_post_only(&input, &mut metrics);
    let after = post_only_reject_total();
    assert!(mid > before, "first call should increment");
    assert!(after > mid, "second call should increment further (monotonic)");
}

// ─── Group ──────────────────────────────────────────────────────────────

#[test]
fn test_group_lock_timeout_reject_counter() {
    let before = group_lock_timeout_total();
    let config = GroupConfig {
        group_lock_max_wait_ms: 0, // immediate timeout
        ..Default::default()
    };
    let mut lock = GroupLock::new();
    lock.try_acquire(); // hold the lock
    let _result = try_acquire_group_lock(&mut lock, &config);
    let after = group_lock_timeout_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_group_persist_fail_reject_counter() {
    let before = group_persist_fail_total();
    let group = AtomicGroup::new("grp-test".to_string(), 2);
    let mut store = InMemoryGroupPersistence {
        fail_persist: true,
        ..Default::default()
    };
    let result = persist_before_dispatch(&group, &mut store);
    assert!(result.is_err());
    let after = group_persist_fail_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_group_mixed_failed_reject_counter() {
    use soldier_core::execution::{GroupStateTransition, LegResult};
    use soldier_core::execution::tlsm::TlsmState;

    let before = group_mixed_failed_total();
    let config = GroupConfig::default();
    let mut group = AtomicGroup::new("grp-counter".to_string(), 2);
    group.mark_dispatched().unwrap();

    // Leg 0 fills
    group.apply_leg_result(
        LegResult {
            leg_idx: 0,
            requested_qty: 1.0,
            filled_qty: 1.0,
            rejected: false,
            unfilled: false,
            tlsm_state: TlsmState::Filled,
        },
        &config,
    );

    // Leg 1 rejected → MixedFailed
    let transition = group.apply_leg_result(
        LegResult {
            leg_idx: 1,
            requested_qty: 1.0,
            filled_qty: 0.0,
            rejected: true,
            unfilled: false,
            tlsm_state: TlsmState::Failed,
        },
        &config,
    );
    assert!(matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }));
    let after = group_mixed_failed_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Fee Staleness ──────────────────────────────────────────────────────

#[test]
fn test_fee_staleness_hard_stale_missing_ts_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: None, // missing → hard-stale
        now_ms: 1_000_000,
    };
    let config = FeeStalenessConfig::default();
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_fee_staleness_hard_stale_expired_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let config = FeeStalenessConfig::default();
    let snapshot = FeeCacheSnapshot {
        fee_rate: 0.001,
        fee_model_cached_at_ts_ms: Some(0),
        now_ms: (config.fee_cache_hard_s + 1) * 1000 + 1, // well past hard threshold
    };
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_fee_staleness_nan_rate_fail_closed_reject_counter() {
    let before = fee_staleness_hard_stale_total();
    let snapshot = FeeCacheSnapshot {
        fee_rate: f64::NAN, // NaN → hard-stale
        fee_model_cached_at_ts_ms: Some(1_000_000),
        now_ms: 1_000_000,
    };
    let config = FeeStalenessConfig::default();
    let result = evaluate_fee_staleness(&snapshot, &config);
    assert_eq!(result.staleness, FeeStaleness::HardStale);
    let after = fee_staleness_hard_stale_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Margin Gate ────────────────────────────────────────────────────────

#[test]
fn test_margin_gate_invalid_input_reject_counter() {
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: f64::NAN, // NaN → reject
        equity_usd: 1000.0,
        mm_util_reject_opens: 0.70,
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let result = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(matches!(result, MarginGateDecision::Rejected { .. }));
    let after = margin_gate_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_margin_gate_over_threshold_reject_counter() {
    let before = margin_gate_reject_total();
    let mut metrics = MarginGateMetrics::new();
    let input = MarginGateInput {
        maintenance_margin_usd: 800.0,
        equity_usd: 1000.0,
        mm_util_reject_opens: 0.70, // mm_util = 0.8 >= 0.70 → reject
        mm_util_reduceonly: 0.85,
        mm_util_kill: 0.95,
    };
    let result = evaluate_margin_headroom_gate(&input, &mut metrics);
    assert!(matches!(result, MarginGateDecision::Rejected { .. }));
    let after = margin_gate_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Pending Exposure ───────────────────────────────────────────────────

#[test]
fn test_pending_exposure_unregistered_instrument_reject_counter() {
    let before = pending_exposure_reject_total();
    let book = PendingExposureBook::new(None);
    // Do NOT register any instrument
    let mut metrics = PendingExposureMetrics::new();
    let rid = ReservationId::new("test-1").unwrap();
    let result = book.reserve(&rid, "UNKNOWN", 0.0, 1.0, &mut metrics);
    assert!(matches!(result, PendingExposureResult::Rejected { .. }));
    let after = pending_exposure_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_pending_exposure_budget_exceeded_reject_counter() {
    let before = pending_exposure_reject_total();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(10.0));
    let mut metrics = PendingExposureMetrics::new();
    let rid = ReservationId::new("test-2").unwrap();
    // Reserve 100 when limit is 10 → reject
    let result = book.reserve(&rid, "BTC", 0.0, 100.0, &mut metrics);
    assert!(matches!(result, PendingExposureResult::Rejected { .. }));
    let after = pending_exposure_reject_total();
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

// ─── Exposure Budget ────────────────────────────────────────────────────

#[test]
fn test_exposure_budget_missing_limit_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 0.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: None, // missing → reject
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::LimitMissing);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_exposure_budget_over_limit_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: 1_000_000.0,
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: Some(100.0), // way over → reject
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}

#[test]
fn test_exposure_budget_nan_input_fail_closed_reject_counter() {
    let before = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    let mut metrics = ExposureBudgetMetrics::new();
    let input = ExposureBudgetInput {
        current_btc_delta_usd: f64::NAN, // NaN → reject
        pending_btc_delta_usd: 0.0,
        current_eth_delta_usd: 0.0,
        pending_eth_delta_usd: 0.0,
        current_alts_delta_usd: 0.0,
        pending_alts_delta_usd: 0.0,
        candidate_bucket: ExposureBucket::Btc,
        candidate_delta_usd: 1.0,
        global_delta_limit_usd: Some(100.0),
    };
    let result = evaluate_global_exposure_budget(&input, &mut metrics);
    assert!(matches!(result, ExposureBudgetResult::Rejected { .. }));
    let after = exposure_budget_reject_total(ExposureBudgetStaticRejectReason::Reject);
    assert!(after > before, "counter should increment: before={before}, after={after}");
}
