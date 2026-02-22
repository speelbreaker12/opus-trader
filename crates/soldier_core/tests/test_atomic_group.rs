//! Integration tests for AtomicGroup state machine per CONTRACT.md §1.2.1.
//!
//! AT-116: Leg A filled, Leg B rejected → MixedFailed, containment, no OPENs until neutral.
//! AT-220: Out-of-order leg events → never Complete before B terminal, first failure triggers containment.
//! AT-924: Lock held > group_lock_max_wait_ms → hot loop doesn't block, ReduceOnly forced.
//! AT-936: MixedFailed + gate rejects rescue → no rescue submitted, emergency close runs.

use soldier_core::execution::TlsmState;
use soldier_core::execution::{
    AtomicGroup, GroupConfig, GroupError, GroupLock, GroupState, GroupStateTransition,
    InMemoryGroupPersistence, LegResult, LockAcquisitionResult, persist_before_dispatch,
    try_acquire_group_lock,
};

// ─── Helpers ────────────────────────────────────────────────────────────

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

// ═══════════════════════════════════════════════════════════════════════
// AT-116: Leg A filled, Leg B rejected → MixedFailed
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn at_116_leg_a_filled_leg_b_rejected_mixed_failed_and_containment() {
    let config = default_config();
    let mut group = AtomicGroup::new("at116-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // Leg A fills — group stays Dispatched
    let t = group.apply_leg_result(filled_leg(0, 1.0), &config);
    assert_eq!(t, GroupStateTransition::NoChange);
    assert_eq!(group.state, GroupState::Dispatched);

    // Leg B rejected — MixedFailed seeded
    let t = group.apply_leg_result(rejected_leg(1, 1.0), &config);
    assert!(
        matches!(t, GroupStateTransition::EnteredMixedFailed { .. }),
        "AT-116: expected MixedFailed, got {t:?}"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
    assert!(
        group.containment_pending,
        "AT-116: containment should be pending"
    );

    // No new OPENs dispatched (dispatch_count stays 0)
    assert_eq!(
        group.dispatch_count, 0,
        "AT-116: no OPEN dispatch while non-neutral"
    );

    // Verify: group cannot be marked Complete
    assert!(
        !group.can_complete(&config),
        "AT-116: MixedFailed group must not complete"
    );
}

#[test]
fn at_116_first_failure_reason_not_overwritten() {
    let config = default_config();
    let mut group = AtomicGroup::new("at116-overwrite".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // Leg B rejects first
    group.apply_leg_result(rejected_leg(1, 1.0), &config);
    let first = group.first_failure_reason().map(String::from);
    assert!(first.is_some(), "AT-116: first failure must be recorded");

    // Leg A fills later — first failure reason MUST NOT change
    group.apply_leg_result(filled_leg(0, 1.0), &config);
    assert_eq!(
        group.first_failure_reason().map(String::from),
        first,
        "AT-116: first failure reason must not be overwritten"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
}

// ═══════════════════════════════════════════════════════════════════════
// AT-220: Out-of-order leg events
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn at_220_never_complete_before_b_terminal() {
    let config = default_config();
    let mut group = AtomicGroup::new("at220-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // Leg A fills fast
    group.apply_leg_result(filled_leg(0, 1.0), &config);
    assert_ne!(
        group.state,
        GroupState::Complete,
        "AT-220: must not be Complete before B terminal"
    );

    // Leg B rejects late — first failure triggers containment
    let t = group.apply_leg_result(rejected_leg(1, 1.0), &config);
    assert!(
        matches!(t, GroupStateTransition::EnteredMixedFailed { .. }),
        "AT-220: first failure must trigger containment"
    );
    assert!(
        group.containment_pending,
        "AT-220: containment must be pending"
    );
}

#[test]
fn at_220_clean_both_fill_completes() {
    let config = default_config();
    let mut group = AtomicGroup::new("at220-clean".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // Leg A fills
    let t = group.apply_leg_result(filled_leg(0, 1.0), &config);
    assert_eq!(t, GroupStateTransition::NoChange);

    // Leg B fills — clean complete
    let t = group.apply_leg_result(filled_leg(1, 1.0), &config);
    assert_eq!(t, GroupStateTransition::Completed);
    assert_eq!(group.state, GroupState::Complete);
    assert!(group.can_complete(&config) || group.state == GroupState::Complete);
}

// ═══════════════════════════════════════════════════════════════════════
// AT-924: Lock timeout → ReduceOnly
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn at_924_lock_held_beyond_timeout_no_block_reduce_only() {
    // Use 0ms timeout so any held lock is immediately "expired"
    let config = GroupConfig {
        group_lock_max_wait_ms: 0,
        ..Default::default()
    };
    let mut lock = GroupLock::new();

    // Acquire lock (simulates another thread holding it)
    assert!(lock.try_acquire());

    // Hot loop attempts to acquire — must not block, must return TimedOut
    let result = try_acquire_group_lock(&mut lock, &config);
    assert_eq!(
        result,
        LockAcquisitionResult::TimedOut,
        "AT-924: must not block, must return TimedOut"
    );
    // Caller is responsible for forcing ReduceOnly and blocking OPEN
}

#[test]
fn at_924_lock_free_acquires_normally() {
    let config = default_config();
    let mut lock = GroupLock::new();

    let result = try_acquire_group_lock(&mut lock, &config);
    assert_eq!(result, LockAcquisitionResult::Acquired);
    assert!(lock.is_held());
}

#[test]
fn at_924_lock_release_allows_reacquire() {
    let config = default_config();
    let mut lock = GroupLock::new();

    lock.try_acquire();
    lock.release();

    let result = try_acquire_group_lock(&mut lock, &config);
    assert_eq!(result, LockAcquisitionResult::Acquired);
}

// ═══════════════════════════════════════════════════════════════════════
// AT-936: MixedFailed + gate rejects rescue → emergency close
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn at_936_rescue_rejected_no_rescue_dispatch_emergency_close() {
    let config = default_config();
    let mut group = AtomicGroup::new("at936-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // Set up MixedFailed: Leg A filled, Leg B rejected
    group.apply_leg_result(filled_leg(0, 1.0), &config);
    group.apply_leg_result(rejected_leg(1, 1.0), &config);
    assert_eq!(group.state, GroupState::MixedFailed);

    // Simulate: LiquidityGate/NetEdge reject rescue orders
    // rescue_dispatch_count stays 0
    assert_eq!(
        group.rescue_dispatch_count, 0,
        "AT-936: no rescue orders submitted under gate reject"
    );

    // Emergency close path: MixedFailed → Flattening → Flattened
    group.mark_flattening().expect("flattening ok");
    assert_eq!(group.state, GroupState::Flattening);

    group.mark_flattened().expect("flattened ok");
    assert_eq!(group.state, GroupState::Flattened);
    assert!(
        !group.containment_pending,
        "AT-936: containment resolved after flatten"
    );
}

// ═══════════════════════════════════════════════════════════════════════
// Persistence before dispatch
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn persist_before_dispatch_success_records_group() {
    let group = AtomicGroup::new("persist-ok".to_string(), 2);
    let mut store = InMemoryGroupPersistence::default();

    let result = persist_before_dispatch(&group, &mut store);
    assert!(result.is_ok());
    assert_eq!(store.persisted_intents, vec!["persist-ok"]);
}

#[test]
fn persist_before_dispatch_failure_must_abort() {
    let group = AtomicGroup::new("persist-fail".to_string(), 2);
    let mut store = InMemoryGroupPersistence {
        fail_persist: true,
        ..Default::default()
    };

    let result = persist_before_dispatch(&group, &mut store);
    assert!(
        matches!(result, Err(GroupError::PersistenceFailed { .. })),
        "persistence failure must abort — no leg dispatch allowed"
    );
}

// ═══════════════════════════════════════════════════════════════════════
// State transition guards
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn flattening_only_from_mixed_failed() {
    let mut group = AtomicGroup::new("guard-1".to_string(), 2);
    group.mark_dispatched().expect("ok");

    // Dispatched → Flattening should fail
    let result = group.mark_flattening();
    assert!(matches!(
        result,
        Err(GroupError::InvalidTransition {
            from: GroupState::Dispatched,
            ..
        })
    ));
}

#[test]
fn flattened_only_from_flattening() {
    let config = default_config();
    let mut group = AtomicGroup::new("guard-2".to_string(), 2);
    group.mark_dispatched().expect("ok");
    group.apply_leg_result(rejected_leg(0, 1.0), &config);
    assert_eq!(group.state, GroupState::MixedFailed);

    // MixedFailed → Flattened should fail (must go through Flattening)
    let result = group.mark_flattened();
    assert!(matches!(
        result,
        Err(GroupError::InvalidTransition {
            from: GroupState::MixedFailed,
            ..
        })
    ));
}

#[test]
fn partial_fill_triggers_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("partial-grp".to_string(), 2);
    group.mark_dispatched().expect("ok");

    // Partial fill on first leg
    let t = group.apply_leg_result(partial_leg(0, 1.0, 0.5), &config);
    assert!(
        matches!(t, GroupStateTransition::EnteredMixedFailed { .. }),
        "partial fill must trigger MixedFailed"
    );
    assert!(
        group
            .first_failure_reason()
            .expect("reason")
            .contains("partial fill")
    );
}

// ─── Devils-advocate: no MixedFailed re-entry from Flattening/Flattened ──

/// Catches mutation: remove Flattening/Flattened guard from failure re-entry
/// in apply_leg_result. A failure leg applied AFTER entering Flattening must
/// NOT re-enter MixedFailed — the containment path is already in progress.
#[test]
fn failure_leg_during_flattening_does_not_reenter_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("guard-flatten".to_string(), 3);
    group.mark_dispatched().expect("ok");

    // Leg A rejected → MixedFailed
    group.apply_leg_result(rejected_leg(0, 1.0), &config);
    assert_eq!(group.state, GroupState::MixedFailed);

    // Enter Flattening (emergency close in progress)
    group.mark_flattening().expect("ok");
    assert_eq!(group.state, GroupState::Flattening);

    // Leg B arrives rejected AFTER flattening started — must NOT re-enter MixedFailed
    let t = group.apply_leg_result(rejected_leg(1, 1.0), &config);
    assert_eq!(
        t,
        GroupStateTransition::NoChange,
        "failure during Flattening must be NoChange, not re-enter MixedFailed"
    );
    assert_eq!(
        group.state,
        GroupState::Flattening,
        "state must remain Flattening"
    );
}

#[test]
fn failure_leg_during_flattened_does_not_reenter_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("guard-flattened".to_string(), 3);
    group.mark_dispatched().expect("ok");

    // Leg A rejected → MixedFailed → Flattening → Flattened
    group.apply_leg_result(rejected_leg(0, 1.0), &config);
    group.mark_flattening().expect("ok");
    group.mark_flattened().expect("ok");
    assert_eq!(group.state, GroupState::Flattened);

    // Late leg B arrives rejected AFTER fully flattened — must NOT re-enter MixedFailed
    let t = group.apply_leg_result(rejected_leg(1, 1.0), &config);
    assert_eq!(
        t,
        GroupStateTransition::NoChange,
        "failure during Flattened must be NoChange, not re-enter MixedFailed"
    );
    assert_eq!(
        group.state,
        GroupState::Flattened,
        "state must remain Flattened"
    );
}

// ═══════════════════════════════════════════════════════════════════════
// S7-AUD-005 Q4: NaN fill quantities → fail-closed MixedFailed
// ═══════════════════════════════════════════════════════════════════════

#[test]
fn nan_filled_qty_forces_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("nan-fill-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    let result = LegResult {
        leg_idx: 0,
        requested_qty: 1.0,
        filled_qty: f64::NAN,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let transition = group.apply_leg_result(result, &config);
    assert!(
        matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
        "NaN filled_qty must force MixedFailed, got {transition:?}"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
    assert!(
        group.containment_pending,
        "containment must be pending on NaN"
    );
    assert!(
        group
            .first_failure_reason()
            .expect("must have reason")
            .contains("non-finite"),
        "reason must mention non-finite"
    );
}

#[test]
fn nan_requested_qty_forces_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("nan-req-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    let result = LegResult {
        leg_idx: 0,
        requested_qty: f64::NAN,
        filled_qty: 1.0,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let transition = group.apply_leg_result(result, &config);
    assert!(
        matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
        "NaN requested_qty must force MixedFailed, got {transition:?}"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
    assert!(
        group
            .first_failure_reason()
            .expect("must have reason")
            .contains("non-finite"),
        "reason must mention non-finite"
    );
}

#[test]
fn nan_both_legs_second_returns_still_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("nan-both-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    // First NaN leg → EnteredMixedFailed
    let leg0 = LegResult {
        leg_idx: 0,
        requested_qty: 1.0,
        filled_qty: f64::NAN,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let t0 = group.apply_leg_result(leg0, &config);
    assert!(
        matches!(t0, GroupStateTransition::EnteredMixedFailed { .. }),
        "first NaN leg must enter MixedFailed"
    );

    // Second NaN leg → StillMixedFailed (already in MixedFailed)
    let leg1 = LegResult {
        leg_idx: 1,
        requested_qty: f64::NAN,
        filled_qty: f64::NAN,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let t1 = group.apply_leg_result(leg1, &config);
    assert_eq!(
        t1,
        GroupStateTransition::StillMixedFailed,
        "second NaN leg on already-MixedFailed must return StillMixedFailed"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
}

#[test]
fn inf_filled_qty_forces_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("inf-fill-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    let result = LegResult {
        leg_idx: 0,
        requested_qty: 1.0,
        filled_qty: f64::INFINITY,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let transition = group.apply_leg_result(result, &config);
    assert!(
        matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
        "Inf filled_qty must force MixedFailed, got {transition:?}"
    );
    assert_eq!(group.state, GroupState::MixedFailed);
}

#[test]
fn inf_requested_qty_forces_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("inf-req-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    let result = LegResult {
        leg_idx: 0,
        requested_qty: f64::INFINITY,
        filled_qty: 1.0,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let transition = group.apply_leg_result(result, &config);
    assert!(
        matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
        "Inf requested_qty must force MixedFailed, got {transition:?}"
    );
}

#[test]
fn neg_inf_filled_qty_forces_mixed_failed() {
    let config = default_config();
    let mut group = AtomicGroup::new("neginf-fill-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    let result = LegResult {
        leg_idx: 0,
        requested_qty: 1.0,
        filled_qty: f64::NEG_INFINITY,
        rejected: false,
        unfilled: false,
        tlsm_state: TlsmState::Filled,
    };
    let transition = group.apply_leg_result(result, &config);
    assert!(
        matches!(transition, GroupStateTransition::EnteredMixedFailed { .. }),
        "-Inf filled_qty must force MixedFailed, got {transition:?}"
    );
}

#[test]
fn nan_atomic_qty_epsilon_prevents_false_complete() {
    let config = GroupConfig {
        atomic_qty_epsilon: f64::NAN,
        ..Default::default()
    };
    let mut group = AtomicGroup::new("nan-eps-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    group.apply_leg_result(filled_leg(0, 1.0), &config);
    group.apply_leg_result(filled_leg(1, 1.0), &config);

    assert!(
        !group.can_complete(&config),
        "NaN atomic_qty_epsilon must prevent Complete (fail-closed)"
    );
}

#[test]
fn negative_atomic_qty_epsilon_prevents_false_complete() {
    let config = GroupConfig {
        atomic_qty_epsilon: -1.0,
        ..Default::default()
    };
    let mut group = AtomicGroup::new("neg-eps-grp".to_string(), 2);
    group.mark_dispatched().expect("dispatch ok");

    group.apply_leg_result(filled_leg(0, 1.0), &config);
    group.apply_leg_result(filled_leg(1, 1.0), &config);

    assert!(
        !group.can_complete(&config),
        "Negative atomic_qty_epsilon must prevent Complete (fail-closed)"
    );
}

#[test]
fn try_acquire_at_deterministic_timestamp() {
    use std::time::{Duration, Instant};

    let mut lock = GroupLock::new();
    let now = Instant::now();

    assert!(
        lock.try_acquire_at(now),
        "lock must be acquirable when free"
    );
    assert!(lock.is_held(), "lock must be held after acquire_at");

    let later = now + Duration::from_millis(5);
    assert!(
        !lock.try_acquire_at(later),
        "double acquire_at must fail while held"
    );

    lock.release();
    assert!(!lock.is_held());
    assert!(
        lock.try_acquire_at(later),
        "lock must be acquirable after release"
    );
    assert!(lock.is_held());
}
