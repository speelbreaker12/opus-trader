//! Property-based tests for the Net Edge Gate (CONTRACT.md §1.4.1).
//!
//! Properties under test:
//! - net_edge = gross - fee - slippage identity holds when Allowed.
//! - Any None field → Rejected(NetEdgeInputMissing).
//! - NaN/Inf inputs → Rejected (fail-closed).
//! - Negative fee/slippage/min_edge → Rejected (fail-closed).
//! - Never panics on any input.

use super::{NetEdgeInput, NetEdgeMetrics, NetEdgeRejectReason, NetEdgeResult, evaluate_net_edge};
use proptest::prelude::*;

/// Generate a finite f64 for edge values.
fn finite_f64() -> impl Strategy<Value = f64> {
    prop::num::f64::NORMAL
}

/// Generate an optional f64 that is sometimes None.
fn optional_f64() -> impl Strategy<Value = Option<f64>> {
    prop_oneof![Just(None), finite_f64().prop_map(Some),]
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// When all inputs are present, positive, and net_edge >= min_edge,
    /// the result should be Allowed with correct net_edge identity.
    #[test]
    fn net_edge_identity_when_allowed(
        gross in (10.0_f64..1e4),
        fee in (0.0_f64..5.0),
        slippage in (0.0_f64..5.0),
        min_edge_fraction in (0.0_f64..0.5),
    ) {
        let net_edge_expected = gross - fee - slippage;
        // Derive min_edge as a fraction of net_edge to guarantee condition
        let min_edge = net_edge_expected * min_edge_fraction;
        prop_assume!(net_edge_expected.is_finite() && min_edge.is_finite() && min_edge >= 0.0);

        let input = NetEdgeInput {
            gross_edge_usd: Some(gross),
            fee_usd: Some(fee),
            expected_slippage_usd: Some(slippage),
            min_edge_usd: Some(min_edge),
        };
        let mut metrics = NetEdgeMetrics::new();
        let result = evaluate_net_edge(&input, &mut metrics);

        match result {
            NetEdgeResult::Allowed { net_edge_usd } => {
                let diff = (net_edge_usd - net_edge_expected).abs();
                prop_assert!(
                    diff < 1e-10,
                    "net_edge_usd={} != expected={} (gross={} - fee={} - slippage={})",
                    net_edge_usd,
                    net_edge_expected,
                    gross,
                    fee,
                    slippage
                );
            }
            NetEdgeResult::Rejected { reason, .. } => {
                prop_assert!(
                    false,
                    "expected Allowed but got Rejected({:?}) for gross={}, fee={}, slippage={}, min_edge={}",
                    reason,
                    gross,
                    fee,
                    slippage,
                    min_edge
                );
            }
        }
    }

    /// Any None field produces Rejected(NetEdgeInputMissing).
    #[test]
    fn missing_field_rejects(
        gross in optional_f64(),
        fee in optional_f64(),
        slippage in optional_f64(),
        min_edge in optional_f64(),
    ) {
        // At least one field must be None for this test
        prop_assume!(gross.is_none() || fee.is_none() || slippage.is_none() || min_edge.is_none());

        let input = NetEdgeInput {
            gross_edge_usd: gross,
            fee_usd: fee,
            expected_slippage_usd: slippage,
            min_edge_usd: min_edge,
        };
        let mut metrics = NetEdgeMetrics::new();
        let result = evaluate_net_edge(&input, &mut metrics);

        prop_assert!(
            matches!(result, NetEdgeResult::Rejected { reason: NetEdgeRejectReason::NetEdgeInputMissing, .. }),
            "expected NetEdgeInputMissing for input with None field, got {:?}",
            result
        );
    }

    /// NaN inputs produce rejection (fail-closed).
    #[test]
    fn nan_inputs_rejected(which_field in 0..4usize) {
        let mut input = NetEdgeInput {
            gross_edge_usd: Some(10.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(2.0),
        };
        match which_field {
            0 => input.gross_edge_usd = Some(f64::NAN),
            1 => input.fee_usd = Some(f64::NAN),
            2 => input.expected_slippage_usd = Some(f64::NAN),
            3 => input.min_edge_usd = Some(f64::NAN),
            _ => unreachable!(),
        }
        let mut metrics = NetEdgeMetrics::new();
        let result = evaluate_net_edge(&input, &mut metrics);

        prop_assert!(
            matches!(result, NetEdgeResult::Rejected { .. }),
            "expected rejection for NaN input in field {}, got {:?}",
            which_field,
            result
        );
    }

    /// Infinity inputs produce rejection (fail-closed).
    #[test]
    fn inf_inputs_rejected(
        which_field in 0..4usize,
        positive in proptest::bool::ANY,
    ) {
        let inf_val = if positive { f64::INFINITY } else { f64::NEG_INFINITY };
        let mut input = NetEdgeInput {
            gross_edge_usd: Some(10.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(2.0),
        };
        match which_field {
            0 => input.gross_edge_usd = Some(inf_val),
            1 => input.fee_usd = Some(inf_val),
            2 => input.expected_slippage_usd = Some(inf_val),
            3 => input.min_edge_usd = Some(inf_val),
            _ => unreachable!(),
        }
        let mut metrics = NetEdgeMetrics::new();
        let result = evaluate_net_edge(&input, &mut metrics);

        prop_assert!(
            matches!(result, NetEdgeResult::Rejected { .. }),
            "expected rejection for inf input in field {}, got {:?}",
            which_field,
            result
        );
    }

    /// Negative fee/slippage/min_edge produce rejection (fail-closed).
    #[test]
    fn negative_cost_fields_rejected(
        which_field in 1..4usize, // fee, slippage, min_edge
        neg_val in (-1e6_f64..-1e-10),
    ) {
        let mut input = NetEdgeInput {
            gross_edge_usd: Some(10.0),
            fee_usd: Some(1.0),
            expected_slippage_usd: Some(1.0),
            min_edge_usd: Some(2.0),
        };
        match which_field {
            1 => input.fee_usd = Some(neg_val),
            2 => input.expected_slippage_usd = Some(neg_val),
            3 => input.min_edge_usd = Some(neg_val),
            _ => unreachable!(),
        }
        let mut metrics = NetEdgeMetrics::new();
        let result = evaluate_net_edge(&input, &mut metrics);

        prop_assert!(
            matches!(result, NetEdgeResult::Rejected { .. }),
            "expected rejection for negative field {}, got {:?}",
            which_field,
            result
        );
    }

    /// Never panics on any combination of Option<f64> inputs.
    #[test]
    fn never_panics(
        gross in optional_f64(),
        fee in optional_f64(),
        slippage in optional_f64(),
        min_edge in optional_f64(),
    ) {
        let input = NetEdgeInput {
            gross_edge_usd: gross,
            fee_usd: fee,
            expected_slippage_usd: slippage,
            min_edge_usd: min_edge,
        };
        let mut metrics = NetEdgeMetrics::new();
        let _ = evaluate_net_edge(&input, &mut metrics);
    }
}
