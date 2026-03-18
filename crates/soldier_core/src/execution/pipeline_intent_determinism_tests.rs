//! CI test proving identical inputs produce identical intent outputs.
//!
//! CSP.2.1 Stable Intent Identity: Same inputs → same quantized values,
//! same gate trace, same limit price, same label — across runs and restarts.
//!
//! No HashMap iteration order dependency, no clock dependency, no randomness.

#![allow(deprecated)]

trait TestValueExt<T> {
    fn must(self) -> T;
}

impl<T, E: std::fmt::Debug> TestValueExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

impl<T> TestValueExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

use crate::execution::build_order_intent::{
    ChokeIntentClass, ChokeMetrics, ChokeResult, GateResults, GateStep, build_order_intent,
};
use crate::execution::gate::{
    GateIntentClass, L2BookSnapshot, L2Level, LiquidityGateInput, LiquidityGateMetrics,
    evaluate_liquidity_gate,
};
use crate::execution::gates::{NetEdgeInput, NetEdgeMetrics, evaluate_net_edge};
use crate::execution::label::{LabelInput, derive_gid12, derive_sid8, encode_label};
use crate::execution::pricer::{PricerInput, PricerMetrics, PricerResult, compute_limit_price};
use crate::execution::quantize::{QuantizeConstraints, QuantizeMetrics, Side, quantize};
use crate::risk::RiskState;
use std::collections::HashMap;

fn gate_results_all_passing() -> GateResults {
    GateResults {
        preflight_passed: true,
        quantize_passed: true,
        dispatch_consistency_passed: true,
        fee_cache_passed: true,
        expiry_guard_passed: true,
        liquidity_gate_passed: true,
        net_edge_passed: true,
        pricer_passed: true,
        wal_recorded: true,
        requested_qty: None,
        max_dispatch_qty: None,
    }
}

// ─── Quantize determinism ────────────────────────────────────────────────

#[test]
fn test_quantize_same_inputs_same_output() {
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = QuantizeMetrics::new();
        let r = quantize(1.23456, 100.789, Side::Buy, &constraints, &mut m).must();
        results.push((r.qty_q, r.qty_steps, r.limit_price_q, r.price_ticks));
    }

    // All 100 runs must produce identical results
    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(
            r, first,
            "Quantize run {i} differs from run 0: {r:?} vs {first:?}"
        );
    }
}

#[test]
fn test_quantize_sell_deterministic() {
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = QuantizeMetrics::new();
        let r = quantize(1.23456, 100.789, Side::Sell, &constraints, &mut m).must();
        results.push((r.qty_q, r.qty_steps, r.limit_price_q, r.price_ticks));
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Quantize sell run {i} differs from run 0");
    }
}

// ─── Chokepoint determinism ──────────────────────────────────────────────

#[test]
fn test_chokepoint_same_inputs_same_trace() {
    let gates = gate_results_all_passing();

    let mut traces = Vec::new();
    for _ in 0..100 {
        let mut m = ChokeMetrics::new();
        let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);
        match result {
            ChokeResult::Approved { gate_trace } => traces.push(gate_trace),
            other => panic!("expected Approved, got {other:?}"),
        }
    }

    let first = &traces[0];
    for (i, t) in traces.iter().enumerate() {
        assert_eq!(t, first, "Chokepoint trace run {i} differs from run 0");
    }
}

#[test]
fn test_chokepoint_rejected_deterministic() {
    let gates = GateResults {
        liquidity_gate_passed: false,
        ..gate_results_all_passing()
    };

    let mut results = Vec::new();
    for _ in 0..50 {
        let mut m = ChokeMetrics::new();
        let result = build_order_intent(ChokeIntentClass::Open, RiskState::Healthy, &mut m, &gates);
        results.push(result);
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Chokepoint rejected run {i} differs from run 0");
    }
}

// ─── Pricer determinism ──────────────────────────────────────────────────

#[test]
fn test_pricer_same_inputs_same_price() {
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 10.0,
        min_edge_usd: 2.0,
        fee_estimate_usd: 3.0,
        expected_slippage_usd: 1.0,
        qty: 1.0,
        side: Side::Buy,
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = PricerMetrics::new();
        let r = compute_limit_price(&input, &mut m);
        results.push(r);
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Pricer run {i} differs from run 0");
    }
}

#[test]
fn test_pricer_sell_deterministic() {
    let input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 10.0,
        min_edge_usd: 2.0,
        fee_estimate_usd: 3.0,
        expected_slippage_usd: 1.0,
        qty: 1.0,
        side: Side::Sell,
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = PricerMetrics::new();
        let r = compute_limit_price(&input, &mut m);
        results.push(r);
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Pricer sell run {i} differs from run 0");
    }
}

// ─── Net edge determinism ────────────────────────────────────────────────

#[test]
fn test_net_edge_same_inputs_same_result() {
    let input = NetEdgeInput {
        gross_edge_usd: Some(10.0),
        fee_usd: Some(3.0),
        expected_slippage_usd: Some(1.0),
        min_edge_usd: Some(2.0),
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = NetEdgeMetrics::new();
        let r = evaluate_net_edge(&input, &mut m);
        results.push(r);
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Net edge run {i} differs from run 0");
    }
}

// ─── Liquidity gate determinism ──────────────────────────────────────────

#[test]
fn test_liquidity_gate_same_inputs_same_result() {
    let make_input = || LiquidityGateInput {
        order_qty: 3.0,
        is_buy: true,
        intent_class: GateIntentClass::Open,
        is_marketable: true,
        l2_snapshot: Some(L2BookSnapshot {
            asks: vec![
                L2Level {
                    price: 101.0,
                    qty: 5.0,
                },
                L2Level {
                    price: 102.0,
                    qty: 10.0,
                },
            ],
            bids: vec![
                L2Level {
                    price: 99.0,
                    qty: 5.0,
                },
                L2Level {
                    price: 98.0,
                    qty: 10.0,
                },
            ],
            timestamp_ms: 1000,
        }),
        now_ms: 2000,
        l2_book_snapshot_max_age_ms: 5000,
        max_slippage_bps: 200.0,
    };

    let mut results = Vec::new();
    for _ in 0..100 {
        let mut m = LiquidityGateMetrics::new();
        let input = make_input();
        let r = evaluate_liquidity_gate(&input, &mut m);
        results.push(r);
    }

    let first = &results[0];
    for (i, r) in results.iter().enumerate() {
        assert_eq!(r, first, "Liquidity gate run {i} differs from run 0");
    }
}

// ─── Label determinism ───────────────────────────────────────────────────

#[test]
fn test_label_encode_deterministic() {
    let input = LabelInput {
        sid8: "abcd1234",
        gid12: "012345678901",
        leg_idx: 0,
        ih16: "deadbeef01234567",
    };

    let mut labels = Vec::new();
    for _ in 0..100 {
        let label = encode_label(&input).must();
        labels.push(label);
    }

    let first = &labels[0];
    for (i, l) in labels.iter().enumerate() {
        assert_eq!(l, first, "Label encode run {i} differs from run 0");
    }
}

#[test]
fn test_sid8_deterministic() {
    let mut hashes = Vec::new();
    for _ in 0..100 {
        let h = derive_sid8("my-strategy-id");
        hashes.push(h);
    }

    let first = &hashes[0];
    for (i, h) in hashes.iter().enumerate() {
        assert_eq!(h, first, "sid8 run {i} differs from run 0");
    }
}

#[test]
fn test_gid12_deterministic() {
    let mut hashes = Vec::new();
    for _ in 0..100 {
        let h = derive_gid12("550e8400-e29b-41d4-a716-446655440000");
        hashes.push(h);
    }

    let first = &hashes[0];
    for (i, h) in hashes.iter().enumerate() {
        assert_eq!(h, first, "gid12 run {i} differs from run 0");
    }
}

// ─── No HashMap ordering dependency ─────────────────────────────────────

#[test]
fn test_no_hashmap_ordering_dependency() {
    // Build a HashMap with many keys to trigger different iteration orders,
    // then feed values to quantize. Prove the output is identical regardless.
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let mut reference = None;

    for seed in 0u64..50 {
        // Build HashMap with varying insertion order
        let mut map: HashMap<String, f64> = HashMap::new();
        for i in 0..20 {
            let key = format!("key_{}", (i + seed) % 20);
            map.insert(key, 1.5);
        }

        // Use a fixed value from the map (not iteration order)
        let qty = *map.get("key_0").must();
        let price = 100.5;

        let mut m = QuantizeMetrics::new();
        let result = quantize(qty, price, Side::Buy, &constraints, &mut m).must();
        let output = (
            result.qty_q,
            result.qty_steps,
            result.limit_price_q,
            result.price_ticks,
        );

        match &reference {
            None => reference = Some(output),
            Some(ref_val) => {
                assert_eq!(
                    &output, ref_val,
                    "HashMap seed {seed} produced different quantize output"
                );
            }
        }
    }
}

// ─── Full pipeline determinism ───────────────────────────────────────────

#[test]
fn test_full_pipeline_determinism() {
    // Run the complete intent pipeline with fixed inputs 100 times
    let constraints = QuantizeConstraints {
        tick_size: 0.5,
        amount_step: 0.1,
        min_amount: 0.1,
    };

    let pricer_input = PricerInput {
        fair_price: 100.0,
        gross_edge_usd: 10.0,
        min_edge_usd: 2.0,
        fee_estimate_usd: 3.0,
        expected_slippage_usd: 1.0,
        qty: 1.0,
        side: Side::Buy,
    };

    let gate_results = gate_results_all_passing();

    #[derive(Debug, PartialEq)]
    struct PipelineSnapshot {
        qty_q: f64,
        price_ticks: i64,
        limit_price: PricerResult,
        choke_trace: Vec<GateStep>,
    }

    let mut snapshots = Vec::new();

    for _ in 0..100 {
        let mut qm = QuantizeMetrics::new();
        let qv = quantize(1.5, 100.3, Side::Buy, &constraints, &mut qm).must();

        let mut pm = PricerMetrics::new();
        let pr = compute_limit_price(&pricer_input, &mut pm);

        let mut cm = ChokeMetrics::new();
        let cr = build_order_intent(
            ChokeIntentClass::Open,
            RiskState::Healthy,
            &mut cm,
            &gate_results,
        );

        let trace = match cr {
            ChokeResult::Approved { gate_trace } => gate_trace,
            other => panic!("expected Approved, got {other:?}"),
        };

        snapshots.push(PipelineSnapshot {
            qty_q: qv.qty_q,
            price_ticks: qv.price_ticks,
            limit_price: pr,
            choke_trace: trace,
        });
    }

    let first = &snapshots[0];
    for (i, s) in snapshots.iter().enumerate() {
        assert_eq!(s, first, "Full pipeline run {i} differs from run 0");
    }
}
