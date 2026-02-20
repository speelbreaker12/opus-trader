//! Pending exposure reservation tests (S6.2, PX-2 per-instrument isolation).
//!
//! Contract targets:
//! - AT-225: concurrent OPEN reservations cannot overfill exposure budget.
//! - AT-910: over-budget reserve attempts reject with PendingExposureBudgetExceeded.
//! - §1.4.2.1: "Maintain `pending_delta` per instrument + global."
//! - S6 fail-closed expectation: invalid/missing budget input rejects before dispatch.

use soldier_core::risk::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome, ReservationId, RiskState,
};

/// Helper: create a book with one registered instrument.
fn make_book(instrument: &str, limit: f64) -> PendingExposureBook {
    let book = PendingExposureBook::new(None);
    book.register_instrument(instrument, Some(limit));
    book
}

const INST: &str = "BTC-PERPETUAL";

#[test]
fn test_pending_exposure_reservation_blocks_overfill() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);

    let mut accepted = 0;
    let mut rejected = 0;
    for i in 0..5 {
        // CRITICAL: Each iteration MUST use a unique ID. A fixed ID would silently
        // pass via idempotent replacement, masking the budget check. (AT-225)
        let rid = ReservationId::new(format!("r{i}")).unwrap();
        match book.reserve(&rid, INST, 0.0, 30.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => accepted += 1,
            PendingExposureResult::Rejected { reason, .. } => {
                assert_eq!(
                    reason,
                    PendingExposureRejectReason::PendingExposureBudgetExceeded
                );
                rejected += 1;
            }
        }
    }

    assert_eq!(accepted, 3, "only budget-fitting reservations may pass");
    assert_eq!(rejected, 2, "excess reservations must reject");
    // Defense against fixed-ID regression: if someone accidentally uses a fixed ID,
    // active_reservations will be 1 instead of 3. (AT-225)
    assert_eq!(book.active_reservations(INST), 3);
    assert!(
        (book.pending_total(INST) - 90.0).abs() < 1e-9,
        "pending_total must not overfill"
    );
    assert_eq!(metrics.reserve_reject_total(), 2);
}

#[test]
fn test_pending_exposure_release_on_terminal_restores_budget() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();

    let first = book.reserve(&r1, INST, 0.0, 70.0, &mut metrics);
    match first {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first reservation to pass, got {other:?}"),
    }

    let blocked = book.reserve(&r2, INST, 0.0, 40.0, &mut metrics);
    match blocked {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected overfill rejection, got {other:?}"),
    }

    let released = book.settle(
        &r1,
        INST,
        PendingExposureTerminalOutcome::Rejected,
        &mut metrics,
    );
    assert!(released, "terminal outcome should release the reservation");
    assert!((book.pending_total(INST) - 0.0).abs() < 1e-9);

    let second = book.reserve(&r2, INST, 0.0, 40.0, &mut metrics);
    match second {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected reservation after release to pass, got {other:?}"),
    }

    assert_eq!(metrics.release_total(), 1);
}

#[test]
fn test_pending_exposure_missing_budget_fails_closed() {
    let mut metrics = PendingExposureMetrics::new();
    let missing_budget = PendingExposureBook::new(None);
    missing_budget.register_instrument(INST, None);
    let zero_budget = PendingExposureBook::new(None);
    zero_budget.register_instrument(INST, Some(0.0));

    let rid = ReservationId::new("r1").unwrap();

    for book in [&missing_budget, &zero_budget] {
        let out = book.reserve(&rid, INST, 0.0, 5.0, &mut metrics);
        match out {
            PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                ..
            } => {}
            other => panic!("expected fail-closed rejection, got {other:?}"),
        }
    }
}

#[test]
fn test_pending_exposure_opposite_side_does_not_reopen_capacity() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();
    let r3 = ReservationId::new("r3").unwrap();

    let first = book.reserve(&r1, INST, 0.0, 100.0, &mut metrics);
    match first {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first +100 reservation to pass, got {other:?}"),
    }

    let second = book.reserve(&r2, INST, 0.0, -100.0, &mut metrics);
    match second {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected second -100 reservation to pass, got {other:?}"),
    }

    // Net pending is now zero, but worst-case long fill remains +100. Another +1 must reject.
    let third = book.reserve(&r3, INST, 0.0, 1.0, &mut metrics);
    match third {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected worst-case overfill rejection, got {other:?}"),
    }

    assert_eq!(book.pending_total(INST), 0.0);
    assert_eq!(metrics.reserve_success_total(), 2);
    assert_eq!(metrics.reserve_reject_total(), 1);
}

// ─── Idempotency tests ─────────────────────────────────────────────────

#[test]
fn test_idempotent_reserve_same_id_replaces_reservation() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("idem-1").unwrap();

    // First reserve: +50
    match book.reserve(&rid, INST, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 50.0).abs() < 1e-9);
        }
        other => panic!("expected first reserve success, got {other:?}"),
    }

    // Second reserve same ID: +30 (replaces +50)
    match book.reserve(&rid, INST, 0.0, 30.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 30.0).abs() < 1e-9);
        }
        other => panic!("expected idempotent re-reserve success, got {other:?}"),
    }

    assert_eq!(
        book.active_reservations(INST),
        1,
        "should still be one reservation"
    );
    assert_eq!(metrics.reserve_attempt_total(), 2);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 1);
    assert_eq!(metrics.reserve_success_total(), 2);
}

#[test]
fn test_idempotent_reserve_same_id_same_delta_is_noop() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("idem-2").unwrap();

    book.reserve(&rid, INST, 0.0, 50.0, &mut metrics);
    let before = book.pending_total(INST);

    book.reserve(&rid, INST, 0.0, 50.0, &mut metrics);
    let after = book.pending_total(INST);

    assert!(
        (before - after).abs() < 1e-12,
        "same delta re-reserve should be no-op"
    );
    assert_eq!(book.active_reservations(INST), 1);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 1);
}

#[test]
fn test_idempotent_reserve_cross_bucket_replacement() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("cross-bucket").unwrap();

    // Reserve +80 (positive bucket)
    match book.reserve(&rid, INST, 0.0, 80.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected reserve +80 success, got {other:?}"),
    }
    assert!((book.pending_total(INST) - 80.0).abs() < 1e-9);

    // Replace with -30 (moves to negative bucket)
    match book.reserve(&rid, INST, 0.0, -30.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - (-30.0)).abs() < 1e-9);
        }
        other => panic!("expected cross-bucket re-reserve success, got {other:?}"),
    }
    assert_eq!(book.active_reservations(INST), 1);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 1);
}

#[test]
fn test_idempotent_reserve_reject_preserves_old_reservation() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("fail-closed").unwrap();

    // Reserve +50
    match book.reserve(&rid, INST, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first reserve success, got {other:?}"),
    }

    // Try to re-reserve +200 (exceeds budget) — old +50 must stay.
    match book.reserve(&rid, INST, 0.0, 200.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            pending_total,
        } => {
            assert!(
                (pending_total - 50.0).abs() < 1e-9,
                "old reservation must be preserved"
            );
        }
        other => panic!("expected over-budget rejection, got {other:?}"),
    }

    assert_eq!(book.active_reservations(INST), 1, "old reservation stays");
    assert!((book.pending_total(INST) - 50.0).abs() < 1e-9);
}

#[test]
fn test_settle_double_settle_returns_false() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("double-settle").unwrap();

    book.reserve(&rid, INST, 0.0, 40.0, &mut metrics);

    let first = book.settle(
        &rid,
        INST,
        PendingExposureTerminalOutcome::Filled,
        &mut metrics,
    );
    assert!(first, "first settle should succeed");
    assert_eq!(metrics.release_total(), 1);

    let second = book.settle(
        &rid,
        INST,
        PendingExposureTerminalOutcome::Filled,
        &mut metrics,
    );
    assert!(!second, "second settle should return false");
    assert_eq!(metrics.release_total(), 1, "metrics counted once");
}

#[test]
fn test_settle_after_idempotent_rereserve_clears_to_zero() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("rereserve-settle").unwrap();

    // Reserve +50
    book.reserve(&rid, INST, 0.0, 50.0, &mut metrics);
    // Re-reserve +60
    book.reserve(&rid, INST, 0.0, 60.0, &mut metrics);

    assert!((book.pending_total(INST) - 60.0).abs() < 1e-9);

    // Settle → should clear to zero
    let released = book.settle(
        &rid,
        INST,
        PendingExposureTerminalOutcome::Filled,
        &mut metrics,
    );
    assert!(released);
    assert!(
        (book.pending_total(INST)).abs() < 1e-12,
        "must be exactly zero after settle"
    );
    assert_eq!(book.active_reservations(INST), 0);
}

#[test]
fn test_reserve_after_settle_works_as_fresh() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("fresh-after-settle").unwrap();

    // Reserve → settle
    book.reserve(&rid, INST, 0.0, 50.0, &mut metrics);
    book.settle(
        &rid,
        INST,
        PendingExposureTerminalOutcome::Rejected,
        &mut metrics,
    );
    assert_eq!(metrics.reserve_idempotent_hit_total(), 0);

    // Reserve same ID again → should be FRESH, not idempotent hit
    match book.reserve(&rid, INST, 0.0, 30.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 30.0).abs() < 1e-9);
        }
        other => panic!("expected fresh reserve after settle, got {other:?}"),
    }
    assert_eq!(
        metrics.reserve_idempotent_hit_total(),
        0,
        "reserve-after-settle must NOT count as idempotent hit"
    );
    assert_eq!(book.active_reservations(INST), 1);
}

#[test]
fn test_reserve_fails_closed_on_invalid_reservation_id() {
    // ReservationId::new returns None for invalid inputs
    assert!(ReservationId::new("").is_none(), "empty string");
    assert!(ReservationId::new("   ").is_none(), "whitespace-only");
    assert!(ReservationId::new("x".repeat(200)).is_none(), ">128 chars");
    assert!(ReservationId::new("\x00bad").is_none(), "control chars");
    assert!(
        ReservationId::new("valid-id-123").is_some(),
        "normal ID should work"
    );
}

#[test]
fn test_reserve_fails_closed_on_non_finite_inputs() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("non-finite").unwrap();

    // NaN current_delta
    match book.reserve(&rid, INST, f64::NAN, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NaN current_delta should reject, got {other:?}"),
    }

    // Infinity delta_impact_est
    match book.reserve(&rid, INST, 0.0, f64::INFINITY, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("Infinity delta_impact should reject, got {other:?}"),
    }

    // NaN delta_impact_est
    match book.reserve(&rid, INST, 0.0, f64::NAN, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NaN delta_impact should reject, got {other:?}"),
    }

    // Negative infinity current_delta
    match book.reserve(&rid, INST, f64::NEG_INFINITY, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NEG_INFINITY current_delta should reject, got {other:?}"),
    }

    assert_eq!(book.active_reservations(INST), 0, "no reservations created");
    assert_eq!(metrics.reserve_reject_total(), 4);
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `>` flipped to `>=` on budget check.
/// Exposure exactly at budget limit must be Allowed.
#[test]
fn test_pending_exposure_at_exact_budget_allowed() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 100.0);
    let rid = ReservationId::new("exact-budget").unwrap();

    // Reserve exactly 100.0 against a 100.0 budget — must be Allowed
    match book.reserve(&rid, INST, 0.0, 100.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!(
                (pending_total - 100.0).abs() < 1e-9,
                "pending_total should be 100.0, got {pending_total}"
            );
        }
        other => panic!("exposure == budget must ALLOW, got {other:?}"),
    }
    assert_eq!(metrics.reserve_success_total(), 1);
}

#[test]
fn test_negative_and_nan_budget_fails_closed() {
    let mut metrics = PendingExposureMetrics::new();
    let rid = ReservationId::new("budget-edge").unwrap();

    // All non-finite or non-positive instrument budgets must reject (fail-closed).
    let cases: Vec<(Option<f64>, &str)> = vec![
        (Some(-50.0), "negative budget"),
        (Some(f64::NAN), "NaN budget"),
        (Some(f64::NEG_INFINITY), "neg-infinity budget"),
        (Some(f64::INFINITY), "infinity budget"),
    ];

    for (budget, label) in &cases {
        let book = PendingExposureBook::new(None);
        book.register_instrument(INST, *budget);
        let out = book.reserve(&rid, INST, 0.0, 5.0, &mut metrics);
        match out {
            PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                ..
            } => {}
            other => panic!("{label}: expected rejection, got {other:?}"),
        }
    }
}

// ─── PX-2 per-instrument isolation tests ────────────────────────────

#[test]
fn test_per_instrument_isolation_independent_budgets() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(50.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    // BTC reserve +90 — within BTC's 100 budget
    match book.reserve(&r1, "BTC", 0.0, 90.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("BTC reserve should pass, got {other:?}"),
    }

    // ETH reserve +40 — within ETH's 50 budget (BTC's usage doesn't affect ETH)
    match book.reserve(&r2, "ETH", 0.0, 40.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("ETH reserve should pass independently, got {other:?}"),
    }

    assert!((book.pending_total("BTC") - 90.0).abs() < 1e-9);
    assert!((book.pending_total("ETH") - 40.0).abs() < 1e-9);
    assert_eq!(book.active_reservations("BTC"), 1);
    assert_eq!(book.active_reservations("ETH"), 1);
    assert!((book.global_pending_total() - 130.0).abs() < 1e-9);
    assert_eq!(book.global_active_reservations(), 2);
}

#[test]
fn test_global_budget_enforced_across_instruments() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0)); // global limit
    book.register_instrument("BTC", Some(200.0)); // generous per-instrument
    book.register_instrument("ETH", Some(200.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    // BTC +60 — within both per-instrument (200) and global (100)
    match book.reserve(&r1, "BTC", 0.0, 60.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("BTC reserve should pass, got {other:?}"),
    }

    // ETH +50 — within per-instrument (200) but would exceed global (60+50=110 > 100)
    match book.reserve(&r2, "ETH", 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("ETH should be rejected by global budget, got {other:?}"),
    }

    assert_eq!(book.active_reservations("BTC"), 1);
    assert_eq!(book.active_reservations("ETH"), 0);
    assert!((book.global_pending_total() - 60.0).abs() < 1e-9);
}

#[test]
fn test_global_delta_limit_none_allows_unlimited_cross_instrument() {
    // Explicit coverage: global_delta_limit: None means no cross-instrument ceiling.
    // Two instruments each at 90% of their per-instrument limit = global total 180,
    // which would exceed any reasonable global limit — but passes because there is none.
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None); // no global limit
    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(100.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    // BTC +90 — within per-instrument limit
    match book.reserve(&r1, "BTC", 0.0, 90.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("BTC reserve should pass, got {other:?}"),
    }

    // ETH +90 — within per-instrument limit, no global cap to block it
    match book.reserve(&r2, "ETH", 0.0, 90.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("ETH reserve should pass without global cap, got {other:?}"),
    }

    assert!((book.global_pending_total() - 180.0).abs() < 1e-9);
    assert_eq!(book.global_active_reservations(), 2);
    assert_eq!(metrics.reserve_success_total(), 2);
    assert_eq!(metrics.reserve_reject_total(), 0);
}

#[test]
fn test_global_delta_limit_nan_normalized_to_none() {
    // global_delta_limit is normalized at construction — NaN becomes None.
    let book = PendingExposureBook::new(Some(f64::NAN));
    let mut metrics = PendingExposureMetrics::new();
    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(100.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    // Both should pass — NaN global limit is normalized to None (no global cap)
    match book.reserve(&r1, "BTC", 0.0, 90.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("BTC should pass with NaN global (normalized to None), got {other:?}"),
    }
    match book.reserve(&r2, "ETH", 0.0, 90.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("ETH should pass with NaN global (normalized to None), got {other:?}"),
    }

    assert!((book.global_pending_total() - 180.0).abs() < 1e-9);
}

#[test]
fn test_unregistered_instrument_rejected() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    // No instruments registered

    let rid = ReservationId::new("orphan").unwrap();
    match book.reserve(&rid, "UNKNOWN-INST", 0.0, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::InstrumentNotRegistered,
            pending_total,
        } => {
            assert!(
                pending_total.is_nan(),
                "InstrumentNotRegistered returns NAN"
            );
        }
        other => panic!("unregistered instrument should reject, got {other:?}"),
    }
    assert_eq!(metrics.reserve_instrument_not_registered_total(), 1);
    assert_eq!(
        metrics.reserve_reject_total(),
        0,
        "not counted as budget reject"
    );
}

#[test]
fn test_cross_instrument_reservation_id_collision_rejected() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(100.0));

    let rid = ReservationId::new("shared-id").unwrap();

    // Reserve on BTC first
    match book.reserve(&rid, "BTC", 0.0, 10.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("BTC reserve should pass, got {other:?}"),
    }

    // Try same ID on ETH — must reject (cross-instrument collision)
    match book.reserve(&rid, "ETH", 0.0, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("cross-instrument collision should reject, got {other:?}"),
    }

    // BTC reservation still intact
    assert_eq!(book.active_reservations("BTC"), 1);
    assert_eq!(book.active_reservations("ETH"), 0);
}

#[test]
fn test_settle_authoritative_routing() {
    // settle() uses the reverse lookup as authoritative — even if caller passes wrong instrument,
    // settlement happens on the canonical instrument to prevent budget leaks.
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(100.0));

    let rid = ReservationId::new("auth-route").unwrap();
    book.reserve(&rid, "BTC", 0.0, 50.0, &mut metrics);

    // Settle with wrong instrument — should still work (authoritative routing)
    let released = book.settle(
        &rid,
        "ETH", // wrong — but reverse lookup says BTC
        PendingExposureTerminalOutcome::Filled,
        &mut metrics,
    );
    assert!(released, "settle should succeed via authoritative routing");
    assert_eq!(
        book.active_reservations("BTC"),
        0,
        "BTC reservation cleared"
    );
    assert!((book.pending_total("BTC")).abs() < 1e-12);
    assert!((book.global_pending_total()).abs() < 1e-12);
}

#[test]
fn test_per_instrument_settle_clears_only_own_instrument() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(200.0));
    book.register_instrument("ETH", Some(200.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    book.reserve(&r1, "BTC", 0.0, 50.0, &mut metrics);
    book.reserve(&r2, "ETH", 0.0, 30.0, &mut metrics);
    assert!((book.global_pending_total() - 80.0).abs() < 1e-9);

    // Settle BTC only
    book.settle(
        &r1,
        "BTC",
        PendingExposureTerminalOutcome::Filled,
        &mut metrics,
    );

    assert_eq!(book.active_reservations("BTC"), 0);
    assert_eq!(book.active_reservations("ETH"), 1);
    assert!((book.pending_total("BTC")).abs() < 1e-12);
    assert!((book.pending_total("ETH") - 30.0).abs() < 1e-9);
    assert!((book.global_pending_total() - 30.0).abs() < 1e-9);
}

#[test]
fn test_register_instrument_count_and_delta_limit_accessor() {
    let book = PendingExposureBook::new(Some(500.0));
    assert_eq!(book.registered_instrument_count(), 0);

    book.register_instrument("BTC", Some(100.0));
    book.register_instrument("ETH", Some(50.0));
    assert_eq!(book.registered_instrument_count(), 2);

    // instrument_delta_limit returns Some(Some(limit)) for registered
    assert_eq!(book.instrument_delta_limit("BTC"), Some(Some(100.0)));
    assert_eq!(book.instrument_delta_limit("ETH"), Some(Some(50.0)));
    // Returns None for unregistered
    assert_eq!(book.instrument_delta_limit("SOL"), None);
}

#[test]
fn test_global_pending_total_tracks_across_instruments() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(200.0));
    book.register_instrument("ETH", Some(200.0));
    book.register_instrument("SOL", Some(200.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();
    let r3 = ReservationId::new("sol-1").unwrap();

    book.reserve(&r1, "BTC", 0.0, 50.0, &mut metrics);
    book.reserve(&r2, "ETH", 0.0, -20.0, &mut metrics);
    book.reserve(&r3, "SOL", 0.0, 30.0, &mut metrics);

    assert!((book.global_pending_total() - 60.0).abs() < 1e-9);
    assert_eq!(book.global_active_reservations(), 3);

    // Settle one
    book.settle(
        &r2,
        "ETH",
        PendingExposureTerminalOutcome::Canceled,
        &mut metrics,
    );
    assert!((book.global_pending_total() - 80.0).abs() < 1e-9);
    assert_eq!(book.global_active_reservations(), 2);
}

#[test]
fn test_register_instrument_config_reload_updates_limit() {
    // P2 #5: Calling register_instrument twice overwrites limit, preserves reservations.
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument(INST, Some(100.0));

    let r1 = ReservationId::new("r1").unwrap();
    match book.reserve(&r1, INST, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected success, got {other:?}"),
    }

    // Shrink limit below current reservation — new reserves should be blocked.
    book.register_instrument(INST, Some(30.0));
    assert_eq!(book.instrument_delta_limit(INST), Some(Some(30.0)));
    assert_eq!(
        book.active_reservations(INST),
        1,
        "existing reservation preserved"
    );

    let r2 = ReservationId::new("r2").unwrap();
    match book.reserve(&r2, INST, 0.0, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("should reject under new limit, got {other:?}"),
    }

    // Expand limit — reserves should work again.
    book.register_instrument(INST, Some(200.0));
    match book.reserve(&r2, INST, 0.0, 10.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("should pass under expanded limit, got {other:?}"),
    }
}

#[test]
fn test_register_instrument_nan_and_infinity_limits_are_fail_closed() {
    // P2 #5: NaN and Infinity delta_limits are treated as invalid (fail-closed at reserve time).
    let mut metrics = PendingExposureMetrics::new();

    // NaN limit — normalized to None at registration
    let book_nan = PendingExposureBook::new(None);
    book_nan.register_instrument(INST, Some(f64::NAN));
    assert_eq!(
        book_nan.instrument_delta_limit(INST),
        Some(None),
        "NaN should be normalized to None at registration"
    );
    let r1 = ReservationId::new("r1").unwrap();
    match book_nan.reserve(&r1, INST, 0.0, 1.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NaN limit should fail-closed, got {other:?}"),
    }

    // Infinity limit — normalized to None at registration
    let book_inf = PendingExposureBook::new(None);
    book_inf.register_instrument(INST, Some(f64::INFINITY));
    assert_eq!(
        book_inf.instrument_delta_limit(INST),
        Some(None),
        "Infinity should be normalized to None at registration"
    );
    let r2 = ReservationId::new("r2").unwrap();
    match book_inf.reserve(&r2, INST, 0.0, 1.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("Infinity limit should fail-closed, got {other:?}"),
    }

    // None limit (explicit None)
    let book_none = PendingExposureBook::new(None);
    book_none.register_instrument(INST, None);
    assert_eq!(
        book_none.instrument_delta_limit(INST),
        Some(None),
        "None stays None"
    );
    let r3 = ReservationId::new("r3").unwrap();
    match book_none.reserve(&r3, INST, 0.0, 1.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("None limit should fail-closed, got {other:?}"),
    }

    // Zero limit — normalized to None at registration
    let book_zero = PendingExposureBook::new(None);
    book_zero.register_instrument(INST, Some(0.0));
    assert_eq!(
        book_zero.instrument_delta_limit(INST),
        Some(None),
        "zero should be normalized to None at registration"
    );
    let r4 = ReservationId::new("r4").unwrap();
    match book_zero.reserve(&r4, INST, 0.0, 1.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("zero limit should fail-closed, got {other:?}"),
    }
}

// ─── PX-4 drain_all tests ────────────────────────────────────────────

#[test]
fn test_drain_all_clears_single_instrument() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 1000.0);

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();
    let r3 = ReservationId::new("r3").unwrap();

    book.reserve(&r1, INST, 0.0, 10.0, &mut metrics);
    book.reserve(&r2, INST, 0.0, 20.0, &mut metrics);
    book.reserve(&r3, INST, 0.0, -5.0, &mut metrics);

    let cleared = book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(cleared, 3, "should clear all 3 reservations");
    assert!(
        (book.pending_total(INST)).abs() < 1e-12,
        "pending must be zero"
    );
    assert_eq!(book.active_reservations(INST), 0);
    assert!(
        (book.global_pending_total()).abs() < 1e-12,
        "global must be zero"
    );
    assert_eq!(metrics.drain_call_total(), 1);
    assert_eq!(metrics.drain_reservations_cleared_total(), 3);
}

#[test]
fn test_drain_all_clears_multi_instrument() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(None);
    book.register_instrument("BTC", Some(500.0));
    book.register_instrument("ETH", Some(500.0));
    book.register_instrument("SOL", Some(500.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("btc-2").unwrap();
    let r3 = ReservationId::new("eth-1").unwrap();
    let r4 = ReservationId::new("sol-1").unwrap();
    let r5 = ReservationId::new("sol-2").unwrap();

    book.reserve(&r1, "BTC", 0.0, 50.0, &mut metrics);
    book.reserve(&r2, "BTC", 0.0, -20.0, &mut metrics);
    book.reserve(&r3, "ETH", 0.0, 30.0, &mut metrics);
    book.reserve(&r4, "SOL", 0.0, 10.0, &mut metrics);
    book.reserve(&r5, "SOL", 0.0, 15.0, &mut metrics);

    let cleared = book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(
        cleared, 5,
        "should clear all 5 reservations across 3 instruments"
    );
    assert!((book.pending_total("BTC")).abs() < 1e-12);
    assert!((book.pending_total("ETH")).abs() < 1e-12);
    assert!((book.pending_total("SOL")).abs() < 1e-12);
    assert_eq!(book.active_reservations("BTC"), 0);
    assert_eq!(book.active_reservations("ETH"), 0);
    assert_eq!(book.active_reservations("SOL"), 0);
    assert!((book.global_pending_total()).abs() < 1e-12);
    assert_eq!(book.global_active_reservations(), 0);
    assert_eq!(metrics.drain_call_total(), 1);
    assert_eq!(metrics.drain_reservations_cleared_total(), 5);
}

#[test]
fn test_drain_all_idempotent() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 1000.0);

    let r1 = ReservationId::new("r1").unwrap();
    book.reserve(&r1, INST, 0.0, 42.0, &mut metrics);

    let first = book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(first, 1);

    let second = book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(second, 0, "second drain should return 0 — nothing left");

    assert_eq!(metrics.drain_call_total(), 2, "both calls counted");
    assert_eq!(
        metrics.drain_reservations_cleared_total(),
        1,
        "only first drain cleared anything"
    );
}

#[test]
fn test_drain_all_allows_fresh_reserves_after() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 1000.0);

    let r1 = ReservationId::new("r1").unwrap();
    book.reserve(&r1, INST, 0.0, 100.0, &mut metrics);

    book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(book.active_reservations(INST), 0);

    // Fresh reserve after drain should work
    let r2 = ReservationId::new("r2").unwrap();
    match book.reserve(&r2, INST, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 50.0).abs() < 1e-9);
        }
        other => panic!("fresh reserve after drain should succeed, got {other:?}"),
    }
    assert_eq!(book.active_reservations(INST), 1);
    assert!((book.global_pending_total() - 50.0).abs() < 1e-9);
}

#[test]
fn test_drain_all_with_global_delta_limit_reclaims_budget() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(500.0));
    book.register_instrument("BTC", Some(300.0));
    book.register_instrument("ETH", Some(300.0));

    let r1 = ReservationId::new("btc-1").unwrap();
    let r2 = ReservationId::new("eth-1").unwrap();

    // Fill near global limit
    book.reserve(&r1, "BTC", 0.0, 250.0, &mut metrics);
    book.reserve(&r2, "ETH", 0.0, 200.0, &mut metrics);
    assert!((book.global_pending_total() - 450.0).abs() < 1e-9);

    // Drain clears everything
    let cleared = book.drain_all(RiskState::Kill, &mut metrics);
    assert_eq!(cleared, 2);
    assert!((book.global_pending_total()).abs() < 1e-12);

    // Fresh reserve succeeds — global budget fully reclaimed
    let r3 = ReservationId::new("btc-2").unwrap();
    match book.reserve(&r3, "BTC", 0.0, 250.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 250.0).abs() < 1e-9);
        }
        other => panic!("reserve after drain should succeed with reclaimed global budget, got {other:?}"),
    }
}

#[test]
fn test_drain_all_rejected_outside_kill_state() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 1000.0);

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();
    book.reserve(&r1, INST, 0.0, 50.0, &mut metrics);
    book.reserve(&r2, INST, 0.0, 30.0, &mut metrics);

    // Drain with Healthy state — must be rejected
    let cleared = book.drain_all(RiskState::Healthy, &mut metrics);
    assert_eq!(cleared, 0, "drain outside Kill must return 0");
    assert_eq!(
        book.active_reservations(INST),
        2,
        "reservations must be intact"
    );
    assert!(
        (book.pending_total(INST) - 80.0).abs() < 1e-9,
        "pending must be unchanged"
    );
    assert!((book.global_pending_total() - 80.0).abs() < 1e-9);

    // Also check Degraded and Maintenance
    assert_eq!(book.drain_all(RiskState::Degraded, &mut metrics), 0);
    assert_eq!(book.drain_all(RiskState::Maintenance, &mut metrics), 0);
    assert_eq!(
        book.active_reservations(INST),
        2,
        "still intact after Degraded/Maintenance"
    );

    // Metrics: all 3 rejected calls counted, zero reservations cleared
    assert_eq!(
        metrics.drain_call_total(),
        3,
        "all rejected drain calls must be counted"
    );
    assert_eq!(
        metrics.drain_reservations_cleared_total(),
        0,
        "no reservations cleared on rejected drains"
    );
}

#[test]
fn test_drain_all_post_drain_settle_returns_false() {
    let mut metrics = PendingExposureMetrics::new();
    let book = make_book(INST, 1000.0);

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();

    book.reserve(&r1, INST, 0.0, 50.0, &mut metrics);
    book.reserve(&r2, INST, 0.0, 30.0, &mut metrics);

    book.drain_all(RiskState::Kill, &mut metrics);

    // Post-drain settle: reservation no longer exists — returns false (benign)
    let settled = book.settle(
        &r1,
        INST,
        PendingExposureTerminalOutcome::Failed,
        &mut metrics,
    );
    assert!(!settled, "settle after drain must return false");

    let settled2 = book.settle(
        &r2,
        INST,
        PendingExposureTerminalOutcome::Canceled,
        &mut metrics,
    );
    assert!(!settled2, "settle after drain must return false");

    // Budget stays at zero — failed settles are budget-neutral
    assert!(
        (book.pending_total(INST)).abs() < 1e-12,
        "pending must remain zero after failed settles"
    );
    assert!(
        (book.global_pending_total()).abs() < 1e-12,
        "global must remain zero after failed settles"
    );
    assert_eq!(
        metrics.release_total(),
        0,
        "failed settles do not increment release_total"
    );
}
