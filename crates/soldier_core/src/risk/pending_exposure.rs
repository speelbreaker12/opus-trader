//! Pending exposure reservation (S6.2, anti over-fill).
//!
//! Contract mapping:
//! - §1.4.2.1: reserve before dispatch; reject if reservation breaches budget.
//! - AT-225: concurrent reserves must not overfill budget.
//! - AT-910: over-budget reserve rejects with PendingExposureBudgetExceeded.

use std::cell::RefCell;
use std::collections::HashMap;

/// Stable idempotency key for pending exposure reservations.
/// Typically derived from intent_hash. Prevents double-counting on retry.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct ReservationId(String);

const MAX_RESERVATION_ID_LEN: usize = 128;

impl ReservationId {
    /// Create a validated reservation ID.
    ///
    /// Returns `None` for empty, >128 char, or control-char inputs.
    /// Caller must handle — fail-closed at reserve() level.
    pub fn new(id: impl Into<String>) -> Option<Self> {
        let s: String = id.into();
        let trimmed = s.trim();
        if trimmed.is_empty()
            || trimmed.len() > MAX_RESERVATION_ID_LEN
            || trimmed.bytes().any(|b| b < 0x20)
        {
            None
        } else {
            Some(Self(trimmed.to_owned()))
        }
    }

    pub fn as_str(&self) -> &str {
        &self.0
    }
}

impl std::fmt::Display for ReservationId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        self.0.fmt(f)
    }
}

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
        reservation_id: ReservationId,
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
    reserve_idempotent_hit_total: u64,
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

    pub fn reserve_idempotent_hit_total(&self) -> u64 {
        self.reserve_idempotent_hit_total
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

    fn record_reserve_idempotent_hit(&mut self) {
        self.reserve_idempotent_hit_total += 1;
    }

    fn record_release(&mut self) {
        self.release_total += 1;
    }
}

/// Internal mutable state behind RefCell.
struct BookInner {
    pending_total: f64,
    pending_positive: f64,
    pending_negative: f64,
    reservations: HashMap<ReservationId, f64>,
}

/// In-memory reservation book with idempotent reserve/settle.
///
/// # Orphan reservation risk
///
/// If `reserve()` is called for an ID that was previously settled (e.g., due to
/// a signal pipeline ordering violation where cancel races ahead of amend), the
/// reservation is created with no TLSM to drive its settlement. This budget is
/// leaked until process restart.
///
/// Mitigation options (PX-2 or PX-4):
/// 1. Track settled IDs in a bounded tombstone set. Reject reserve for tombstoned IDs.
/// 2. Add `drain_all()` for kill-switch recovery.
/// 3. Add reservation TTL with automatic expiry.
///
/// Current risk: Low — signal pipeline ordering guarantees cancel-after-reserve.
/// This requires an async ordering violation to trigger.
///
/// # Emergency drain (PX-4)
///
/// There is no `drain_all()` or `clear()` method. If TLSM settlement fails
/// (exchange down, WS disconnect), reservations leak permanently until process
/// restart. A future `drain_all(&self) -> (usize, f64)` gated behind
/// `RiskState::Kill` + operator confirmation should be tracked for PX-4.
///
/// # RefCell safety
///
/// INVARIANT: No public method on PendingExposureBook may call another
/// borrowing method. Each method borrows `inner` exactly once at entry.
/// Violating this causes a runtime panic from RefCell double-borrow.
pub struct PendingExposureBook {
    delta_limit: Option<f64>,
    inner: RefCell<BookInner>,
}

impl std::fmt::Debug for PendingExposureBook {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let inner = self.inner.borrow();
        f.debug_struct("PendingExposureBook")
            .field("delta_limit", &self.delta_limit)
            .field("pending_total", &inner.pending_total)
            .field("active_reservations", &inner.reservations.len())
            .finish()
    }
}

impl Default for PendingExposureBook {
    fn default() -> Self {
        Self::new(None)
    }
}

impl PendingExposureBook {
    /// Construct a reservation book.
    ///
    /// `delta_limit` is absolute budget enforced against worst-case pending outcomes.
    /// Missing/invalid value is fail-closed at reserve time.
    pub fn new(delta_limit: Option<f64>) -> Self {
        Self {
            delta_limit,
            inner: RefCell::new(BookInner {
                pending_total: 0.0,
                pending_positive: 0.0,
                pending_negative: 0.0,
                reservations: HashMap::new(),
            }),
        }
    }

    pub fn pending_total(&self) -> f64 {
        self.inner.borrow().pending_total
    }

    pub fn active_reservations(&self) -> usize {
        self.inner.borrow().reservations.len()
    }

    /// Reserve projected delta impact before dispatch.
    ///
    /// Idempotent: if `reservation_id` already exists, replaces the old reservation
    /// (subject to budget check). On reject, the old reservation stays intact (fail-closed).
    ///
    /// # Reserve-after-settle behavior
    ///
    /// If a reservation was previously settled and the same ID is re-reserved,
    /// it is treated as a FRESH reservation (not idempotent hit). This is correct —
    /// dispatch-layer dedup is responsible for preventing duplicate orders after
    /// settlement. The budget accounting is correct at every step; the duplicate
    /// dispatch risk lives in the dispatch layer, not the reservation book.
    ///
    /// Fail-closed behavior:
    /// - invalid/missing `delta_limit`
    /// - non-finite inputs
    pub fn reserve(
        &self,
        reservation_id: &ReservationId,
        current_delta: f64,
        delta_impact_est: f64,
        metrics: &mut PendingExposureMetrics,
    ) -> PendingExposureResult {
        let Some(limit) = normalized_limit(self.delta_limit) else {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: self.inner.borrow().pending_total,
            };
        };

        let mut inner = self.inner.borrow_mut();

        if !current_delta.is_finite()
            || !delta_impact_est.is_finite()
            || !inner.pending_total.is_finite()
            || !inner.pending_positive.is_finite()
            || !inner.pending_negative.is_finite()
        {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: inner.pending_total,
            };
        }

        // Compute trial buckets with old delta subtracted (if idempotent re-reserve).
        let old_delta = inner.reservations.get(reservation_id).copied();
        let mut trial_positive = inner.pending_positive;
        let mut trial_negative = inner.pending_negative;
        if let Some(old) = old_delta {
            if old >= 0.0 {
                trial_positive -= old;
            } else {
                trial_negative -= old;
            }
        }

        // Project new delta into trial buckets.
        let projected_positive = if delta_impact_est >= 0.0 {
            trial_positive + delta_impact_est
        } else {
            trial_positive
        };
        let projected_negative = if delta_impact_est < 0.0 {
            trial_negative + delta_impact_est
        } else {
            trial_negative
        };
        let worst_case_long = current_delta + projected_positive;
        let worst_case_short = current_delta + projected_negative;
        if worst_case_long.abs() > limit || worst_case_short.abs() > limit {
            // Fail-closed: on reject, old reservation stays intact.
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: inner.pending_total,
            };
        }

        // Compute-then-assign: compute all final values before any mutation.
        // This eliminates the subtract-then-add window where a panic could leave
        // inconsistent state (fail-open budget undercount).
        let new_positive = if delta_impact_est >= 0.0 {
            trial_positive + delta_impact_est
        } else {
            trial_positive
        };
        let new_negative = if delta_impact_est < 0.0 {
            trial_negative + delta_impact_est
        } else {
            trial_negative
        };
        // Snap-to-zero (1e-12 epsilon) to prevent FP drift.
        let new_positive = if new_positive.abs() < 1e-12 {
            0.0
        } else {
            new_positive
        };
        let new_negative = if new_negative.abs() < 1e-12 {
            0.0
        } else {
            new_negative
        };
        let new_total = new_positive + new_negative;
        let new_total = if new_total.abs() < 1e-12 {
            0.0
        } else {
            new_total
        };

        // Atomic assignment block.
        inner.pending_positive = new_positive;
        inner.pending_negative = new_negative;
        inner.pending_total = new_total;
        inner
            .reservations
            .insert(reservation_id.clone(), delta_impact_est);

        // Metrics.
        if old_delta.is_some() {
            metrics.record_reserve_idempotent_hit();
        }
        metrics.record_reserve_success();

        #[cfg(debug_assertions)]
        assert_invariants(&inner);

        PendingExposureResult::Reserved {
            reservation_id: reservation_id.clone(),
            pending_total: new_total,
        }
    }

    /// Release reservation on TLSM terminal transition.
    ///
    /// Returns true when a reservation existed and was released.
    pub fn settle(
        &self,
        reservation_id: &ReservationId,
        outcome: PendingExposureTerminalOutcome,
        metrics: &mut PendingExposureMetrics,
    ) -> bool {
        let mut inner = self.inner.borrow_mut();

        let Some(delta_impact_est) = inner.reservations.remove(reservation_id) else {
            return false;
        };

        // Compute-then-assign for settle (same pattern as reserve).
        let new_positive = if delta_impact_est >= 0.0 {
            inner.pending_positive - delta_impact_est
        } else {
            inner.pending_positive
        };
        let new_negative = if delta_impact_est < 0.0 {
            inner.pending_negative - delta_impact_est
        } else {
            inner.pending_negative
        };
        let new_positive = if new_positive.abs() < 1e-12 {
            0.0
        } else {
            new_positive
        };
        let new_negative = if new_negative.abs() < 1e-12 {
            0.0
        } else {
            new_negative
        };
        let new_total = new_positive + new_negative;
        let new_total = if new_total.abs() < 1e-12 {
            0.0
        } else {
            new_total
        };

        inner.pending_positive = new_positive;
        inner.pending_negative = new_negative;
        inner.pending_total = new_total;

        // Filled conversion to realized exposure is owned by exposure state handlers.
        match outcome {
            PendingExposureTerminalOutcome::Filled
            | PendingExposureTerminalOutcome::Rejected
            | PendingExposureTerminalOutcome::Canceled
            | PendingExposureTerminalOutcome::Failed => {}
        }

        metrics.record_release();

        #[cfg(debug_assertions)]
        assert_invariants(&inner);

        true
    }
}

fn normalized_limit(delta_limit: Option<f64>) -> Option<f64> {
    match delta_limit {
        Some(v) if v.is_finite() && v > 0.0 => Some(v),
        _ => None,
    }
}

/// Debug-only invariant checker. Takes `&BookInner` (NOT `&self`) to avoid
/// nested RefCell borrow — the caller already holds `borrow_mut()`.
#[cfg(debug_assertions)]
fn assert_invariants(inner: &BookInner) {
    debug_assert!(
        inner.pending_positive >= 0.0,
        "pending_positive went negative: {}",
        inner.pending_positive
    );
    debug_assert!(
        inner.pending_negative <= 0.0,
        "pending_negative went positive: {}",
        inner.pending_negative
    );
    let sum = inner.pending_positive + inner.pending_negative;
    debug_assert!(
        (inner.pending_total - sum).abs() < 1e-12,
        "pending_total drift: total={}, sum={}",
        inner.pending_total,
        sum
    );
    let map_sum: f64 = inner.reservations.values().sum();
    debug_assert!(
        (map_sum - inner.pending_total).abs() < 1e-12,
        "reservation map vs total drift: map_sum={}, total={}",
        map_sum,
        inner.pending_total
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_settle_recomputes_total_after_component_snap() {
        let mut metrics = PendingExposureMetrics::new();
        let book = PendingExposureBook::new(Some(1_000.0));

        let r1 = ReservationId::new("r1").unwrap();
        let r2 = ReservationId::new("r2").unwrap();
        let r3 = ReservationId::new("r3").unwrap();

        match book.reserve(&r1, 0.0, 10.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected reserve success, got {other:?}"),
        }
        match book.reserve(&r2, 0.0, 1e-13, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected tiny reserve success, got {other:?}"),
        }
        match book.reserve(&r3, 0.0, -4.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected negative reserve success, got {other:?}"),
        }

        assert!(book.settle(&r1, PendingExposureTerminalOutcome::Rejected, &mut metrics));
        let inner = book.inner.borrow();
        assert_eq!(inner.pending_positive, 0.0);
        assert_eq!(inner.pending_negative, -4.0);
        assert_eq!(inner.pending_total, -4.0);
        assert_eq!(
            inner.pending_total,
            inner.pending_positive + inner.pending_negative
        );
    }
}
