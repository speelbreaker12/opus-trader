//! Pending exposure reservation tests (S6.2).
//!
//! Contract targets:
//! - AT-225: concurrent OPEN reservations cannot overfill exposure budget.
//! - AT-910: over-budget reserve attempts reject with PendingExposureBudgetExceeded.
//! - S6 fail-closed expectation: invalid/missing budget input rejects before dispatch.

use soldier_core::risk::{
    PendingExposureBook, PendingExposureMetrics, PendingExposureRejectReason,
    PendingExposureResult, PendingExposureTerminalOutcome,
};

#[test]
fn test_pending_exposure_reservation_blocks_overfill() {
    let mut metrics = PendingExposureMetrics::new();
    let mut book = PendingExposureBook::new(Some(100.0));

    let mut accepted = 0;
    let mut rejected = 0;
    for _ in 0..5 {
        match book.reserve(0.0, 30.0, &mut metrics) {
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
    assert!(
        (book.pending_total() - 90.0).abs() < 1e-9,
        "pending_total must not overfill"
    );
    assert_eq!(metrics.reserve_reject_total(), 2);
}

#[test]
fn test_pending_exposure_release_on_terminal_restores_budget() {
    let mut metrics = PendingExposureMetrics::new();
    let mut book = PendingExposureBook::new(Some(100.0));

    let first = book.reserve(0.0, 70.0, &mut metrics);
    let first_id = match first {
        PendingExposureResult::Reserved { reservation_id, .. } => reservation_id,
        other => panic!("expected first reservation to pass, got {other:?}"),
    };

    let blocked = book.reserve(0.0, 40.0, &mut metrics);
    match blocked {
        PendingExposureResult::Rejected {
            reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
            ..
        } => {}
        other => panic!("expected overfill rejection, got {other:?}"),
    }

    let released = book.settle(
        first_id,
        PendingExposureTerminalOutcome::Rejected,
        &mut metrics,
    );
    assert!(released, "terminal outcome should release the reservation");
    assert!((book.pending_total() - 0.0).abs() < 1e-9);

    let second = book.reserve(0.0, 40.0, &mut metrics);
    match second {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected reservation after release to pass, got {other:?}"),
    }

    assert_eq!(metrics.release_total(), 1);
}

#[test]
fn test_pending_exposure_missing_budget_fails_closed() {
    let mut metrics = PendingExposureMetrics::new();
    let mut missing_budget = PendingExposureBook::new(None);
    let mut zero_budget = PendingExposureBook::new(Some(0.0));

    for book in [&mut missing_budget, &mut zero_budget] {
        let out = book.reserve(0.0, 5.0, &mut metrics);
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
    let mut book = PendingExposureBook::new(Some(100.0));

    let first = book.reserve(0.0, 100.0, &mut metrics);
    match first {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected first +100 reservation to pass, got {other:?}"),
    }

    let second = book.reserve(0.0, -100.0, &mut metrics);
    match second {
        PendingExposureResult::Reserved { .. } => {}
        other => panic!("expected second -100 reservation to pass, got {other:?}"),
    }

    // Net pending is now zero, but worst-case long fill remains +100. Another +1 must reject.
    let third = book.reserve(0.0, 1.0, &mut metrics);
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
