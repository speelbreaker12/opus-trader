//! Contract-level integration tests for TLSM facade behavior.
//!
//! Metric-counter assertions (e.g. ooo_count/ooo_total) remain unit-level in
//! `src/execution/tlsm_tests.rs`.

use soldier_core::execution::{
    PersistedTransition, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
};
use soldier_core::risk::ReservationId;

#[derive(Default)]
struct CollectingSink {
    transitions: Vec<PersistedTransition>,
}

impl TlsmTransitionSink for CollectingSink {
    fn append_transition(&mut self, transition: PersistedTransition) -> Result<(), String> {
        self.transitions.push(transition);
        Ok(())
    }
}

#[test]
fn test_normal_lifecycle_created_to_filled() {
    let mut sm = Tlsm::new();
    assert_eq!(sm.state(), TlsmState::Created);

    assert!(matches!(
        sm.apply(TlsmEvent::Sent),
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Sent
        }
    ));
    assert!(matches!(
        sm.apply(TlsmEvent::Acked),
        TransitionResult::Transitioned {
            from: TlsmState::Sent,
            to: TlsmState::Acked
        }
    ));
    assert!(matches!(
        sm.apply(TlsmEvent::PartialFill),
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::PartiallyFilled
        }
    ));
    assert!(matches!(
        sm.apply(TlsmEvent::Filled),
        TransitionResult::Transitioned {
            from: TlsmState::PartiallyFilled,
            to: TlsmState::Filled
        }
    ));
    assert!(sm.state().is_terminal());
    assert_eq!(sm.transition_count(), 4);
}

#[test]
fn test_fill_before_ack_is_out_of_order_but_accepted() {
    let mut sm = Tlsm::new();
    let _ = sm.apply(TlsmEvent::Sent);

    let result = sm.apply(TlsmEvent::Filled);
    assert!(matches!(
        result,
        TransitionResult::OutOfOrder {
            from: TlsmState::Sent,
            to: TlsmState::Filled,
            ..
        }
    ));
    assert_eq!(sm.state(), TlsmState::Filled);
}

#[test]
fn test_terminal_state_ignores_late_events() {
    let mut sm = Tlsm::new();
    let _ = sm.apply(TlsmEvent::Sent);
    let _ = sm.apply(TlsmEvent::Acked);
    let _ = sm.apply(TlsmEvent::Filled);

    let result = sm.apply(TlsmEvent::PartialFill);
    assert!(matches!(
        result,
        TransitionResult::Ignored {
            current: TlsmState::Filled,
            ..
        }
    ));
}

#[test]
fn test_apply_with_sink_persists_transitions() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    let _ = sm.apply_with_sink(TlsmEvent::Sent, &mut sink);
    let _ = sm.apply_with_sink(TlsmEvent::Acked, &mut sink);

    assert_eq!(sink.transitions.len(), 2);
    assert_eq!(sink.transitions[0].from, TlsmState::Created);
    assert_eq!(sink.transitions[0].to, TlsmState::Sent);
    assert_eq!(sink.transitions[1].from, TlsmState::Sent);
    assert_eq!(sink.transitions[1].to, TlsmState::Acked);
}

#[test]
fn test_pending_reservation_settles_once_at_terminal() {
    let rid = match ReservationId::new("rid-tlsm-001") {
        Some(value) => value,
        None => panic!("invalid reservation id fixture"),
    };
    let mut sm = Tlsm::with_pending_reservation(rid.clone(), "BTC-PERP".to_string());

    assert_eq!(sm.take_pending_reservation_on_terminal(), None);

    let _ = sm.apply(TlsmEvent::Sent);
    let _ = sm.apply(TlsmEvent::Acked);
    let _ = sm.apply(TlsmEvent::Filled);

    let settled = sm.take_pending_reservation_on_terminal();
    assert_eq!(settled, Some((rid, "BTC-PERP".to_string())));
    assert_eq!(sm.take_pending_reservation_on_terminal(), None);
}
