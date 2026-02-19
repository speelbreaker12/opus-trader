//! Pending exposure reservation tests (S6.2).
//!
//! Contract targets:
//! - AT-225: concurrent OPEN reservations cannot overfill exposure budget.
//! - AT-910: over-budget reserve attempts reject with PendingExposureBudgetExceeded.
//! - S6 fail-closed expectation: invalid/missing budget input rejects before dispatch.

use soldier_core::risk::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome, ReservationId,
};

#[test]
fn test_pending_exposure_reservation_blocks_overfill() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));

    let mut accepted = 0;
    let mut rejected = 0;
    for i in 0..5 {
        // CRITICAL: Each iteration MUST use a unique ID. A fixed ID would silently
        // pass via idempotent replacement, masking the budget check. (AT-225)
        let rid = ReservationId::new(format!("r{i}")).unwrap();
        match book.reserve(&rid, 0.0, 30.0, &mut metrics) {
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
    assert_eq!(book.active_reservations(), 3);
    assert!(
        (book.pending_total() - 90.0).abs() < 1e-9,
        "pending_total must not overfill"
    );
    assert_eq!(metrics.reserve_reject_total(), 2);
}

#[test]
fn test_pending_exposure_release_on_terminal_restores_budget() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();

    let first = book.reserve(&r1, 0.0, 70.0, &mut metrics);
    match first {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first reservation to pass, got {other:?}"),
    }

    let blocked = book.reserve(&r2, 0.0, 40.0, &mut metrics);
    match blocked {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected overfill rejection, got {other:?}"),
    }

    let released = book.settle(&r1, PendingExposureTerminalOutcome::Rejected, &mut metrics);
    assert!(released, "terminal outcome should release the reservation");
    assert!((book.pending_total() - 0.0).abs() < 1e-9);

    let second = book.reserve(&r2, 0.0, 40.0, &mut metrics);
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
    let zero_budget = PendingExposureBook::new(Some(0.0));

    let rid = ReservationId::new("r1").unwrap();

    for book in [&missing_budget, &zero_budget] {
        let out = book.reserve(&rid, 0.0, 5.0, &mut metrics);
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
    let book = PendingExposureBook::new(Some(100.0));

    let r1 = ReservationId::new("r1").unwrap();
    let r2 = ReservationId::new("r2").unwrap();
    let r3 = ReservationId::new("r3").unwrap();

    let first = book.reserve(&r1, 0.0, 100.0, &mut metrics);
    match first {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first +100 reservation to pass, got {other:?}"),
    }

    let second = book.reserve(&r2, 0.0, -100.0, &mut metrics);
    match second {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected second -100 reservation to pass, got {other:?}"),
    }

    // Net pending is now zero, but worst-case long fill remains +100. Another +1 must reject.
    let third = book.reserve(&r3, 0.0, 1.0, &mut metrics);
    match third {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected worst-case overfill rejection, got {other:?}"),
    }

    assert_eq!(book.pending_total(), 0.0);
    assert_eq!(metrics.reserve_success_total(), 2);
    assert_eq!(metrics.reserve_reject_total(), 1);
}

// ─── New idempotency tests ───────────────────────────────────────────────

#[test]
fn test_idempotent_reserve_same_id_replaces_reservation() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("idem-1").unwrap();

    // First reserve: +50
    match book.reserve(&rid, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 50.0).abs() < 1e-9);
        }
        other => panic!("expected first reserve success, got {other:?}"),
    }

    // Second reserve same ID: +30 (replaces +50)
    match book.reserve(&rid, 0.0, 30.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - 30.0).abs() < 1e-9);
        }
        other => panic!("expected idempotent re-reserve success, got {other:?}"),
    }

    assert_eq!(
        book.active_reservations(),
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
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("idem-2").unwrap();

    book.reserve(&rid, 0.0, 50.0, &mut metrics);
    let before = book.pending_total();

    book.reserve(&rid, 0.0, 50.0, &mut metrics);
    let after = book.pending_total();

    assert!(
        (before - after).abs() < 1e-12,
        "same delta re-reserve should be no-op"
    );
    assert_eq!(book.active_reservations(), 1);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 1);
}

#[test]
fn test_idempotent_reserve_cross_bucket_replacement() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("cross-bucket").unwrap();

    // Reserve +80 (positive bucket)
    match book.reserve(&rid, 0.0, 80.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected reserve +80 success, got {other:?}"),
    }
    assert!((book.pending_total() - 80.0).abs() < 1e-9);

    // Replace with -30 (moves to negative bucket)
    match book.reserve(&rid, 0.0, -30.0, &mut metrics) {
        PendingExposureResult::Reserved { pending_total, .. } => {
            assert!((pending_total - (-30.0)).abs() < 1e-9);
        }
        other => panic!("expected cross-bucket re-reserve success, got {other:?}"),
    }
    assert_eq!(book.active_reservations(), 1);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 1);
}

#[test]
fn test_idempotent_reserve_reject_preserves_old_reservation() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("fail-closed").unwrap();

    // Reserve +50
    match book.reserve(&rid, 0.0, 50.0, &mut metrics) {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first reserve success, got {other:?}"),
    }

    // Try to re-reserve +200 (exceeds budget) — old +50 must stay.
    match book.reserve(&rid, 0.0, 200.0, &mut metrics) {
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

    assert_eq!(book.active_reservations(), 1, "old reservation stays");
    assert!((book.pending_total() - 50.0).abs() < 1e-9);
}

#[test]
fn test_settle_double_settle_returns_false() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("double-settle").unwrap();

    book.reserve(&rid, 0.0, 40.0, &mut metrics);

    let first = book.settle(&rid, PendingExposureTerminalOutcome::Filled, &mut metrics);
    assert!(first, "first settle should succeed");
    assert_eq!(metrics.release_total(), 1);

    let second = book.settle(&rid, PendingExposureTerminalOutcome::Filled, &mut metrics);
    assert!(!second, "second settle should return false");
    assert_eq!(metrics.release_total(), 1, "metrics counted once");
}

#[test]
fn test_settle_after_idempotent_rereserve_clears_to_zero() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("rereserve-settle").unwrap();

    // Reserve +50
    book.reserve(&rid, 0.0, 50.0, &mut metrics);
    // Re-reserve +60
    book.reserve(&rid, 0.0, 60.0, &mut metrics);

    assert!((book.pending_total() - 60.0).abs() < 1e-9);

    // Settle → should clear to zero
    let released = book.settle(&rid, PendingExposureTerminalOutcome::Filled, &mut metrics);
    assert!(released);
    assert!(
        (book.pending_total()).abs() < 1e-12,
        "must be exactly zero after settle"
    );
    assert_eq!(book.active_reservations(), 0);
}

#[test]
fn test_reserve_after_settle_works_as_fresh() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("fresh-after-settle").unwrap();

    // Reserve → settle
    book.reserve(&rid, 0.0, 50.0, &mut metrics);
    book.settle(&rid, PendingExposureTerminalOutcome::Rejected, &mut metrics);
    assert_eq!(metrics.reserve_idempotent_hit_total(), 0);

    // Reserve same ID again → should be FRESH, not idempotent hit
    match book.reserve(&rid, 0.0, 30.0, &mut metrics) {
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
    assert_eq!(book.active_reservations(), 1);
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
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("non-finite").unwrap();

    // NaN current_delta
    match book.reserve(&rid, f64::NAN, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NaN current_delta should reject, got {other:?}"),
    }

    // Infinity delta_impact_est
    match book.reserve(&rid, 0.0, f64::INFINITY, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("Infinity delta_impact should reject, got {other:?}"),
    }

    // NaN delta_impact_est
    match book.reserve(&rid, 0.0, f64::NAN, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NaN delta_impact should reject, got {other:?}"),
    }

    // Negative infinity current_delta
    match book.reserve(&rid, f64::NEG_INFINITY, 10.0, &mut metrics) {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("NEG_INFINITY current_delta should reject, got {other:?}"),
    }

    assert_eq!(book.active_reservations(), 0, "no reservations created");
    assert_eq!(metrics.reserve_reject_total(), 4);
}

// ─── Devils-advocate: boundary mutations ─────────────────────────────

/// Catches mutation: `>` flipped to `>=` on budget check.
/// Exposure exactly at budget limit must be Allowed.
#[test]
fn test_pending_exposure_at_exact_budget_allowed() {
    let mut metrics = PendingExposureMetrics::new();
    let book = PendingExposureBook::new(Some(100.0));
    let rid = ReservationId::new("exact-budget").unwrap();

    // Reserve exactly 100.0 against a 100.0 budget — must be Allowed
    match book.reserve(&rid, 0.0, 100.0, &mut metrics) {
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

    // All non-finite or non-positive budgets must reject (fail-closed).
    let cases: Vec<(Option<f64>, &str)> = vec![
        (Some(-50.0), "negative budget"),
        (Some(f64::NAN), "NaN budget"),
        (Some(f64::NEG_INFINITY), "neg-infinity budget"),
        (Some(f64::INFINITY), "infinity budget"),
    ];

    for (budget, label) in &cases {
        let book = PendingExposureBook::new(*budget);
        let out = book.reserve(&rid, 0.0, 5.0, &mut metrics);
        match out {
            PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                ..
            } => {}
            other => panic!("{label}: expected rejection, got {other:?}"),
        }
    }
}
