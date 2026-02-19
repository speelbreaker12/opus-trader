//! Pending exposure reservation (S6.2, anti over-fill) with per-instrument isolation.
//!
//! Contract mapping:
//! - §1.4.2.1: reserve before dispatch; reject if reservation breaches budget.
//!   "Maintain `pending_delta` per instrument + global."
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
    /// Instrument not registered via `register_instrument()` (fail-closed).
    InstrumentNotRegistered,
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
        /// Per-instrument pending total. `f64::NAN` when reason is `InstrumentNotRegistered`
        /// (no instrument exists, so there is no meaningful pending total).
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
    reserve_instrument_not_registered_total: u64,
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

    pub fn reserve_instrument_not_registered_total(&self) -> u64 {
        self.reserve_instrument_not_registered_total
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

    fn record_reserve_instrument_not_registered(&mut self) {
        self.reserve_attempt_total += 1;
        self.reserve_instrument_not_registered_total += 1;
        // NOTE: does NOT increment reserve_reject_total — that counter is for budget-exceeded only
    }

    fn record_reserve_idempotent_hit(&mut self) {
        self.reserve_idempotent_hit_total += 1;
    }

    fn record_release(&mut self) {
        self.release_total += 1;
    }
}

/// Per-instrument pending exposure state.
/// Each instrument has its own budget, positive/negative buckets, and reservation map.
// TODO(PX-3): If profiling shows allocation pressure, intern instrument_id
// keys with Arc<str> or a string interner. Current String cloning is fine
// for startup-registered instruments with low cardinality.
struct InstrumentBook {
    delta_limit: Option<f64>,
    pending_positive: f64,
    pending_negative: f64,
    pending_total: f64,
    reservations: HashMap<ReservationId, f64>,
}

/// Interior state behind RefCell.
struct BookInner {
    instruments: HashMap<String, InstrumentBook>,
    /// Cached global total — updated on every reserve/settle. Makes global_pending_total() O(1).
    global_total: f64,
    /// Reverse lookup: ReservationId → instrument_id. Detects cross-instrument misrouting.
    reservation_instrument: HashMap<ReservationId, String>,
}

/// Per-instrument pending exposure book with idempotent reserve/settle.
///
/// CONTRACT.md §1.4.2.1: "Maintain `pending_delta` per instrument + global."
///
/// # §1.4.2.1 compliance
///
/// `global_delta_limit: None` is valid only for unit tests or when the separate
/// global exposure budget gate (§1.4.2.2) provides cross-instrument protection.
/// Production deployments MUST set `global_delta_limit` to satisfy the
/// "per instrument + global" requirement.
///
/// # Orphan reservation risk
///
/// If `reserve()` is called for an ID that was previously settled (e.g., due to
/// a signal pipeline ordering violation where cancel races ahead of amend), the
/// reservation is created with no TLSM to drive its settlement. This budget is
/// leaked until process restart.
///
/// Mitigation options (PX-4):
/// 1. Track settled IDs in a bounded tombstone set. Reject reserve for tombstoned IDs.
/// 2. Add `drain_all()` for kill-switch recovery.
/// 3. Add reservation TTL with automatic expiry.
///
/// Current risk: Low — signal pipeline ordering guarantees cancel-after-reserve.
///
/// # RefCell safety
///
/// INVARIANT: No public method on PendingExposureBook may call another
/// borrowing method. Each method borrows `inner` exactly once at entry.
/// Violating this causes a runtime panic from RefCell double-borrow.
pub struct PendingExposureBook {
    global_delta_limit: Option<f64>,
    inner: RefCell<BookInner>,
}

impl std::fmt::Debug for PendingExposureBook {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let inner = self.inner.borrow();
        f.debug_struct("PendingExposureBook")
            .field("global_delta_limit", &self.global_delta_limit)
            .field("global_pending_total", &inner.global_total)
            .field("registered_instruments", &inner.instruments.len())
            .field(
                "global_active_reservations",
                &inner
                    .instruments
                    .values()
                    .map(|b| b.reservations.len())
                    .sum::<usize>(),
            )
            .finish()
    }
}

impl Default for PendingExposureBook {
    fn default() -> Self {
        Self::new(None)
    }
}

impl PendingExposureBook {
    /// Construct a reservation book with an optional global delta limit.
    ///
    /// Per-instrument limits are set via `register_instrument()`.
    /// `global_delta_limit` enforces a cross-instrument budget ceiling per §1.4.2.1.
    /// `None` skips the global check (per-instrument limits still enforced).
    ///
    /// `global_delta_limit` is normalized at construction: NaN, Infinity, negative,
    /// and zero values become `None` (fail-closed: no global cap means only
    /// per-instrument limits apply). This matches `register_instrument()` behavior.
    pub fn new(global_delta_limit: Option<f64>) -> Self {
        Self {
            global_delta_limit: normalized_limit(global_delta_limit),
            inner: RefCell::new(BookInner {
                instruments: HashMap::new(),
                global_total: 0.0,
                reservation_instrument: HashMap::new(),
            }),
        }
    }

    /// Register an instrument with its per-instrument delta limit.
    ///
    /// Must be called at startup before any reserve() calls for this instrument.
    /// Calling twice for the same instrument_id overwrites the previous registration
    /// (allows config reload). Existing reservations for the instrument are preserved.
    ///
    /// # Fail-closed behavior
    /// - Unregistered instruments are rejected at reserve() time
    /// - `delta_limit: None` or `delta_limit: Some(0.0)` rejects all reserves (fail-closed)
    pub fn register_instrument(&self, instrument_id: impl Into<String>, delta_limit: Option<f64>) {
        let id = instrument_id.into();
        // Normalize at registration: NaN, Infinity, negative, zero → None (fail-closed).
        let normalized = normalized_limit(delta_limit);
        let mut inner = self.inner.borrow_mut();
        if let Some(existing) = inner.instruments.get_mut(&id) {
            let has_active = !existing.reservations.is_empty();
            if let Some(new_limit) = normalized {
                // Check worst-case exposure (positive and negative buckets independently),
                // not just the algebraic pending_total which can hide a large one-sided position.
                if existing.pending_positive > new_limit
                    || existing.pending_negative.abs() > new_limit
                {
                    tracing::warn!(
                        %id, new_limit,
                        pending_positive = existing.pending_positive,
                        pending_negative = existing.pending_negative,
                        "config reload: instrument pending exposure exceeds new limit — \
                         new reserves blocked until existing reservations settle"
                    );
                }
            } else if has_active {
                tracing::warn!(
                    %id,
                    active_reservations = existing.reservations.len(),
                    "config reload: instrument delta_limit set to None — \
                     all new reserves blocked until existing reservations settle"
                );
            }
            existing.delta_limit = normalized;
        } else {
            inner.instruments.insert(
                id,
                InstrumentBook {
                    delta_limit: normalized,
                    pending_positive: 0.0,
                    pending_negative: 0.0,
                    pending_total: 0.0,
                    reservations: HashMap::new(),
                },
            );
        }
    }

    /// Get pending_total for a specific instrument. Returns 0.0 if not registered.
    pub fn pending_total(&self, instrument_id: &str) -> f64 {
        self.inner
            .borrow()
            .instruments
            .get(instrument_id)
            .map_or(0.0, |b| b.pending_total)
    }

    /// Get active reservation count for a specific instrument. Returns 0 if not registered.
    pub fn active_reservations(&self, instrument_id: &str) -> usize {
        self.inner
            .borrow()
            .instruments
            .get(instrument_id)
            .map_or(0, |b| b.reservations.len())
    }

    /// Global pending total across all instruments (cached, O(1)).
    pub fn global_pending_total(&self) -> f64 {
        self.inner.borrow().global_total
    }

    /// Global active reservation count across all instruments.
    pub fn global_active_reservations(&self) -> usize {
        self.inner
            .borrow()
            .instruments
            .values()
            .map(|b| b.reservations.len())
            .sum()
    }

    /// Number of registered instruments.
    pub fn registered_instrument_count(&self) -> usize {
        self.inner.borrow().instruments.len()
    }

    /// Get per-instrument delta limit (for diagnostics).
    /// Returns `None` if not registered, `Some(limit)` if registered.
    pub fn instrument_delta_limit(&self, instrument_id: &str) -> Option<Option<f64>> {
        self.inner
            .borrow()
            .instruments
            .get(instrument_id)
            .map(|b| b.delta_limit)
    }

    /// Reserve projected delta impact before dispatch on a specific instrument.
    ///
    /// Idempotent: if `reservation_id` already exists on this instrument, replaces
    /// the old reservation (subject to budget check). On reject, old reservation
    /// stays intact (fail-closed).
    ///
    /// # Reserve-after-settle behavior
    ///
    /// If a reservation was previously settled and the same ID is re-reserved,
    /// it is treated as a FRESH reservation (not idempotent hit).
    ///
    /// # Fail-closed behavior
    /// - Unregistered instrument → `InstrumentNotRegistered`
    /// - Cross-instrument ReservationId collision → `PendingExposureBudgetExceeded`
    /// - Invalid/missing per-instrument `delta_limit` → `PendingExposureBudgetExceeded`
    /// - Non-finite inputs → `PendingExposureBudgetExceeded`
    /// - Per-instrument budget exceeded → `PendingExposureBudgetExceeded`
    /// - Global budget exceeded → `PendingExposureBudgetExceeded`
    pub fn reserve(
        &self,
        reservation_id: &ReservationId,
        instrument_id: &str,
        current_delta: f64,
        delta_impact_est: f64,
        metrics: &mut PendingExposureMetrics,
    ) -> PendingExposureResult {
        let mut inner = self.inner.borrow_mut();

        // 1. Check instrument is registered.
        if !inner.instruments.contains_key(instrument_id) {
            metrics.record_reserve_instrument_not_registered();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::InstrumentNotRegistered,
                pending_total: f64::NAN,
            };
        }

        // 2. Cross-instrument ReservationId collision check.
        // Same instrument = idempotent replacement (handled below in step 5).
        if let Some(existing_instrument) = inner.reservation_instrument.get(reservation_id)
            && existing_instrument != instrument_id
        {
            tracing::error!(
                %reservation_id, existing = %existing_instrument, attempted = %instrument_id,
                "cross-instrument ReservationId collision — rejecting to prevent budget leak"
            );
            let pending = inner
                .instruments
                .get(instrument_id)
                .map_or(0.0, |b| b.pending_total);
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: pending,
            };
        }

        // 3. Per-instrument limit check.
        let book = inner.instruments.get(instrument_id).unwrap(); // safe: checked above
        let Some(limit) = normalized_limit(book.delta_limit) else {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: book.pending_total,
            };
        };

        // 4. Non-finite input check.
        if !current_delta.is_finite()
            || !delta_impact_est.is_finite()
            || !book.pending_total.is_finite()
            || !book.pending_positive.is_finite()
            || !book.pending_negative.is_finite()
        {
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: book.pending_total,
            };
        }

        // 5. Compute trial buckets with old delta subtracted (if idempotent re-reserve).
        let old_delta = book.reservations.get(reservation_id).copied();
        let mut trial_positive = book.pending_positive;
        let mut trial_negative = book.pending_negative;
        if let Some(old) = old_delta {
            if old >= 0.0 {
                trial_positive -= old;
            } else {
                trial_negative -= old;
            }
        }

        // 6. Project new delta into trial buckets — worst-case signed math.
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
            metrics.record_reserve_reject();
            return PendingExposureResult::Rejected {
                reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                pending_total: book.pending_total,
            };
        }

        // 7. Global budget check (after per-instrument passes).
        // NOTE: Uses algebraic sum (net across all instruments), not worst-case.
        // Per-instrument worst-case (long/short buckets) is the primary safety gate;
        // the global check is a secondary ceiling preventing aggregate over-extension.
        let old_global_delta = old_delta.unwrap_or(0.0);
        if let Some(global_limit) = normalized_limit(self.global_delta_limit) {
            let trial_global = inner.global_total - old_global_delta + delta_impact_est;
            if trial_global.abs() > global_limit {
                metrics.record_reserve_reject();
                return PendingExposureResult::Rejected {
                    reason: PendingExposureRejectReason::PendingExposureBudgetExceeded,
                    pending_total: book.pending_total,
                };
            }
        }

        // 8. Compute-then-assign: compute all final values before any mutation.
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
        let new_positive = snap_to_zero(new_positive);
        let new_negative = snap_to_zero(new_negative);
        let new_total = snap_to_zero(new_positive + new_negative);
        let new_global_total =
            snap_to_zero(inner.global_total - old_global_delta + delta_impact_est);

        // Atomic assignment block — per-instrument.
        let book = inner.instruments.get_mut(instrument_id).unwrap(); // safe: checked above
        book.pending_positive = new_positive;
        book.pending_negative = new_negative;
        book.pending_total = new_total;
        book.reservations
            .insert(reservation_id.clone(), delta_impact_est);

        // Atomic assignment — global.
        inner.global_total = new_global_total;
        inner
            .reservation_instrument
            .insert(reservation_id.clone(), instrument_id.to_owned());

        // Metrics.
        if old_delta.is_some() {
            metrics.record_reserve_idempotent_hit();
        }
        metrics.record_reserve_success();

        #[cfg(debug_assertions)]
        {
            let book = inner.instruments.get(instrument_id).unwrap();
            assert_invariants(book);
            assert_global_consistency(&inner);
        }

        PendingExposureResult::Reserved {
            reservation_id: reservation_id.clone(),
            pending_total: new_total,
        }
    }

    /// Release reservation on TLSM terminal transition.
    ///
    /// Uses `reservation_instrument` reverse lookup as authoritative routing key.
    /// The caller's `instrument_id` is a cross-check only — if it doesn't match
    /// the canonical instrument, a warning is logged but settlement proceeds on
    /// the canonical instrument to prevent budget leaks.
    ///
    /// `outcome` is currently unused but retained in the API contract for PX-3:
    /// different terminal outcomes (Filled vs Rejected/Canceled/Failed) will
    /// drive distinct settlement accounting (realized vs unrealized exposure).
    ///
    /// Returns true when a reservation existed and was released.
    pub fn settle(
        &self,
        reservation_id: &ReservationId,
        instrument_id: &str,
        _outcome: PendingExposureTerminalOutcome,
        metrics: &mut PendingExposureMetrics,
    ) -> bool {
        let mut inner = self.inner.borrow_mut();

        // Authoritative routing via reverse lookup.
        let canonical_instrument = match inner.reservation_instrument.get(reservation_id) {
            Some(canonical) => canonical.clone(),
            None => {
                tracing::error!(
                    %reservation_id, %instrument_id,
                    "settle failed — reservation not in reverse lookup (already settled or never reserved)"
                );
                return false;
            }
        };

        if canonical_instrument != instrument_id {
            tracing::warn!(
                %reservation_id, canonical = %canonical_instrument, caller = %instrument_id,
                "settle instrument mismatch — settling on canonical instrument to prevent budget leak"
            );
        }

        if !inner.instruments.contains_key(&canonical_instrument) {
            tracing::error!(
                %reservation_id, %canonical_instrument,
                "BUG: reverse lookup points to unregistered instrument"
            );
            debug_assert!(false, "reservation_instrument points to missing instrument");
            inner.reservation_instrument.remove(reservation_id);
            return false;
        }

        // Check reservation exists before mutating anything.
        let delta_impact_est = {
            let book = inner.instruments.get(&canonical_instrument).unwrap();
            match book.reservations.get(reservation_id).copied() {
                Some(d) => d,
                None => {
                    tracing::error!(
                        %reservation_id, %canonical_instrument,
                        "BUG: reverse lookup exists but instrument has no matching reservation"
                    );
                    debug_assert!(false, "reverse lookup / instrument map inconsistency");
                    inner.reservation_instrument.remove(reservation_id);
                    return false;
                }
            }
        };

        // Compute final values from current state (read-only access).
        let old_global_total = inner.global_total;
        let (new_positive, new_negative, new_total) = {
            let book = inner.instruments.get(&canonical_instrument).unwrap();
            let pos = if delta_impact_est >= 0.0 {
                book.pending_positive - delta_impact_est
            } else {
                book.pending_positive
            };
            let neg = if delta_impact_est < 0.0 {
                book.pending_negative - delta_impact_est
            } else {
                book.pending_negative
            };
            let pos = snap_to_zero(pos);
            let neg = snap_to_zero(neg);
            let total = snap_to_zero(pos + neg);
            (pos, neg, total)
        };
        let new_global_total = snap_to_zero(old_global_total - delta_impact_est);

        // Atomic assignment block — all mutations at once.
        {
            let book = inner.instruments.get_mut(&canonical_instrument).unwrap();
            book.reservations.remove(reservation_id);
            book.pending_positive = new_positive;
            book.pending_negative = new_negative;
            book.pending_total = new_total;
        }
        inner.global_total = new_global_total;
        inner.reservation_instrument.remove(reservation_id);

        metrics.record_release();

        #[cfg(debug_assertions)]
        {
            let book = inner.instruments.get(&canonical_instrument).unwrap();
            assert_invariants(book);
            assert_global_consistency(&inner);
        }

        true
    }
}

fn normalized_limit(delta_limit: Option<f64>) -> Option<f64> {
    match delta_limit {
        Some(v) if v.is_finite() && v > 0.0 => Some(v),
        _ => None,
    }
}

fn snap_to_zero(v: f64) -> f64 {
    if v.abs() < 1e-12 { 0.0 } else { v }
}

/// Debug-only per-instrument invariant checker.
#[cfg(debug_assertions)]
fn assert_invariants(book: &InstrumentBook) {
    debug_assert!(
        book.pending_positive >= 0.0,
        "pending_positive went negative: {}",
        book.pending_positive
    );
    debug_assert!(
        book.pending_negative <= 0.0,
        "pending_negative went positive: {}",
        book.pending_negative
    );
    let sum = book.pending_positive + book.pending_negative;
    debug_assert!(
        (book.pending_total - sum).abs() < 1e-12,
        "pending_total drift: total={}, sum={}",
        book.pending_total,
        sum
    );
    let map_sum: f64 = book.reservations.values().sum();
    debug_assert!(
        (map_sum - book.pending_total).abs() < 1e-12,
        "reservation map vs total drift: map_sum={}, total={}",
        map_sum,
        book.pending_total
    );
}

/// Debug-only global consistency check — cached global_total vs sum of per-instrument totals.
#[cfg(debug_assertions)]
fn assert_global_consistency(inner: &BookInner) {
    let computed_global: f64 = inner.instruments.values().map(|b| b.pending_total).sum();
    debug_assert!(
        (inner.global_total - computed_global).abs() < 1e-12,
        "global_total cache drift: cached={}, computed={}",
        inner.global_total,
        computed_global
    );
}

#[cfg(test)]
mod tests {
    use super::*;

    fn make_book(instrument: &str, limit: f64) -> PendingExposureBook {
        let book = PendingExposureBook::new(None);
        book.register_instrument(instrument, Some(limit));
        book
    }

    #[test]
    fn test_settle_recomputes_total_after_component_snap() {
        let mut metrics = PendingExposureMetrics::new();
        let book = make_book("TEST", 1_000.0);

        let r1 = ReservationId::new("r1").unwrap();
        let r2 = ReservationId::new("r2").unwrap();
        let r3 = ReservationId::new("r3").unwrap();

        match book.reserve(&r1, "TEST", 0.0, 10.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected reserve success, got {other:?}"),
        }
        match book.reserve(&r2, "TEST", 0.0, 1e-13, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected tiny reserve success, got {other:?}"),
        }
        match book.reserve(&r3, "TEST", 0.0, -4.0, &mut metrics) {
            PendingExposureResult::Reserved { .. } => {}
            other => panic!("expected negative reserve success, got {other:?}"),
        }

        assert!(book.settle(
            &r1,
            "TEST",
            PendingExposureTerminalOutcome::Rejected,
            &mut metrics
        ));
        assert_eq!(book.pending_total("TEST"), -4.0);
    }
}
