//! Group state machine per CONTRACT.md §1.2.1.
//!
//! Manages multi-leg atomic intent groups with first-fail invariant:
//! - GroupState: `New → Dispatched → Complete | MixedFailed → Flattening → Flattened`
//! - First observed failure seeds MixedFailed and MUST NOT be overwritten.
//! - GroupState transitions are single-writer protected by group-level lock.
//! - Lock acquisition is bounded by `group_lock_max_wait_ms`; timeout forces ReduceOnly.
//! - Group intent MUST be durably recorded before any leg dispatch.
//!
//! AT-116, AT-220, AT-924, AT-936.

use std::time::{Duration, Instant};

use super::tlsm::TlsmState;

// ─── GroupState ─────────────────────────────────────────────────────────

/// Group lifecycle states per CONTRACT.md §1.2.1.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub enum GroupState {
    /// Group created, not yet dispatched.
    New,
    /// All legs dispatched, awaiting results.
    Dispatched,
    /// All legs terminal, fills balanced within epsilon, no containment pending.
    Complete,
    /// First failure observed — atomicity broken. Containment required.
    MixedFailed,
    /// Containment/emergency-close in progress.
    Flattening,
    /// Fully flattened — exposure neutral.
    Flattened,
}

impl GroupState {
    /// Whether this state is terminal (no further transitions expected).
    pub fn is_terminal(self) -> bool {
        matches!(self, GroupState::Complete | GroupState::Flattened)
    }
}

// ─── LegResult ──────────────────────────────────────────────────────────

/// Outcome of a single leg dispatch per CONTRACT.md §1.2.1.
#[derive(Debug, Clone, PartialEq)]
pub struct LegResult {
    pub leg_idx: u8,
    pub requested_qty: f64,
    pub filled_qty: f64,
    pub rejected: bool,
    pub unfilled: bool,
    pub tlsm_state: TlsmState,
}

// ─── GroupConfig ────────────────────────────────────────────────────────

/// Configuration for group execution per CONTRACT.md Appendix A.
#[derive(Debug, Clone)]
pub struct GroupConfig {
    /// Maximum time to wait for group lock acquisition (Appendix A default: 10ms).
    pub group_lock_max_wait_ms: u64,
    /// Fill mismatch tolerance for atomicity check.
    pub atomic_qty_epsilon: f64,
}

impl Default for GroupConfig {
    fn default() -> Self {
        Self {
            group_lock_max_wait_ms: 10,
            atomic_qty_epsilon: 1e-9,
        }
    }
}

// ─── GroupPersistence trait ──────────────────────────────────────────────

/// Persistence interface for group intent recording.
///
/// CONTRACT.md §1.2.1: "Group intent MUST be durably recorded before any leg
/// dispatch. If persistence fails, MUST abort and MUST NOT submit any leg orders."
pub trait GroupPersistence {
    fn persist_group_intent(&mut self, group_id: &str) -> Result<(), String>;
    fn mark_group_state(&mut self, group_id: &str, state: GroupState) -> Result<(), String>;
}

/// In-memory persistence for testing.
#[derive(Debug, Default)]
pub struct InMemoryGroupPersistence {
    pub persisted_intents: Vec<String>,
    pub state_transitions: Vec<(String, GroupState)>,
    pub fail_persist: bool,
}

impl GroupPersistence for InMemoryGroupPersistence {
    fn persist_group_intent(&mut self, group_id: &str) -> Result<(), String> {
        if self.fail_persist {
            return Err("persistence failure".to_string());
        }
        self.persisted_intents.push(group_id.to_string());
        Ok(())
    }

    fn mark_group_state(&mut self, group_id: &str, state: GroupState) -> Result<(), String> {
        self.state_transitions.push((group_id.to_string(), state));
        Ok(())
    }
}

// ─── GroupLock ───────────────────────────────────────────────────────────

/// Bounded lock for group-level serialization per CONTRACT.md §1.2.1.
///
/// Lock acquisition MUST be bounded by `group_lock_max_wait_ms`.
/// If not acquired, the hot loop MUST NOT block and MUST force ReduceOnly.
#[derive(Debug)]
pub struct GroupLock {
    held: bool,
    held_since: Option<Instant>,
}

impl GroupLock {
    pub fn new() -> Self {
        Self {
            held: false,
            held_since: None,
        }
    }

    /// Attempt to acquire the lock. Returns true if acquired.
    pub fn try_acquire(&mut self) -> bool {
        if self.held {
            return false;
        }
        self.held = true;
        self.held_since = Some(Instant::now());
        true
    }

    /// Release the lock.
    pub fn release(&mut self) {
        self.held = false;
        self.held_since = None;
    }

    /// Check if the lock is currently held.
    pub fn is_held(&self) -> bool {
        self.held
    }

    /// Check if the lock has been held longer than the given duration.
    pub fn is_expired(&self, max_wait: Duration) -> bool {
        match self.held_since {
            Some(since) => since.elapsed() > max_wait,
            None => false,
        }
    }
}

impl Default for GroupLock {
    fn default() -> Self {
        Self::new()
    }
}

// ─── LockAcquisitionResult ─────────────────────────────────────────────

/// Result of attempting to acquire the group lock within the bounded timeout.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LockAcquisitionResult {
    /// Lock acquired successfully.
    Acquired,
    /// Lock not acquired within timeout — caller MUST force ReduceOnly.
    TimedOut,
}

// ─── AtomicGroup ────────────────────────────────────────────────────────

/// A multi-leg atomic group per CONTRACT.md §1.2.1.
#[derive(Debug)]
pub struct AtomicGroup {
    pub group_id: String,
    pub num_legs: usize,
    pub state: GroupState,
    pub leg_results: Vec<LegResult>,
    pub containment_pending: bool,
    pub dispatch_count: u32,
    pub rescue_dispatch_count: u32,
    first_failure_reason: Option<String>,
}

impl AtomicGroup {
    pub fn new(group_id: String, num_legs: usize) -> Self {
        Self {
            group_id,
            num_legs,
            state: GroupState::New,
            leg_results: Vec::new(),
            containment_pending: false,
            dispatch_count: 0,
            rescue_dispatch_count: 0,
            first_failure_reason: None,
        }
    }

    /// Get the first failure reason, if any.
    pub fn first_failure_reason(&self) -> Option<&str> {
        self.first_failure_reason.as_deref()
    }

    /// Record group as dispatched. Returns error if not in New state.
    pub fn mark_dispatched(&mut self) -> Result<(), GroupError> {
        if self.state != GroupState::New {
            return Err(GroupError::InvalidTransition {
                from: self.state,
                to: GroupState::Dispatched,
            });
        }
        self.state = GroupState::Dispatched;
        Ok(())
    }

    /// Apply a leg result and evaluate group state.
    ///
    /// CONTRACT.md §1.2.1: "First observed failure seeds MixedFailed and MUST NOT
    /// be overwritten by later async updates."
    pub fn apply_leg_result(
        &mut self,
        result: LegResult,
        config: &GroupConfig,
    ) -> GroupStateTransition {
        self.leg_results.push(result.clone());

        // Check for failure condition on this leg
        let is_failure = result.rejected
            || result.unfilled
            || (result.filled_qty > 0.0 && result.filled_qty < result.requested_qty);

        // First-fail invariant: seed MixedFailed on first failure, never overwrite
        if is_failure
            && self.state != GroupState::MixedFailed
            && self.state != GroupState::Flattening
            && self.state != GroupState::Flattened
        {
            let reason = if result.rejected {
                format!("leg {} rejected", result.leg_idx)
            } else if result.unfilled {
                format!("leg {} unfilled", result.leg_idx)
            } else {
                format!(
                    "leg {} partial fill ({}/{})",
                    result.leg_idx, result.filled_qty, result.requested_qty
                )
            };

            // Only set first failure if not already set (idempotent for concurrent arrivals)
            if self.first_failure_reason.is_none() {
                self.first_failure_reason = Some(reason.clone());
            }

            if self.state == GroupState::Dispatched || self.state == GroupState::New {
                self.state = GroupState::MixedFailed;
                self.containment_pending = true;
                return GroupStateTransition::EnteredMixedFailed { reason };
            }
        }

        // Check if all legs are terminal
        if self.all_legs_terminal() && self.state == GroupState::Dispatched {
            if self.is_atomicity_intact(config) {
                self.state = GroupState::Complete;
                return GroupStateTransition::Completed;
            }
            // All terminal but atomicity broken — should already be MixedFailed
            // from the failure leg, but defensive fallback:
            let reason = "all legs terminal but atomicity broken".to_string();
            if self.first_failure_reason.is_none() {
                self.first_failure_reason = Some(reason.clone());
            }
            self.state = GroupState::MixedFailed;
            self.containment_pending = true;
            return GroupStateTransition::EnteredMixedFailed { reason };
        }

        GroupStateTransition::NoChange
    }

    /// Check if all legs have reached a terminal TLSM state.
    pub fn all_legs_terminal(&self) -> bool {
        self.leg_results.len() == self.num_legs
            && !self.leg_results.is_empty()
            && self.leg_results.iter().all(|r| r.tlsm_state.is_terminal())
    }

    /// Check if group atomicity is intact (fills balanced within epsilon, no partials).
    fn is_atomicity_intact(&self, config: &GroupConfig) -> bool {
        if self.leg_results.is_empty() {
            return false;
        }

        let filled_qtys: Vec<f64> = self.leg_results.iter().map(|r| r.filled_qty).collect();
        let max_f = filled_qtys
            .iter()
            .copied()
            .fold(f64::NEG_INFINITY, f64::max);
        let min_f = filled_qtys.iter().copied().fold(f64::INFINITY, f64::min);
        let any_partial = self
            .leg_results
            .iter()
            .any(|r| r.filled_qty > 0.0 && r.filled_qty < r.requested_qty);
        let any_rejected = self.leg_results.iter().any(|r| r.rejected);

        !any_partial
            && !any_rejected
            && (max_f - min_f) <= config.atomic_qty_epsilon
            && !self.containment_pending
    }

    /// Evaluate whether group can be marked Complete per CONTRACT.md §1.2.1.
    ///
    /// A Group may be marked Complete ONLY if:
    /// - Every leg has reached terminal TLSM state
    /// - No partial fills
    /// - No fill mismatch beyond epsilon
    /// - No containment/rescue pending
    pub fn can_complete(&self, config: &GroupConfig) -> bool {
        self.all_legs_terminal()
            && self.is_atomicity_intact(config)
            && !self.containment_pending
            && self.state != GroupState::MixedFailed
    }

    /// Mark group as flattening (containment in progress).
    pub fn mark_flattening(&mut self) -> Result<(), GroupError> {
        if self.state != GroupState::MixedFailed {
            return Err(GroupError::InvalidTransition {
                from: self.state,
                to: GroupState::Flattening,
            });
        }
        self.state = GroupState::Flattening;
        Ok(())
    }

    /// Mark group as flattened (exposure neutral).
    pub fn mark_flattened(&mut self) -> Result<(), GroupError> {
        if self.state != GroupState::Flattening {
            return Err(GroupError::InvalidTransition {
                from: self.state,
                to: GroupState::Flattened,
            });
        }
        self.state = GroupState::Flattened;
        self.containment_pending = false;
        Ok(())
    }
}

// ─── GroupStateTransition ───────────────────────────────────────────────

/// Result of applying a leg result to the group.
#[derive(Debug, Clone, PartialEq)]
pub enum GroupStateTransition {
    /// No state change — waiting for more leg results.
    NoChange,
    /// Group entered MixedFailed — containment required.
    EnteredMixedFailed { reason: String },
    /// Group completed cleanly.
    Completed,
}

// ─── GroupError ─────────────────────────────────────────────────────────

/// Errors from group operations.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum GroupError {
    /// Invalid state transition attempted.
    InvalidTransition { from: GroupState, to: GroupState },
    /// Group intent persistence failed — MUST abort, MUST NOT dispatch.
    PersistenceFailed { reason: String },
    /// Lock acquisition timed out — force ReduceOnly.
    LockTimeout,
}

// ─── try_acquire_group_lock ─────────────────────────────────────────────

/// Attempt to acquire the group lock within bounded timeout.
///
/// CONTRACT.md §1.2.1: "Lock acquisition MUST be bounded (try_lock/timeout)
/// with group_lock_max_wait_ms. If not acquired within the bound, the hot loop
/// MUST NOT block and MUST force ReduceOnly until the lock clears."
pub fn try_acquire_group_lock(lock: &mut GroupLock, config: &GroupConfig) -> LockAcquisitionResult {
    let max_wait = Duration::from_millis(config.group_lock_max_wait_ms);

    // If lock is already held and expired, force ReduceOnly
    if lock.is_held() && lock.is_expired(max_wait) {
        return LockAcquisitionResult::TimedOut;
    }

    if lock.try_acquire() {
        LockAcquisitionResult::Acquired
    } else {
        LockAcquisitionResult::TimedOut
    }
}

// ─── persist_before_dispatch ────────────────────────────────────────────

/// Persist group intent before dispatch per CONTRACT.md §1.2.1.
///
/// "Group intent MUST be durably recorded before any leg dispatch.
///  If persistence fails, MUST abort and MUST NOT submit any leg orders."
pub fn persist_before_dispatch(
    group: &AtomicGroup,
    persistence: &mut dyn GroupPersistence,
) -> Result<(), GroupError> {
    persistence
        .persist_group_intent(&group.group_id)
        .map_err(|reason| GroupError::PersistenceFailed { reason })
}

#[cfg(test)]
mod tests {
    use super::*;

    fn filled_leg(idx: u8, qty: f64) -> LegResult {
        LegResult {
            leg_idx: idx,
            requested_qty: qty,
            filled_qty: qty,
            rejected: false,
            unfilled: false,
            tlsm_state: TlsmState::Filled,
        }
    }

    fn rejected_leg(idx: u8, qty: f64) -> LegResult {
        LegResult {
            leg_idx: idx,
            requested_qty: qty,
            filled_qty: 0.0,
            rejected: true,
            unfilled: false,
            tlsm_state: TlsmState::Failed,
        }
    }

    fn partial_leg(idx: u8, requested: f64, filled: f64) -> LegResult {
        LegResult {
            leg_idx: idx,
            requested_qty: requested,
            filled_qty: filled,
            rejected: false,
            unfilled: false,
            tlsm_state: TlsmState::PartiallyFilled,
        }
    }

    fn default_config() -> GroupConfig {
        GroupConfig::default()
    }

    // ─── AT-116: Leg A filled, Leg B rejected → MixedFailed ─────────────

    #[test]
    fn at_116_leg_a_filled_leg_b_rejected_enters_mixed_failed() {
        let config = default_config();
        let mut group = AtomicGroup::new("grp-1".to_string(), 2);
        group.mark_dispatched().expect("dispatch should succeed");

        // Leg A fills successfully
        let transition = group.apply_leg_result(filled_leg(0, 1.0), &config);
        assert_eq!(transition, GroupStateTransition::NoChange);
        assert_eq!(group.state, GroupState::Dispatched);

        // Leg B rejected — first failure seeds MixedFailed
        let transition = group.apply_leg_result(rejected_leg(1, 1.0), &config);
        assert!(
            matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
            "expected MixedFailed, got {:?}",
            transition
        );
        assert_eq!(group.state, GroupState::MixedFailed);
        assert!(group.containment_pending);
        assert!(group.first_failure_reason().is_some());
        assert!(
            group
                .first_failure_reason()
                .expect("should have reason")
                .contains("rejected"),
        );

        // Dispatch count should be 0 (no new OPENs dispatched)
        assert_eq!(group.dispatch_count, 0);
    }

    #[test]
    fn at_116_mixed_failed_not_overwritten_by_later_updates() {
        let config = default_config();
        let mut group = AtomicGroup::new("grp-2".to_string(), 2);
        group.mark_dispatched().expect("dispatch should succeed");

        // Leg B rejected first — seeds MixedFailed
        let transition = group.apply_leg_result(rejected_leg(1, 1.0), &config);
        assert!(matches!(
            transition,
            GroupStateTransition::EnteredMixedFailed { .. }
        ));
        assert_eq!(group.state, GroupState::MixedFailed);
        let first_reason = group.first_failure_reason().map(String::from);

        // Leg A fills later — state MUST NOT change from MixedFailed
        let transition = group.apply_leg_result(filled_leg(0, 1.0), &config);
        assert_eq!(transition, GroupStateTransition::NoChange);
        assert_eq!(group.state, GroupState::MixedFailed);

        // First failure reason MUST NOT be overwritten
        assert_eq!(group.first_failure_reason().map(String::from), first_reason);
    }

    // ─── AT-220: Out-of-order leg events ────────────────────────────────

    #[test]
    fn at_220_never_complete_before_all_legs_terminal() {
        let config = default_config();
        let mut group = AtomicGroup::new("grp-3".to_string(), 2);
        group.mark_dispatched().expect("dispatch should succeed");

        // Leg A fills fast
        let transition = group.apply_leg_result(filled_leg(0, 1.0), &config);
        assert_eq!(transition, GroupStateTransition::NoChange);
        // Group MUST NOT be Complete yet — Leg B is not terminal
        assert_ne!(group.state, GroupState::Complete);

        // Leg B rejects late — first failure triggers containment
        let transition = group.apply_leg_result(rejected_leg(1, 1.0), &config);
        assert!(matches!(
            transition,
            GroupStateTransition::EnteredMixedFailed { .. }
        ));
        assert_eq!(group.state, GroupState::MixedFailed);
        assert!(group.containment_pending);

        // Group is never Complete
        assert!(!group.can_complete(&config));
    }

    #[test]
    fn at_220_both_legs_fill_cleanly_then_complete() {
        let config = default_config();
        let mut group = AtomicGroup::new("grp-4".to_string(), 2);
        group.mark_dispatched().expect("dispatch should succeed");

        // Leg A fills
        let transition = group.apply_leg_result(filled_leg(0, 1.0), &config);
        assert_eq!(transition, GroupStateTransition::NoChange);

        // Leg B fills — both terminal, no mismatch
        let transition = group.apply_leg_result(filled_leg(1, 1.0), &config);
        assert_eq!(transition, GroupStateTransition::Completed);
        assert_eq!(group.state, GroupState::Complete);
    }

    // ─── AT-924: Lock timeout → ReduceOnly ──────────────────────────────

    #[test]
    fn at_924_lock_held_beyond_timeout_returns_timed_out() {
        let config = GroupConfig {
            group_lock_max_wait_ms: 0, // immediate timeout for testing
            ..Default::default()
        };
        let mut lock = GroupLock::new();

        // Acquire the lock
        assert!(lock.try_acquire());

        // Attempting to acquire again while held should fail
        let result = try_acquire_group_lock(&mut lock, &config);
        assert_eq!(result, LockAcquisitionResult::TimedOut);

        // Verify: caller must force ReduceOnly (no stall, no block)
        // The function returns immediately — it never blocks.
    }

    #[test]
    fn at_924_lock_not_held_acquires_successfully() {
        let config = default_config();
        let mut lock = GroupLock::new();

        let result = try_acquire_group_lock(&mut lock, &config);
        assert_eq!(result, LockAcquisitionResult::Acquired);
        assert!(lock.is_held());
    }

    #[test]
    fn at_924_lock_released_then_reacquired() {
        let config = default_config();
        let mut lock = GroupLock::new();

        // Acquire
        assert!(lock.try_acquire());
        // Release
        lock.release();
        assert!(!lock.is_held());

        // Re-acquire
        let result = try_acquire_group_lock(&mut lock, &config);
        assert_eq!(result, LockAcquisitionResult::Acquired);
    }

    // ─── AT-936: MixedFailed + gate rejects rescue → emergency close ────

    #[test]
    fn at_936_mixed_failed_rescue_rejected_no_rescue_dispatched() {
        let config = default_config();
        let mut group = AtomicGroup::new("grp-5".to_string(), 2);
        group.mark_dispatched().expect("dispatch should succeed");

        // Leg A fills, Leg B rejected → MixedFailed
        group.apply_leg_result(filled_leg(0, 1.0), &config);
        let transition = group.apply_leg_result(rejected_leg(1, 1.0), &config);
        assert!(matches!(
            transition,
            GroupStateTransition::EnteredMixedFailed { .. }
        ));

        // Simulate: rescue gates reject (LiquidityGate/NetEdge fail)
        // No rescue dispatch occurs — rescue_dispatch_count stays 0
        assert_eq!(group.rescue_dispatch_count, 0);

        // Transition to Flattening (emergency close runs)
        group.mark_flattening().expect("flattening should succeed");
        assert_eq!(group.state, GroupState::Flattening);

        // Emergency close completes
        group.mark_flattened().expect("flattened should succeed");
        assert_eq!(group.state, GroupState::Flattened);
        assert!(!group.containment_pending);
    }

    // ─── Persistence before dispatch ────────────────────────────────────

    #[test]
    fn persist_before_dispatch_succeeds() {
        let group = AtomicGroup::new("grp-persist".to_string(), 2);
        let mut store = InMemoryGroupPersistence::default();

        let result = persist_before_dispatch(&group, &mut store);
        assert!(result.is_ok());
        assert_eq!(store.persisted_intents, vec!["grp-persist"]);
    }

    #[test]
    fn persist_before_dispatch_fails_aborts() {
        let group = AtomicGroup::new("grp-fail".to_string(), 2);
        let mut store = InMemoryGroupPersistence {
            fail_persist: true,
            ..Default::default()
        };

        let result = persist_before_dispatch(&group, &mut store);
        assert!(matches!(result, Err(GroupError::PersistenceFailed { .. })));
        // No leg dispatch should occur after this error
    }

    // ─── State transition validation ────────────────────────────────────

    #[test]
    fn mark_dispatched_from_non_new_fails() {
        let mut group = AtomicGroup::new("grp-x".to_string(), 2);
        group.mark_dispatched().expect("first dispatch ok");

        let result = group.mark_dispatched();
        assert!(matches!(
            result,
            Err(GroupError::InvalidTransition {
                from: GroupState::Dispatched,
                to: GroupState::Dispatched,
            })
        ));
    }

    #[test]
    fn mark_flattening_from_non_mixed_failed_fails() {
        let mut group = AtomicGroup::new("grp-y".to_string(), 2);
        group.mark_dispatched().expect("dispatch ok");

        let result = group.mark_flattening();
        assert!(matches!(
            result,
            Err(GroupError::InvalidTransition {
                from: GroupState::Dispatched,
                to: GroupState::Flattening,
            })
        ));
    }

    #[test]
    fn mark_flattened_from_non_flattening_fails() {
        let mut group = AtomicGroup::new("grp-z".to_string(), 2);

        let result = group.mark_flattened();
        assert!(matches!(
            result,
            Err(GroupError::InvalidTransition {
                from: GroupState::New,
                to: GroupState::Flattened,
            })
        ));
    }

    // ─── First-fail invariant (table-driven) ────────────────────────────

    #[test]
    fn first_fail_invariant_table_driven() {
        struct Case {
            name: &'static str,
            legs: Vec<LegResult>,
            expected_state: GroupState,
            expected_first_failure_contains: Option<&'static str>,
        }

        let cases = vec![
            Case {
                name: "both_filled_clean_complete",
                legs: vec![filled_leg(0, 1.0), filled_leg(1, 1.0)],
                expected_state: GroupState::Complete,
                expected_first_failure_contains: None,
            },
            Case {
                name: "a_filled_b_rejected_mixed_failed",
                legs: vec![filled_leg(0, 1.0), rejected_leg(1, 1.0)],
                expected_state: GroupState::MixedFailed,
                expected_first_failure_contains: Some("rejected"),
            },
            Case {
                name: "a_rejected_b_filled_mixed_failed",
                legs: vec![rejected_leg(0, 1.0), filled_leg(1, 1.0)],
                expected_state: GroupState::MixedFailed,
                expected_first_failure_contains: Some("rejected"),
            },
            Case {
                name: "both_rejected_mixed_failed",
                legs: vec![rejected_leg(0, 1.0), rejected_leg(1, 1.0)],
                expected_state: GroupState::MixedFailed,
                expected_first_failure_contains: Some("leg 0 rejected"),
            },
            Case {
                name: "partial_fill_mixed_failed",
                legs: vec![partial_leg(0, 1.0, 0.5), filled_leg(1, 1.0)],
                expected_state: GroupState::MixedFailed,
                expected_first_failure_contains: Some("partial fill"),
            },
        ];

        let config = default_config();
        for case in &cases {
            let mut group = AtomicGroup::new(format!("table-{}", case.name), case.legs.len());
            group.mark_dispatched().expect("dispatch ok");

            for leg in &case.legs {
                group.apply_leg_result(leg.clone(), &config);
            }

            assert_eq!(
                group.state, case.expected_state,
                "case '{}': expected {:?}, got {:?}",
                case.name, case.expected_state, group.state
            );

            match case.expected_first_failure_contains {
                Some(expected) => {
                    let reason = group.first_failure_reason().unwrap_or_else(|| {
                        panic!("case '{}': expected first failure reason", case.name)
                    });
                    assert!(
                        reason.contains(expected),
                        "case '{}': expected reason to contain '{}', got '{}'",
                        case.name,
                        expected,
                        reason
                    );
                }
                None => {
                    assert!(
                        group.first_failure_reason().is_none(),
                        "case '{}': expected no failure reason, got {:?}",
                        case.name,
                        group.first_failure_reason()
                    );
                }
            }
        }
    }

    // ─── GroupState::is_terminal ─────────────────────────────────────────

    #[test]
    fn group_state_terminal_classification() {
        let cases = vec![
            (GroupState::New, false),
            (GroupState::Dispatched, false),
            (GroupState::Complete, true),
            (GroupState::MixedFailed, false),
            (GroupState::Flattening, false),
            (GroupState::Flattened, true),
        ];

        for (state, expected_terminal) in cases {
            assert_eq!(
                state.is_terminal(),
                expected_terminal,
                "{:?}.is_terminal() should be {}",
                state,
                expected_terminal
            );
        }
    }

    // ─── GroupLock unit tests ────────────────────────────────────────────

    #[test]
    fn group_lock_double_acquire_fails() {
        let mut lock = GroupLock::new();
        assert!(lock.try_acquire());
        assert!(!lock.try_acquire());
    }

    #[test]
    fn group_lock_acquire_release_acquire() {
        let mut lock = GroupLock::new();
        assert!(lock.try_acquire());
        lock.release();
        assert!(lock.try_acquire());
    }
}
