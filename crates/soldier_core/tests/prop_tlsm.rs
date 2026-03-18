//! Property-based tests for the Trade Lifecycle State Machine (CONTRACT.md §2.1).
//!
//! Properties under test:
//! - Terminal states (Filled, Cancelled, Failed) absorb all events.
//! - No panic on arbitrary event sequences.
//! - Fill-before-ack from Sent produces OutOfOrder, not panic.
//! - Transition count == number of non-Ignored events.
//! - State after terminal event remains terminal for all future events.
//!
//! NOTE: `Tlsm::apply()` is test-only inside the crate. These integration
//! tests intentionally use `apply_with_sink` with a local `NoopSink` helper
//! so the sink requirement stays explicit.

use proptest::prelude::*;
use soldier_core::execution::{
    PersistedTransition, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
};

/// Local no-op sink — for test setup only. Production callers must supply a
/// durable WAL sink.
struct NoopSink;
impl TlsmTransitionSink for NoopSink {
    fn append_transition(&mut self, _t: PersistedTransition) -> Result<(), String> {
        Ok(())
    }
}

/// Convenience wrapper: drive `sm` through `event` using the local no-op sink.
fn drive(sm: &mut Tlsm, event: TlsmEvent) -> TransitionResult {
    sm.apply_with_sink(event, &mut NoopSink)
        .expect("NoopSink never fails")
}

fn event_strategy() -> impl Strategy<Value = TlsmEvent> {
    prop_oneof![
        Just(TlsmEvent::Sent),
        Just(TlsmEvent::Acked),
        Just(TlsmEvent::PartialFill),
        Just(TlsmEvent::Filled),
        Just(TlsmEvent::Cancelled),
        Just(TlsmEvent::Rejected),
        Just(TlsmEvent::Failed),
    ]
}

fn event_sequence(max_len: usize) -> impl Strategy<Value = Vec<TlsmEvent>> {
    prop::collection::vec(event_strategy(), 0..=max_len)
}

proptest! {
    #![proptest_config(ProptestConfig::with_cases(
        std::env::var("PROPTEST_CASES")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(256)
    ))]

    /// TLSM never panics on any sequence of events.
    #[test]
    fn never_panics_on_arbitrary_sequence(events in event_sequence(50)) {
        let mut tlsm = Tlsm::new();
        for event in events {
            let _ = drive(&mut tlsm, event);
        }
    }

    /// Terminal states absorb all subsequent events as Ignored.
    #[test]
    fn terminal_states_absorb_all_events(
        prefix in event_sequence(20),
        suffix in event_sequence(20),
    ) {
        let mut tlsm = Tlsm::new();

        // Apply prefix events
        for event in &prefix {
            let _ = drive(&mut tlsm, event.clone());
        }

        // If we're in a terminal state, all future events must be Ignored
        if tlsm.state().is_terminal() {
            let terminal_state = tlsm.state();
            let transition_count_before = tlsm.transition_count();

            for event in suffix {
                let result = drive(&mut tlsm, event);
                prop_assert!(
                    matches!(result, TransitionResult::Ignored { .. }),
                    "terminal state {:?} did not ignore event, got {:?}",
                    terminal_state, result
                );
            }

            // State must not change
            prop_assert_eq!(tlsm.state(), terminal_state);
            // Transition count must not change (Ignored events don't record)
            prop_assert_eq!(tlsm.transition_count(), transition_count_before);
        }
    }

    /// Transition count equals the number of non-Ignored apply_with_sink() results.
    #[test]
    fn transition_count_matches_non_ignored(events in event_sequence(30)) {
        let mut tlsm = Tlsm::new();
        let mut expected_count = 0_usize;

        for event in events {
            let result = drive(&mut tlsm, event);
            match result {
                TransitionResult::Transitioned { .. } | TransitionResult::OutOfOrder { .. } => {
                    expected_count += 1;
                }
                TransitionResult::Ignored { .. } => {}
            }
        }

        prop_assert_eq!(
            tlsm.transition_count(), expected_count,
            "transition_count={} != expected={}",
            tlsm.transition_count(), expected_count
        );
    }

    /// Fill-before-ack from Sent produces OutOfOrder (not Ignored or panic).
    #[test]
    fn fill_before_ack_is_out_of_order(event in prop_oneof![
        Just(TlsmEvent::Filled),
        Just(TlsmEvent::PartialFill),
    ]) {
        let mut tlsm = Tlsm::new();
        // Move to Sent state
        let sent_result = drive(&mut tlsm, TlsmEvent::Sent);
        let is_transitioned = matches!(sent_result, TransitionResult::Transitioned { .. });
        prop_assert!(is_transitioned, "Sent should produce Transitioned");
        prop_assert_eq!(tlsm.state(), TlsmState::Sent);

        // Fill/PartialFill before Ack should be OutOfOrder
        let result = drive(&mut tlsm, event);
        prop_assert!(
            matches!(result, TransitionResult::OutOfOrder { .. }),
            "fill-before-ack should be OutOfOrder, got {:?}", result
        );
    }

    /// Once a terminal state is reached, is_terminal() always returns true.
    #[test]
    fn terminal_flag_is_sticky(events in event_sequence(30)) {
        let mut tlsm = Tlsm::new();
        let mut reached_terminal = false;

        for event in events {
            let _ = drive(&mut tlsm, event);
            if tlsm.state().is_terminal() {
                reached_terminal = true;
            }
            if reached_terminal {
                prop_assert!(
                    tlsm.state().is_terminal(),
                    "state became non-terminal after being terminal"
                );
            }
        }
    }

    /// Created is the initial state; first Sent event produces Transitioned.
    #[test]
    fn initial_state_is_created(_dummy in 0..1u8) {
        let tlsm = Tlsm::new();
        prop_assert_eq!(tlsm.state(), TlsmState::Created);
        prop_assert_eq!(tlsm.transition_count(), 0);
    }

    /// Normal happy path: Created->Sent->Acked->Filled is all Transitioned.
    #[test]
    fn happy_path_is_all_transitioned(_dummy in 0..1u8) {
        let mut tlsm = Tlsm::new();
        let events = vec![TlsmEvent::Sent, TlsmEvent::Acked, TlsmEvent::Filled];
        for event in events {
            let result = drive(&mut tlsm, event);
            prop_assert!(
                matches!(result, TransitionResult::Transitioned { .. }),
                "happy path event should be Transitioned, got {:?}", result
            );
        }
        prop_assert_eq!(tlsm.state(), TlsmState::Filled);
        prop_assert!(tlsm.state().is_terminal());
    }
}
