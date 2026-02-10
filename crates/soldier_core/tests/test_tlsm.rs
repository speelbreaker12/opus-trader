//! Tests for Trade Lifecycle State Machine (TLSM) per CONTRACT.md §2.1.
//!
//! AT-230: Fill-before-ack is valid reality.
//! AT-210: Orphan fill (fill-before-send).

use soldier_core::execution::{Tlsm, TlsmEvent, TlsmState, TransitionResult};

// ─── Normal lifecycle ────────────────────────────────────────────────────

#[test]
fn test_normal_lifecycle_created_to_filled() {
    let mut sm = Tlsm::new();
    assert_eq!(sm.state(), TlsmState::Created);

    // Created → Sent
    let r = sm.apply(TlsmEvent::Sent);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Sent
        }
    ));

    // Sent → Acked
    let r = sm.apply(TlsmEvent::Acked);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Sent,
            to: TlsmState::Acked
        }
    ));

    // Acked → PartiallyFilled
    let r = sm.apply(TlsmEvent::PartialFill);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::PartiallyFilled
        }
    ));

    // PartiallyFilled → Filled
    let r = sm.apply(TlsmEvent::Filled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::PartiallyFilled,
            to: TlsmState::Filled
        }
    ));

    assert!(sm.state().is_terminal());
    assert_eq!(sm.transition_count(), 4);
}

#[test]
fn test_normal_lifecycle_acked_to_filled_direct() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);

    // Acked → Filled (skip partial)
    let r = sm.apply(TlsmEvent::Filled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::Filled
        }
    ));
}

#[test]
fn test_multiple_partial_fills() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    sm.apply(TlsmEvent::PartialFill);

    // PartiallyFilled → PartiallyFilled (another partial)
    let r = sm.apply(TlsmEvent::PartialFill);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::PartiallyFilled,
            to: TlsmState::PartiallyFilled
        }
    ));
    assert_eq!(sm.state(), TlsmState::PartiallyFilled);
}

// ─── Terminal state ignoring ─────────────────────────────────────────────

#[test]
fn test_terminal_state_ignores_all_events() {
    let events = vec![
        TlsmEvent::Sent,
        TlsmEvent::Acked,
        TlsmEvent::PartialFill,
        TlsmEvent::Filled,
        TlsmEvent::Cancelled,
        TlsmEvent::Rejected,
        TlsmEvent::Failed,
    ];

    for event in events {
        let mut sm = Tlsm::new();
        sm.apply(TlsmEvent::Sent);
        sm.apply(TlsmEvent::Acked);
        sm.apply(TlsmEvent::Filled); // terminal

        let r = sm.apply(event);
        assert!(
            matches!(r, TransitionResult::Ignored { .. }),
            "event after terminal should be ignored"
        );
        assert_eq!(sm.state(), TlsmState::Filled);
    }
}

#[test]
fn test_cancelled_is_terminal() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Cancelled);

    assert!(sm.state().is_terminal());
    let r = sm.apply(TlsmEvent::Acked);
    assert!(matches!(r, TransitionResult::Ignored { .. }));
}

#[test]
fn test_failed_is_terminal() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Failed);

    assert!(sm.state().is_terminal());
    let r = sm.apply(TlsmEvent::Filled);
    assert!(matches!(r, TransitionResult::Ignored { .. }));
}

// ─── Cancel from any non-terminal ────────────────────────────────────────

#[test]
fn test_cancel_from_created() {
    let mut sm = Tlsm::new();
    let r = sm.apply(TlsmEvent::Cancelled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Cancelled
        }
    ));
}

#[test]
fn test_cancel_from_sent() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    let r = sm.apply(TlsmEvent::Cancelled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Sent,
            to: TlsmState::Cancelled
        }
    ));
}

#[test]
fn test_cancel_from_acked() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    let r = sm.apply(TlsmEvent::Cancelled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::Cancelled
        }
    ));
}

#[test]
fn test_cancel_from_partially_filled() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    sm.apply(TlsmEvent::PartialFill);
    let r = sm.apply(TlsmEvent::Cancelled);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::PartiallyFilled,
            to: TlsmState::Cancelled
        }
    ));
}

// ─── Rejection ───────────────────────────────────────────────────────────

#[test]
fn test_reject_from_created() {
    let mut sm = Tlsm::new();
    let r = sm.apply(TlsmEvent::Rejected);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Failed
        }
    ));
}

#[test]
fn test_reject_from_sent() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    let r = sm.apply(TlsmEvent::Rejected);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Sent,
            to: TlsmState::Failed
        }
    ));
}

// ─── Failed from any non-terminal ────────────────────────────────────────

#[test]
fn test_failed_from_acked() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    let r = sm.apply(TlsmEvent::Failed);
    assert!(matches!(
        r,
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::Failed
        }
    ));
}

// ─── AT-230: Fill-before-ack ─────────────────────────────────────────────

#[test]
fn test_at230_fill_before_ack() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);

    // Fill arrives before Ack — CONTRACT.md: "Fill-before-Ack is valid reality"
    let r = sm.apply(TlsmEvent::Filled);
    match r {
        TransitionResult::OutOfOrder {
            from,
            to,
            ref anomaly,
        } => {
            assert_eq!(from, TlsmState::Sent);
            assert_eq!(to, TlsmState::Filled);
            assert!(anomaly.contains("fill-before-ack"));
        }
        other => panic!("expected OutOfOrder, got {other:?}"),
    }
    assert_eq!(sm.state(), TlsmState::Filled);
}

#[test]
fn test_at230_partial_fill_before_ack() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);

    let r = sm.apply(TlsmEvent::PartialFill);
    match r {
        TransitionResult::OutOfOrder {
            from,
            to,
            ref anomaly,
        } => {
            assert_eq!(from, TlsmState::Sent);
            assert_eq!(to, TlsmState::PartiallyFilled);
            assert!(anomaly.contains("partial-fill-before-ack"));
        }
        other => panic!("expected OutOfOrder, got {other:?}"),
    }
    assert_eq!(sm.state(), TlsmState::PartiallyFilled);
}

// ─── AT-210: Orphan fill (fill-before-send) ──────────────────────────────

#[test]
fn test_at210_fill_before_send() {
    let mut sm = Tlsm::new();

    // Fill arrives before order even sent — orphan fill
    let r = sm.apply(TlsmEvent::Filled);
    match r {
        TransitionResult::OutOfOrder {
            from,
            to,
            ref anomaly,
        } => {
            assert_eq!(from, TlsmState::Created);
            assert_eq!(to, TlsmState::Filled);
            assert!(anomaly.contains("orphan fill"));
        }
        other => panic!("expected OutOfOrder, got {other:?}"),
    }
    assert_eq!(sm.state(), TlsmState::Filled);
}

#[test]
fn test_at210_partial_fill_before_send() {
    let mut sm = Tlsm::new();

    let r = sm.apply(TlsmEvent::PartialFill);
    match r {
        TransitionResult::OutOfOrder {
            from,
            to,
            ref anomaly,
        } => {
            assert_eq!(from, TlsmState::Created);
            assert_eq!(to, TlsmState::PartiallyFilled);
            assert!(anomaly.contains("partial-fill-before-send"));
        }
        other => panic!("expected OutOfOrder, got {other:?}"),
    }
}

#[test]
fn test_ack_before_send() {
    let mut sm = Tlsm::new();

    let r = sm.apply(TlsmEvent::Acked);
    match r {
        TransitionResult::OutOfOrder {
            from,
            to,
            ref anomaly,
        } => {
            assert_eq!(from, TlsmState::Created);
            assert_eq!(to, TlsmState::Acked);
            assert!(anomaly.contains("ack-before-send"));
        }
        other => panic!("expected OutOfOrder, got {other:?}"),
    }
}

// ─── Late ack after fills ────────────────────────────────────────────────

#[test]
fn test_late_ack_after_partial_fill_ignored() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    sm.apply(TlsmEvent::PartialFill);

    // Late ack arrives after partial fill
    let r = sm.apply(TlsmEvent::Acked);
    assert!(matches!(r, TransitionResult::Ignored { .. }));
    assert_eq!(sm.state(), TlsmState::PartiallyFilled);
}

// ─── Never panic ─────────────────────────────────────────────────────────

#[test]
fn test_never_panic_random_events() {
    // CONTRACT.md §2.1: "Never panic on out-of-order WS events"
    let events = vec![
        TlsmEvent::Sent,
        TlsmEvent::Acked,
        TlsmEvent::PartialFill,
        TlsmEvent::Filled,
        TlsmEvent::Cancelled,
        TlsmEvent::Rejected,
        TlsmEvent::Failed,
    ];

    // Apply all events from Created — should not panic
    for event in &events {
        let mut sm = Tlsm::new();
        let _ = sm.apply(event.clone());
    }

    // Apply all events from Sent — should not panic
    for event in &events {
        let mut sm = Tlsm::new();
        sm.apply(TlsmEvent::Sent);
        let _ = sm.apply(event.clone());
    }

    // Apply all events from Acked — should not panic
    for event in &events {
        let mut sm = Tlsm::new();
        sm.apply(TlsmEvent::Sent);
        sm.apply(TlsmEvent::Acked);
        let _ = sm.apply(event.clone());
    }
}

// ─── State terminal checks ──────────────────────────────────────────────

#[test]
fn test_terminal_states() {
    assert!(TlsmState::Filled.is_terminal());
    assert!(TlsmState::Cancelled.is_terminal());
    assert!(TlsmState::Failed.is_terminal());
}

#[test]
fn test_non_terminal_states() {
    assert!(!TlsmState::Created.is_terminal());
    assert!(!TlsmState::Sent.is_terminal());
    assert!(!TlsmState::Acked.is_terminal());
    assert!(!TlsmState::PartiallyFilled.is_terminal());
}

// ─── Default ─────────────────────────────────────────────────────────────

#[test]
fn test_default_creates_in_created_state() {
    let sm = Tlsm::default();
    assert_eq!(sm.state(), TlsmState::Created);
    assert_eq!(sm.transition_count(), 0);
}

// ─── Duplicate event ignored ─────────────────────────────────────────────

#[test]
fn test_duplicate_sent_ignored() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);

    // Second Sent — no valid transition from Sent+Sent
    let r = sm.apply(TlsmEvent::Sent);
    assert!(matches!(r, TransitionResult::Ignored { .. }));
    assert_eq!(sm.state(), TlsmState::Sent);
}

#[test]
fn test_reject_from_acked_ignored() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);

    // Reject only valid from Created/Sent
    let r = sm.apply(TlsmEvent::Rejected);
    assert!(matches!(r, TransitionResult::Ignored { .. }));
    assert_eq!(sm.state(), TlsmState::Acked);
}
