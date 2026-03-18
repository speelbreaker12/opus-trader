//! Tests for intent hash computation per CONTRACT.md §1.1.1.
//!
//! AT-218: deterministic hash across codepaths.
//! AT-343: hash excludes wall-clock timestamps.

use soldier_core::execution::{
    ExecutionBaseInput, ExecutionDecision, ExecutionEngine, ExecutionInput,
    ExecutionL2BookSnapshot, ExecutionL2Level, ExecutionOrderType, ExecutionPreflightInput,
    ExecutionRejection, ExecutionRuntime, ExecutionStep, GateRejectCodes, GateStep,
    InventorySkewExecutionInput, LiquidityExecutionInput, NetEdgeExecutionInput,
    OpenExecutionInput, PricerExecutionInput, QuantizeExecutionInput, RecordedBeforeDispatchGate,
    RejectReasonCode, Side,
};
use soldier_core::idempotency::{
    IntentHashInput, compute_intent_hash, format_intent_hash, intent_hash_ih16,
};
use soldier_core::risk::{
    ExposureBucket, ExposureBudgetInput, FeeCacheSnapshot, FeeStalenessConfig, MarginGateInput,
    PendingExposureBook, ReservationId, RiskState,
};
use soldier_core::venue::{
    BotFeatureFlags, ExpiryGuardInput, InstrumentKind, LifecycleIntent, VenueCapabilities,
};
use xxhash_rust::xxh64::xxh64;

/// Helper to build a standard test input.
fn sample_input() -> IntentHashInput<'static> {
    IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 3000,
        price_ticks: 100_000,
        group_id: "550e8400-e29b-41d4-a716-446655440000",
        leg_idx: 0,
    }
}

fn canonical_intent_string_v1(input: &IntentHashInput<'_>) -> String {
    format!(
        "v1|{}|{}|{}|{}|{}|{}",
        input.instrument.to_lowercase(),
        input.side.to_lowercase(),
        input.qty_steps,
        input.price_ticks,
        input.group_id.replace('-', "").to_lowercase(),
        input.leg_idx
    )
}

// ─── AT-218: Deterministic hashing ─────────────────────────────────────

/// AT-218: same inputs → same hash
#[test]
fn test_at218_deterministic_hash() {
    let input = sample_input();
    let h1 = compute_intent_hash(&input);
    let h2 = compute_intent_hash(&input);
    assert_eq!(h1, h2, "identical inputs must produce identical hashes");
}

/// AT-218: two codepaths with same fields → same hash
#[test]
fn test_at218_two_codepaths_same_hash() {
    let input_a = IntentHashInput {
        instrument: "ETH-PERPETUAL",
        side: "sell",
        qty_steps: 500,
        price_ticks: 3_500_000,
        group_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        leg_idx: 1,
    };
    // Construct independently
    let input_b = IntentHashInput {
        instrument: "ETH-PERPETUAL",
        side: "sell",
        qty_steps: 500,
        price_ticks: 3_500_000,
        group_id: "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
        leg_idx: 1,
    };
    assert_eq!(
        compute_intent_hash(&input_a),
        compute_intent_hash(&input_b),
        "independently constructed identical inputs must hash equally"
    );
}

#[test]
fn test_contract_hash_uses_canonical_v1_utf8_serialization() {
    let input = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "BUY",
        qty_steps: 3000,
        price_ticks: 100_000,
        group_id: "550E8400-E29B-41D4-A716-446655440000",
        leg_idx: 0,
    };

    let canonical = canonical_intent_string_v1(&input);
    let expected = xxh64(canonical.as_bytes(), 0);
    let actual = compute_intent_hash(&input);
    assert_eq!(
        actual, expected,
        "intent hash must be xxhash64 over canonical v1 UTF-8 serialization"
    );
}

// ─── AT-343: No wall-clock dependency ──────────────────────────────────

/// AT-343: hash does not include timestamps — same fields at different
/// "times" produce the same hash.
#[test]
fn test_at343_no_timestamp_in_hash() {
    // The IntentHashInput struct has no timestamp field at all,
    // proving timestamps cannot influence the hash.
    let input = sample_input();
    let h1 = compute_intent_hash(&input);
    // "Simulate" a different wall-clock time by just calling again
    let h2 = compute_intent_hash(&input);
    assert_eq!(
        h1, h2,
        "hash must be identical regardless of when it's computed"
    );
}

/// AT-343: IntentHashInput has no timestamp field (compile-time proof).
/// This test proves the struct cannot carry time data.
#[test]
fn test_at343_no_timestamp_field() {
    // If someone adds a timestamp field to IntentHashInput,
    // this test will fail to compile (wrong number of fields).
    let _input = IntentHashInput {
        instrument: "BTC-PERPETUAL",
        side: "buy",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "test",
        leg_idx: 0,
    };
}

// ─── Hash uses integer values ──────────────────────────────────────────

/// Hash uses qty_steps (integer), not raw f64
#[test]
fn test_uses_integer_qty_steps() {
    let mut input = sample_input();
    input.qty_steps = 3000;
    let h1 = compute_intent_hash(&input);

    input.qty_steps = 3001;
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2, "different qty_steps must produce different hashes");
}

/// Hash uses price_ticks (integer), not raw f64
#[test]
fn test_uses_integer_price_ticks() {
    let mut input = sample_input();
    input.price_ticks = 100_000;
    let h1 = compute_intent_hash(&input);

    input.price_ticks = 100_001;
    let h2 = compute_intent_hash(&input);
    assert_ne!(
        h1, h2,
        "different price_ticks must produce different hashes"
    );
}

// ─── Field sensitivity ─────────────────────────────────────────────────

/// Different instrument → different hash
#[test]
fn test_different_instrument_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.instrument = "ETH-PERPETUAL";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different side → different hash
#[test]
fn test_different_side_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.side = "sell";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different group_id → different hash
#[test]
fn test_different_group_id_different_hash() {
    let mut input = sample_input();
    let h1 = compute_intent_hash(&input);

    input.group_id = "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee";
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

/// Different leg_idx → different hash
#[test]
fn test_different_leg_idx_different_hash() {
    let mut input = sample_input();
    input.leg_idx = 0;
    let h1 = compute_intent_hash(&input);

    input.leg_idx = 1;
    let h2 = compute_intent_hash(&input);
    assert_ne!(h1, h2);
}

// ─── Formatting ────────────────────────────────────────────────────────

/// format_intent_hash produces 16-char hex string
#[test]
fn test_format_intent_hash_length() {
    let hash = compute_intent_hash(&sample_input());
    let formatted = format_intent_hash(hash);
    assert_eq!(formatted.len(), 16, "xxhash64 hex must be 16 chars");
    assert!(
        formatted.chars().all(|c| c.is_ascii_hexdigit()),
        "must be hex"
    );
}

/// ih16 is the full 16-char hex (xxhash64 is 64 bits = 16 hex chars)
#[test]
fn test_ih16_is_full_hash_hex() {
    let hash = compute_intent_hash(&sample_input());
    let ih16 = intent_hash_ih16(hash);
    let formatted = format_intent_hash(hash);
    assert_eq!(ih16, formatted, "ih16 should be full formatted hash");
}

// ─── Non-zero hash ─────────────────────────────────────────────────────

/// Hash is non-zero for typical inputs
#[test]
fn test_hash_nonzero() {
    let hash = compute_intent_hash(&sample_input());
    assert_ne!(hash, 0, "hash should not be zero for typical inputs");
}

// ─── Field boundary safety ─────────────────────────────────────────────

/// Fields with shifted boundaries produce different hashes
/// (e.g., instrument="AB" + side="CD" vs instrument="ABC" + side="D")
#[test]
fn test_field_boundary_separation() {
    let input_a = IntentHashInput {
        instrument: "AB",
        side: "CD",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };
    let input_b = IntentHashInput {
        instrument: "ABC",
        side: "D",
        qty_steps: 1,
        price_ticks: 1,
        group_id: "g",
        leg_idx: 0,
    };
    assert_ne!(
        compute_intent_hash(&input_a),
        compute_intent_hash(&input_b),
        "shifted field boundaries must produce different hashes"
    );
}

struct DuplicateWalGate {
    calls: usize,
}

impl RecordedBeforeDispatchGate for DuplicateWalGate {
    fn record_before_dispatch(&mut self) -> Result<(), String> {
        self.calls += 1;
        Err("duplicate intent_hash".to_string())
    }
}

fn at928_open_input() -> OpenExecutionInput<'static> {
    OpenExecutionInput {
        base: ExecutionBaseInput {
            risk_state: RiskState::Healthy,
            preflight: ExecutionPreflightInput {
                instrument_kind: InstrumentKind::Option,
                order_type: ExecutionOrderType::Limit,
                has_trigger: false,
                linked_order_type: None,
                linked_orders_allowed: false,
                post_only: None,
            },
            venue_capabilities: VenueCapabilities::default(),
            bot_feature_flags: BotFeatureFlags::default(),
            quantize: QuantizeExecutionInput {
                raw_qty: 1.0,
                raw_limit_price: 100.0,
                side: Side::Buy,
                tick_size: 0.1,
                amount_step: 0.1,
                min_amount: 0.1,
            },
            dispatch_consistency_passed: true,
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
        },
        gate_reject_codes: GateRejectCodes::default(),
        current_delta: 0.0,
        delta_impact_est: 10.0,
        liquidity: LiquidityExecutionInput {
            order_qty: 1.0,
            side: Side::Buy,
            is_marketable: true,
            l2_snapshot: Some(ExecutionL2BookSnapshot {
                asks: vec![ExecutionL2Level {
                    price: 100.0,
                    qty: 10.0,
                }],
                bids: vec![ExecutionL2Level {
                    price: 99.0,
                    qty: 10.0,
                }],
                timestamp_ms: 1_000,
            }),
            now_ms: 1_050,
            l2_book_snapshot_max_age_ms: 100,
            max_slippage_bps: 20.0,
        },
        net_edge: NetEdgeExecutionInput {
            gross_edge_usd: Some(12.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(9.0),
        },
        inventory_skew: InventorySkewExecutionInput {
            current_delta: 0.0,
            pending_delta: 0.0,
            delta_limit: Some(100.0),
            side: Side::Buy,
            min_edge_usd: 9.0,
            net_edge_usd: 10.0,
            limit_price: 100.0,
            tick_size: 0.5,
            inventory_skew_k: 0.1,
            inventory_skew_tick_penalty_max: 3,
        },
        pricer: PricerExecutionInput {
            fair_price: 100.0,
            gross_edge_usd: 20.0,
            min_edge_usd: 9.0,
            fee_estimate_usd: 2.0,
            expected_slippage_usd: 1.0,
            qty: 1.0,
            side: Side::Buy,
        },
        exposure_budget: ExposureBudgetInput {
            current_btc_delta_usd: 0.0,
            pending_btc_delta_usd: 0.0,
            current_eth_delta_usd: 0.0,
            pending_eth_delta_usd: 0.0,
            current_alts_delta_usd: 0.0,
            pending_alts_delta_usd: 0.0,
            candidate_bucket: ExposureBucket::Btc,
            candidate_delta_usd: 10.0,
            global_delta_limit_usd: Some(1_000.0),
        },
        margin_gate: MarginGateInput {
            maintenance_margin_usd: 10.0,
            equity_usd: 100.0,
            mm_util_reject_opens: 0.70,
            mm_util_reduceonly: 0.85,
            mm_util_kill: 0.95,
            now_ms: 1_000,
            mm_util_last_update_ts_ms: Some(1_000),
            mm_util_max_age_ms: 30_000,
        },
        reservation_id: match ReservationId::new("test-intent-at928".to_string()) {
            Some(value) => value,
            None => panic!("invalid reservation id fixture"),
        },
        instrument_id: "BTC-PERPETUAL".to_string(),
    }
}

fn at928_pending_book() -> PendingExposureBook {
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC-PERPETUAL", Some(100.0));
    book
}

/// AT-928: if WAL reports duplicate intent hash, OPEN evaluation is a no-dispatch NOOP.
///
/// WAL unchanged semantics are enforced in infra (`test_duplicate_intent_hash_rejected`).
/// This test proves the core execution chokepoint does not dispatch on duplicates.
#[test]
fn test_intent_hash_noop_when_already_in_wal() {
    let engine = ExecutionEngine::new();
    let mut wal_gate = DuplicateWalGate { calls: 0 };
    let book = at928_pending_book();
    let mut runtime = ExecutionRuntime::new(Some(&mut wal_gate), Some(&book));

    let decision = engine.decide(&ExecutionInput::Open(at928_open_input()), &mut runtime);

    assert_eq!(wal_gate.calls, 1, "open path should consult WAL once");
    assert!(matches!(
        decision,
        ExecutionDecision::Rejected(ExecutionRejection {
            code: RejectReasonCode::RecordedBeforeDispatchFailed,
            step: ExecutionStep::Gate(GateStep::RecordedBeforeDispatch),
            ..
        })
    ));
}
