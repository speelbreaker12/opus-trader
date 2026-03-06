//! Contract-level integration tests for TLSM facade behavior.
//!
//! Metric-counter assertions (e.g. ooo_count/ooo_total) remain unit-level in
//! `src/execution/tlsm_tests.rs`.
//!
//! NOTE: `Tlsm::apply()` remains available only as a deprecated compatibility
//! shim. These tests intentionally use `apply_with_sink` with a local
//! `NoopSink` to keep the WAL-sink requirement explicit at the call site.

use soldier_core::execution::{
    PersistedTransition, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
};
use soldier_core::risk::ReservationId;

/// Local no-op sink — for test setup only. Production callers must supply a
/// durable WAL sink.
struct NoopSink;
impl TlsmTransitionSink for NoopSink {
    fn append_transition(&mut self, _t: PersistedTransition) -> Result<(), String> {
        Ok(())
    }
}

/// Convenience wrapper: drive `sm` through `event` using the local no-op sink.
/// Returns the `TransitionResult`, panicking on `TlsmError` (which cannot
/// happen with a no-op sink).
fn drive(sm: &mut Tlsm, event: TlsmEvent) -> TransitionResult {
    sm.apply_with_sink(event, &mut NoopSink)
        .expect("NoopSink never fails")
}

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
        drive(&mut sm, TlsmEvent::Sent),
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Sent
        }
    ));
    assert!(matches!(
        drive(&mut sm, TlsmEvent::Acked),
        TransitionResult::Transitioned {
            from: TlsmState::Sent,
            to: TlsmState::Acked
        }
    ));
    assert!(matches!(
        drive(&mut sm, TlsmEvent::PartialFill),
        TransitionResult::Transitioned {
            from: TlsmState::Acked,
            to: TlsmState::PartiallyFilled
        }
    ));
    assert!(matches!(
        drive(&mut sm, TlsmEvent::Filled),
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
    let _ = drive(&mut sm, TlsmEvent::Sent);

    let result = drive(&mut sm, TlsmEvent::Filled);
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
    let _ = drive(&mut sm, TlsmEvent::Sent);
    let _ = drive(&mut sm, TlsmEvent::Acked);
    let _ = drive(&mut sm, TlsmEvent::Filled);

    let result = drive(&mut sm, TlsmEvent::PartialFill);
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

    let _ = drive(&mut sm, TlsmEvent::Sent);
    let _ = drive(&mut sm, TlsmEvent::Acked);
    let _ = drive(&mut sm, TlsmEvent::Filled);

    let settled = sm.take_pending_reservation_on_terminal();
    assert_eq!(settled, Some((rid, "BTC-PERP".to_string())));
    assert_eq!(sm.take_pending_reservation_on_terminal(), None);
}
