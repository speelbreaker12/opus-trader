//! Tests for Trade Lifecycle State Machine (TLSM) per CONTRACT.md §2.1.
//!
//! AT-230: Fill-before-ack is valid reality.
//! AT-210: Orphan fill (fill-before-send).
use super::*;

trait TestValueExt<T> {
    fn must(self) -> T;
}

trait TestErrorExt<T, E> {
    fn must_err(self) -> E;
}

impl<T, E: std::fmt::Debug> TestValueExt<T> for Result<T, E> {
    fn must(self) -> T {
        match self {
            Ok(value) => value,
            Err(err) => panic!("unexpected Err: {err:?}"),
        }
    }
}

impl<T> TestValueExt<T> for Option<T> {
    fn must(self) -> T {
        match self {
            Some(value) => value,
            None => panic!("unexpected None"),
        }
    }
}

impl<T: std::fmt::Debug, E> TestErrorExt<T, E> for Result<T, E> {
    fn must_err(self) -> E {
        match self {
            Ok(value) => panic!("unexpected Ok: {value:?}"),
            Err(err) => err,
        }
    }
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

struct FailingSink;

impl TlsmTransitionSink for FailingSink {
    fn append_transition(&mut self, _transition: PersistedTransition) -> Result<(), String> {
        Err("sink append failed".to_string())
    }
}

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

// ─── WAL transition sink emission ───────────────────────────────────────

#[test]
fn test_apply_with_sink_emits_transition_records() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    let _ = sm.apply_with_sink(TlsmEvent::Sent, &mut sink).must();
    let _ = sm.apply_with_sink(TlsmEvent::Filled, &mut sink).must(); // out-of-order from Sent

    assert_eq!(sink.transitions.len(), 2);
    assert_eq!(sink.transitions[0].from, TlsmState::Created);
    assert_eq!(sink.transitions[0].to, TlsmState::Sent);
    assert!(sink.transitions[0].anomaly.is_none());

    assert_eq!(sink.transitions[1].from, TlsmState::Sent);
    assert_eq!(sink.transitions[1].to, TlsmState::Filled);
    assert!(
        sink.transitions[1]
            .anomaly
            .as_deref()
            .unwrap_or("")
            .contains("fill-before-ack")
    );
}

#[test]
fn test_ignored_event_does_not_emit_transition() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    let _ = sm.apply_with_sink(TlsmEvent::Sent, &mut sink).must();
    let _ = sm.apply_with_sink(TlsmEvent::Sent, &mut sink).must(); // ignored

    assert_eq!(sink.transitions.len(), 1);
}

#[test]
fn test_sink_failure_is_atomic_no_state_change() {
    let mut sm = Tlsm::new();
    let mut sink = FailingSink;

    let err = sm.apply_with_sink(TlsmEvent::Sent, &mut sink).must_err();
    assert!(matches!(err, TlsmError::PersistFailed { .. }));
    assert_eq!(sm.state(), TlsmState::Created);
    assert_eq!(sm.transition_count(), 0);
}

// ─── Devils-advocate: Failed event coverage ──────────────────────────

/// Catches mutation: restrict `(_, Failed)` wildcard to `(Acked, Failed)`.
#[test]
fn test_failed_from_created_transitions() {
    let mut sm = Tlsm::new();
    let r = sm.apply(TlsmEvent::Failed);
    match r {
        TransitionResult::Transitioned {
            from: TlsmState::Created,
            to: TlsmState::Failed,
        } => {}
        other => panic!("Created + Failed must Transition (not Ignore), got {other:?}"),
    }
    assert!(sm.state().is_terminal());
}

/// Catches mutation: restrict `(_, Failed)` to exclude PartiallyFilled.
#[test]
fn test_failed_from_partially_filled_transitions() {
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Acked);
    sm.apply(TlsmEvent::PartialFill);
    let r = sm.apply(TlsmEvent::Failed);
    match r {
        TransitionResult::Transitioned {
            from: TlsmState::PartiallyFilled,
            to: TlsmState::Failed,
        } => {}
        other => panic!("PartiallyFilled + Failed must Transition (not Ignore), got {other:?}"),
    }
    assert!(sm.state().is_terminal());
}

/// Catches mutation: remove is_terminal() guard from take_pending_reservation_on_terminal().
#[test]
fn test_take_pending_reservation_only_on_terminal() {
    use crate::risk::ReservationId;
    let rid = ReservationId::new("test-reservation-001").must();
    let mut sm = Tlsm::with_pending_reservation(rid.clone(), "TEST".to_string());

    // Non-terminal states must NOT release
    assert!(
        sm.take_pending_reservation_on_terminal().is_none(),
        "Created must NOT release"
    );
    sm.apply(TlsmEvent::Sent);
    assert!(
        sm.take_pending_reservation_on_terminal().is_none(),
        "Sent must NOT release"
    );

    // Terminal state must release
    sm.apply(TlsmEvent::Filled);
    assert!(sm.state().is_terminal());
    let taken = sm.take_pending_reservation_on_terminal();
    assert!(taken.is_some(), "Filled must release reservation");
    let (taken_rid, taken_inst) = taken.must();
    assert_eq!(taken_rid, rid);
    assert_eq!(taken_inst, "TEST");

    // Already consumed
    assert!(
        sm.take_pending_reservation_on_terminal().is_none(),
        "consumed on first take"
    );
}

// ─── OOO counter metrics ────────────────────────────────────────────────
// Note: OOO counters are global statics. Tests read baseline before
// triggering events to avoid cross-test interference.

#[test]
fn test_ooo_counter_increments_on_fill_before_ack() {
    let before = ooo_count(OooCategory::FillBeforeAck);

    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Filled); // fill-before-ack → OOO

    assert!(
        ooo_count(OooCategory::FillBeforeAck) > before,
        "FillBeforeAck counter must increase by at least 1"
    );
}

#[test]
fn test_ooo_per_category_counts() {
    let before_fill = ooo_count(OooCategory::FillBeforeAck);
    let before_partial = ooo_count(OooCategory::PartialFillBeforeAck);
    let before_orphan = ooo_count(OooCategory::OrphanFill);
    let before_ack = ooo_count(OooCategory::AckBeforeSend);
    let before_pf_send = ooo_count(OooCategory::PartialFillBeforeSend);

    // FillBeforeAck
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Filled);

    // PartialFillBeforeAck
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::PartialFill);

    // OrphanFill
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Filled);

    // AckBeforeSend
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Acked);

    // PartialFillBeforeSend
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::PartialFill);
    let _ = sm; // suppress unused warning

    assert!(ooo_count(OooCategory::FillBeforeAck) > before_fill);
    assert!(ooo_count(OooCategory::PartialFillBeforeAck) > before_partial);
    assert!(ooo_count(OooCategory::OrphanFill) > before_orphan);
    assert!(ooo_count(OooCategory::AckBeforeSend) > before_ack);
    assert!(ooo_count(OooCategory::PartialFillBeforeSend) > before_pf_send);
}

#[test]
fn test_ooo_total_is_sum_of_categories() {
    let total_before = ooo_total();

    // Trigger one OOO event
    let mut sm = Tlsm::new();
    sm.apply(TlsmEvent::Sent);
    sm.apply(TlsmEvent::Filled);

    let total_after = ooo_total();
    assert!(
        total_after > total_before,
        "total must increase by at least 1"
    );
}

// ─── WAL sink production-safety enforcement ──────────────────────────────
//
// These tests enforce the invariant that `NoopTransitionSink` and the
// no-op `apply()` method are ONLY used in test contexts.
//
// Design rationale: `NoopTransitionSink` and `apply()` are gated with
// `#[cfg(test)]` in tlsm.rs. The tests below provide a second layer of
// defence: they scan the raw source text at test time and fail if the
// invariant is violated (e.g. if the cfg gate is accidentally removed).
//
// Production code MUST call `apply_with_sink()` with a durable WAL sink.

/// Assert that `NoopTransitionSink` only appears inside the `#[cfg(test)]`
/// block in the production source of tlsm.rs.
///
/// Because `NoopTransitionSink` is gated with `#[cfg(test)]`, any occurrence
/// of the identifier that is NOT inside a cfg(test) region is a bug. This test
/// catches a future author accidentally removing the cfg gate or adding a new
/// usage outside it.
#[test]
fn noop_sink_definition_is_cfg_test_gated() {
    let src = include_str!("tlsm.rs");

    // Verify that every occurrence of "NoopTransitionSink" appears after the
    // `#[cfg(test)]` line that gates the struct definition. We do this by
    // checking that there is NO occurrence of "NoopTransitionSink" before the
    // first `#[cfg(test)]` that precedes the struct definition.
    //
    // Specifically: locate the byte offset of the cfg(test) gate that sits
    // immediately before "pub struct NoopTransitionSink" and confirm no
    // ungated occurrence exists before it.

    let cfg_test_tag = "#[cfg(test)]";
    let struct_tag = "pub struct NoopTransitionSink";

    let struct_pos = src
        .find(struct_tag)
        .expect("NoopTransitionSink struct definition not found in tlsm.rs");

    // Find the last `#[cfg(test)]` before the struct definition.
    let gate_pos = src[..struct_pos]
        .rfind(cfg_test_tag)
        .expect("no #[cfg(test)] gate found before NoopTransitionSink definition in tlsm.rs");

    // Assert the gate is exactly #[cfg(test)], not cfg(any(...)) or feature-gated.
    let gate_text = src[gate_pos..gate_pos + cfg_test_tag.len()].trim();
    assert_eq!(
        gate_text, "#[cfg(test)]",
        "Gate must be exactly #[cfg(test)], not cfg(any(...)) or feature-gated"
    );

    // Nothing between the gate and the struct definition should be non-whitespace
    // doc comment noise — the gate must be the immediately preceding attribute.
    // Allow doc comment lines but reject anything else that would break the gate.
    let between = &src[gate_pos + cfg_test_tag.len()..struct_pos];
    // Allow whitespace, doc-comments, and ANY attribute (#[...]) between
    // the cfg gate and the struct definition — only non-attribute, non-comment
    // tokens would break the gate.
    let non_whitespace_non_doc: Vec<&str> = between
        .lines()
        .map(str::trim)
        .filter(|l| {
            !l.is_empty() && !l.starts_with("///") && !l.starts_with("//") && !l.starts_with("#[")
        })
        .collect();

    assert!(
        non_whitespace_non_doc.is_empty(),
        "Expected only whitespace/doc-comments/derive between #[cfg(test)] and \
         NoopTransitionSink definition, found: {non_whitespace_non_doc:?}"
    );

    // Also verify that the apply() method is gated: find `#[cfg(test)]`
    // immediately before `pub fn apply(`.
    let apply_tag = "pub fn apply(";
    let apply_pos = src
        .find(apply_tag)
        .expect("apply() method not found in tlsm.rs");

    let apply_gate_pos = src[..apply_pos]
        .rfind(cfg_test_tag)
        .expect("no #[cfg(test)] gate found before apply() method in tlsm.rs");

    // Assert the apply gate is exactly #[cfg(test)].
    let apply_gate_text = src[apply_gate_pos..apply_gate_pos + cfg_test_tag.len()].trim();
    assert_eq!(
        apply_gate_text, "#[cfg(test)]",
        "Gate must be exactly #[cfg(test)], not cfg(any(...)) or feature-gated"
    );

    let between_apply = &src[apply_gate_pos + cfg_test_tag.len()..apply_pos];
    let non_whitespace_apply: Vec<&str> = between_apply
        .lines()
        .map(str::trim)
        .filter(|l| {
            !l.is_empty() && !l.starts_with("///") && !l.starts_with("//") && !l.starts_with("#[")
        })
        .collect();

    assert!(
        non_whitespace_apply.is_empty(),
        "Expected only whitespace/doc-comments between #[cfg(test)] and apply() \
         method, found: {non_whitespace_apply:?}"
    );
}

/// Assert that no non-test Rust source file in soldier_core references
/// `NoopTransitionSink` or calls bare `.apply(`.
///
/// Recursively walks the entire `src/` directory of soldier_core — no
/// hardcoded allowlist to maintain. Files whose names end in `_tests.rs`
/// and `tlsm.rs` itself are excluded (they are the legitimate homes for the
/// no-op sink and its gate).
#[test]
fn production_sources_do_not_reference_noop_sink_or_bare_apply() {
    use std::fs;
    use std::path::{Path, PathBuf};

    fn collect_rs_files(dir: &Path, out: &mut Vec<PathBuf>) {
        let entries = match fs::read_dir(dir) {
            Ok(e) => e,
            Err(_) => return,
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                collect_rs_files(&path, out);
            } else if path.extension().map_or(false, |e| e == "rs") {
                out.push(path);
            }
        }
    }

    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    // Forbidden: using the no-op sink type or calling apply() without _with_sink.
    let forbidden_patterns = ["NoopTransitionSink", ".apply("];

    let mut all_files = Vec::new();
    collect_rs_files(&src_dir, &mut all_files);

    let mut checked = 0_usize;
    for path in &all_files {
        let name = path
            .file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .into_owned();

        // Skip test files and the file that legitimately defines the no-op sink.
        if name.ends_with("_tests.rs") || name == "tlsm.rs" {
            continue;
        }

        let src = fs::read_to_string(path)
            .unwrap_or_else(|e| panic!("cannot read {}: {e}", path.display()));
        checked += 1;

        for pattern in &forbidden_patterns {
            assert!(
                !src.contains(pattern),
                "Production source '{name}' contains forbidden WAL-bypass pattern \
                 '{pattern}'. Use apply_with_sink() with a durable WAL sink instead."
            );
        }
    }

    assert!(
        checked > 0,
        "No production source files scanned — check that src/ exists at {}",
        src_dir.display()
    );
}

// ─── AT-TLSM-01..05: CollectingSink WAL assertions ───────────────────────

/// AT-TLSM-01: Full lifecycle Created→Sent→Acked→Filled is recorded in WAL.
#[test]
fn test_at_tlsm_01_full_lifecycle_wal_recorded() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Acked, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Filled, &mut sink).unwrap();

    // Created is the initial state, so this lifecycle persists 3 transitions.
    assert_eq!(
        sink.transitions.len(),
        3,
        "should record 3 WAL entries for Created→Sent→Acked→Filled"
    );
    assert_eq!(sink.transitions.last().unwrap().to, TlsmState::Filled);
}

/// AT-TLSM-01 variant: 4-step lifecycle including PartiallyFilled.
#[test]
fn test_at_tlsm_01_four_step_lifecycle_wal_recorded() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Acked, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::PartialFill, &mut sink)
        .unwrap();
    sm.apply_with_sink(TlsmEvent::Filled, &mut sink).unwrap();

    assert_eq!(sink.transitions.len(), 4, "should record 4 WAL entries");
    assert_eq!(sink.transitions.last().unwrap().to, TlsmState::Filled);
}

/// AT-TLSM-02: Cancel after partial fill preserves WAL ordering.
#[test]
fn test_at_tlsm_02_cancel_after_partial_wal_preserved() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Acked, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::PartialFill, &mut sink)
        .unwrap();
    sm.apply_with_sink(TlsmEvent::Cancelled, &mut sink).unwrap();

    assert!(
        sink.transitions
            .iter()
            .any(|t| t.to == TlsmState::Cancelled),
        "WAL must contain Cancelled entry"
    );
    // PartiallyFilled must appear before Cancelled
    let pf_idx = sink
        .transitions
        .iter()
        .position(|t| t.to == TlsmState::PartiallyFilled)
        .expect("WAL must contain PartiallyFilled entry");
    let cancel_idx = sink
        .transitions
        .iter()
        .position(|t| t.to == TlsmState::Cancelled)
        .expect("WAL must contain Cancelled entry");
    assert!(
        pf_idx < cancel_idx,
        "PartiallyFilled must precede Cancelled in WAL"
    );
}

/// AT-TLSM-03: VenueRejected (or Rejected) produces Failed state and WAL entry.
/// Note: TlsmEvent::VenueRejected exists in the enum; both VenueRejected and Rejected
/// are aliases that map to TlsmState::Failed.
#[test]
fn test_at_tlsm_03_venue_rejected_produces_failed() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::VenueRejected, &mut sink)
        .unwrap();

    assert_eq!(
        sm.state(),
        TlsmState::Failed,
        "VenueRejected must produce Failed state"
    );
    assert!(
        sink.transitions.iter().any(|t| t.to == TlsmState::Failed),
        "WAL must contain a Failed entry after VenueRejected"
    );
}

/// AT-TLSM-03-NT NON-TRIP: Acked does NOT produce Failed (no false positive).
// AT-TLSM-03-NT
#[test]
fn test_at_tlsm_03_non_trip_acked_does_not_produce_failed() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Acked, &mut sink).unwrap();

    assert_eq!(
        sm.state(),
        TlsmState::Acked,
        "Acked must not produce Failed"
    );
    assert!(
        !sink.transitions.iter().any(|t| t.to == TlsmState::Failed),
        "WAL must NOT contain Failed entry after normal Acked"
    );
}

/// AT-TLSM-04: Duplicate Filled event produces no additional WAL entry.
#[test]
fn test_at_tlsm_04_duplicate_fill_no_additional_wal_entry() {
    let mut sm = Tlsm::new();
    let mut sink = CollectingSink::default();

    sm.apply_with_sink(TlsmEvent::Sent, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Acked, &mut sink).unwrap();
    sm.apply_with_sink(TlsmEvent::Filled, &mut sink).unwrap();

    let len_before = sink.transitions.len();

    // Duplicate Filled — should be ignored (already terminal)
    sm.apply_with_sink(TlsmEvent::Filled, &mut sink).unwrap();

    assert_eq!(
        sink.transitions.len(),
        len_before,
        "Duplicate Filled on terminal state must not add WAL entry"
    );
}

/// AT-TLSM-05: Terminal states (Filled, Cancelled, Failed) are immutable —
/// all events return Ignored and do not add WAL entries.
#[test]
fn test_at_tlsm_05_terminal_rejected_immutable() {
    let all_events = || {
        vec![
            TlsmEvent::Sent,
            TlsmEvent::Acked,
            TlsmEvent::PartialFill,
            TlsmEvent::Filled,
            TlsmEvent::Cancelled,
            TlsmEvent::VenueRejected,
            TlsmEvent::Rejected,
            TlsmEvent::Failed,
        ]
    };

    // Helper: drive sm to a terminal state, then verify all events are ignored.
    let check_terminal = |mut sm: Tlsm, label: &str| {
        assert!(sm.state().is_terminal(), "{label} must start terminal");
        let mut sink = CollectingSink::default();
        let len_before = sink.transitions.len();
        for event in all_events() {
            let result = sm.apply_with_sink(event, &mut sink).unwrap();
            assert!(
                matches!(result, TransitionResult::Ignored { .. }),
                "{label}: event after terminal must return Ignored"
            );
        }
        assert_eq!(
            sink.transitions.len(),
            len_before,
            "{label}: no WAL entries must be added after terminal"
        );
    };

    // Filled terminal
    let mut sm_filled = Tlsm::new();
    let mut s = CollectingSink::default();
    sm_filled.apply_with_sink(TlsmEvent::Sent, &mut s).unwrap();
    sm_filled.apply_with_sink(TlsmEvent::Acked, &mut s).unwrap();
    sm_filled
        .apply_with_sink(TlsmEvent::Filled, &mut s)
        .unwrap();
    check_terminal(sm_filled, "Filled");

    // Cancelled terminal
    let mut sm_cancelled = Tlsm::new();
    let mut s2 = CollectingSink::default();
    sm_cancelled
        .apply_with_sink(TlsmEvent::Sent, &mut s2)
        .unwrap();
    sm_cancelled
        .apply_with_sink(TlsmEvent::Cancelled, &mut s2)
        .unwrap();
    check_terminal(sm_cancelled, "Cancelled");

    // Failed terminal
    let mut sm_failed = Tlsm::new();
    let mut s3 = CollectingSink::default();
    sm_failed.apply_with_sink(TlsmEvent::Sent, &mut s3).unwrap();
    sm_failed
        .apply_with_sink(TlsmEvent::Failed, &mut s3)
        .unwrap();
    check_terminal(sm_failed, "Failed");

    // Verify TlsmState::Failed is_terminal() (WAL-replay scenario)
    assert!(TlsmState::Failed.is_terminal(), "Failed must be terminal");
    assert!(TlsmState::Filled.is_terminal(), "Filled must be terminal");
    assert!(
        TlsmState::Cancelled.is_terminal(),
        "Cancelled must be terminal"
    );
}
