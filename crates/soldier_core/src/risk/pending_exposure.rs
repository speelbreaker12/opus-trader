//! Pending exposure reservation (S6.2, anti over-fill).
//!
//! Contract mapping:
//! - §1.4.2.1: reserve before dispatch; reject if reservation breaches budget.
//! - AT-225: concurrent reserves must not overfill budget.
//! - AT-910: over-budget reserve rejects with PendingExposureBudgetExceeded.

use std::collections::BTreeMap;

/// Rejection reasons for pending exposure reservation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingExposureRejectReason {
    /// Reservation would breach budget, or budget input is invalid (fail-closed).
    PendingExposureBudgetExceeded,
}

/// Reservation attempt outcome.
#[derive(Debug, Clone, PartialEq)]
pub enum PendingExposureResult {
    Reserved {
        reservation_id: u64,
        pending_total: f64,
    },
    Rejected {
        reason: PendingExposureRejectReason,
        pending_total: f64,
    },
}

/// Terminal outcome used to release reservation.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PendingExposureTerminalOutcome {
    Filled,
    Rejected,
    Canceled,
    Failed,
}

/// Observability counters for pending exposure.
#[derive(Debug, Default)]
pub struct PendingExposureMetrics {
    reserve_attempt_total: u64,
    reserve_success_total: u64,
    reserve_reject_total: u64,
    release_total: u64,
}

impl PendingExposureMetrics {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn reserve_attempt_total(&self) -> u64 {
        self.reserve_attempt_total
    }

    pub fn reserve_success_total(&self) -> u64 {
        self.reserve_success_total
    }

    pub fn reserve_reject_total(&self) -> u64 {
        self.reserve_reject_total
    }

    pub fn release_total(&self) -> u64 {
        self.release_total
    }

    fn record_reserve_success(&mut self) {
        self.reserve_attempt_total += 1;
        self.reserve_success_total += 1;
    }

    fn record_reserve_reject(&mut self) {
        self.reserve_attempt_total += 1;
        self.reserve_reject_total += 1;
    }

    fn record_release(&mut self) {
        self.release_total += 1;
    }
}

/// In-memory reservation book keyed by reservation id.
#[derive(Debug, Default)]
pub struct PendingExposureBook {
    delta_limit: Option<f64>,
    pending_total: f64,
    pending_positive: f64,
    pending_negative: f64,
    next_reservation_id: u64,
    reservations: BTreeMap<u64, f64>,
}

impl PendingExposureBook {
    /// Construct a reservation book.
    ///
    /// `delta_limit` is absolute budget enforced against worst-case pending outcomes.
    /// Missing/invalid value is fail-closed at reserve time.
    pub fn new(delta_limit: Option<f64>) -> Self {
        Self {
            delta_limit,
            pending_total: 0.0,
            pending_positive: 0.0,
            pending_negative: 0.0,
            next_reservation_id: 1,
            reservations: BTreeMap::new(),
        }
    }

    pub fn pending_total(&self) -> f64 {
        self.pending_total
    }

    pub fn active_reservations(&self) -> usize {
        self.reservations.len()
    }

    /// Reserve projected delta impact before dispatch.
    ///
    /// Fail-closed behavior:
    /// - invalid/missing `delta_limit`
    /// - non-finite inputs
    pub fn reserve(
        &mut self,
        current_delta: f64,
        delta_impact_est: f64,
        metrics: &mut PendingExposureMetrics,
    ) -> PendingExposureResult {
        let Some(limit) = normalized_limit(self.delta_limit) else {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: self.pending_total,
            };
        };

        if !current_delta.is_finite()
            || !delta_impact_est.is_finite()
            || !self.pending_total.is_finite()
            || !self.pending_positive.is_finite()
            || !self.pending_negative.is_finite()
        {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: self.pending_total,
            };
        }

        let projected_positive = if delta_impact_est >= 0.0 {
            self.pending_positive + delta_impact_est
        } else {
            self.pending_positive
        };
        let projected_negative = if delta_impact_est < 0.0 {
            self.pending_negative + delta_impact_est
        } else {
            self.pending_negative
        };
        let worst_case_long = current_delta + projected_positive;
        let worst_case_short = current_delta + projected_negative;
        if worst_case_long.abs() > limit || worst_case_short.abs() > limit {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: self.pending_total,
            };
        }

        let Some(next_reservation_id) = self.next_reservation_id.checked_add(1) else {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: self.pending_total,
            };
        };

        let reservation_id = self.next_reservation_id;
        self.next_reservation_id = next_reservation_id;
        self.reservations.insert(reservation_id, delta_impact_est);
        if delta_impact_est >= 0.0 {
            self.pending_positive += delta_impact_est;
        } else {
            self.pending_negative += delta_impact_est;
        }
        self.pending_total = self.pending_positive + self.pending_negative;
        metrics.record_reserve_success();

        PendingExposureResult::Reserved {
            reservation_id,
            pending_total: self.pending_total,
        }
    }

    /// Release reservation on TLSM terminal transition.
    ///
    /// Returns true when a reservation existed and was released.
    pub fn settle(
        &mut self,
        reservation_id: u64,
        outcome: PendingExposureTerminalOutcome,
        metrics: &mut PendingExposureMetrics,
    ) -> bool {
        let Some(delta_impact_est) = self.reservations.remove(&reservation_id) else {
            return false;
        };

        if delta_impact_est >= 0.0 {
            self.pending_positive -= delta_impact_est;
        } else {
            self.pending_negative -= delta_impact_est;
        }

        if self.pending_positive.abs() < 1e-12 {
            self.pending_positive = 0.0;
        }
        if self.pending_negative.abs() < 1e-12 {
            self.pending_negative = 0.0;
        }
        self.pending_total = self.pending_positive + self.pending_negative;
        if self.pending_total.abs() < 1e-12 {
            self.pending_total = 0.0;
        }

        // Filled conversion to realized exposure is owned by exposure state handlers.
        match outcome {
            PendingExposureTerminalOutcome::Filled
            | PendingExposureTerminalOutcome::Rejected
            | PendingExposureTerminalOutcome::Canceled
            | PendingExposureTerminalOutcome::Failed => {}
        }

        metrics.record_release();
        true
    }
}

fn normalized_limit(delta_limit: Option<f64>) -> Option<f64> {
    match delta_limit {
        Some(v) if v.is_finite() && v > 0.0 => Some(v.abs()),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_reserve_fails_closed_on_reservation_id_overflow() {
        let mut metrics = PendingExposureMetrics::new();
        let mut book = PendingExposureBook::new(Some(100.0));
        book.next_reservation_id = u64::MAX;

        let out = book.reserve(0.0, 1.0, &mut metrics);
        match out {
            PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total,
            } => {
                assert_eq!(pending_total, 0.0);
            }
            other => panic!("expected overflow fail-closed rejection, got {other:?}"),
        }

        assert_eq!(book.active_reservations(), 0);
        assert_eq!(book.pending_total(), 0.0);
        assert_eq!(metrics.reserve_attempt_total(), 1);
        assert_eq!(metrics.reserve_success_total(), 0);
        assert_eq!(metrics.reserve_reject_total(), 1);
    }

    #[test]
    fn test_settle_recomputes_total_after_component_snap() {
        let mut metrics = PendingExposureMetrics::new();
        let mut book = PendingExposureBook::new(Some(1_000.0));

        let first_id = match book.reserve(0.0, 10.0, &mut metrics) {
            PendingExposureResult::Reserved { reservation_id, .. } => reservation_id,
            other => panic!("expected reserve success, got {other:?}"),
        };
        match book.reserve(0.0, 1e-13, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected tiny reserve success, got {other:?}"),
        }
        match book.reserve(0.0, -4.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected negative reserve success, got {other:?}"),
        }

        assert!(book.settle(
            first_id,
            PendingExposureTerminalOutcome::Rejected,
            &mut metrics
        ));
        assert_eq!(book.pending_positive, 0.0);
        assert_eq!(book.pending_negative, -4.0);
        assert_eq!(book.pending_total, -4.0);
        assert_eq!(
            book.pending_total,
            book.pending_positive + book.pending_negative
        );
    }
}
