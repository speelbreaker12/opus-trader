//! Tests for durable intent ledger (WAL) per CONTRACT.md §2.4.
//!
//! AT-935: append failure → no dispatch.
//! AT-906: WAL write errors counter.
//! AT-233: crash after send → no resend on replay.
//! AT-234: crash after fill → detect fill on replay.

use soldier_core::execution::{
    PersistedTransition, Tlsm, TlsmEvent, TlsmState, TlsmTransitionSink, TransitionResult,
};
use soldier_infra::store::{
    IntentRecord, LedgerAppendError, LedgerMetrics, LedgerTransitionSink, TlsState, WalLedger,
};

/// Local no-op sink for test setup. `Tlsm::apply()` remains available only as
/// a deprecated compatibility shim, so integration tests keep sink handling
/// explicit.
struct NoopSink;
impl TlsmTransitionSink for NoopSink {
    fn append_transition(&mut self, _t: PersistedTransition) -> Result<(), String> {
        Ok(())
    }
}

fn drive(sm: &mut Tlsm, event: TlsmEvent) -> TransitionResult {
    sm.apply_with_sink(event, &mut NoopSink)
        .expect("NoopSink never fails")
}
use std::path::{Path, PathBuf};
use std::time::{SystemTime, UNIX_EPOCH};

/// Helper: build a minimal intent record.
fn intent(hash: &str, group_id: &str, leg_idx: u32, state: TlsState) -> IntentRecord {
    IntentRecord {
        intent_hash: hash.to_string(),
        group_id: group_id.to_string(),
        leg_idx,
        instrument: "BTC-PERP".to_string(),
        side: "buy".to_string(),
        reduce_only: false,
        qty_q: 1.0,
        limit_price_q: 50000.0,
        tls_state: state,
        created_ts: 1000,
        sent_ts: 0,
        ack_ts: 0,
        last_fill_ts: 0,
        exchange_order_id: None,
        last_trade_id: None,
    }
}

// ─── Basic append + lookup ──────────────────────────────────────────────

#[test]
fn test_append_and_lookup() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();
    let record = intent("abc123", "group1", 0, TlsState::Created);

    assert!(ledger.append(record.clone(), &mut m).is_ok());
    assert_eq!(m.appends_total(), 1);

    let found = ledger.get("abc123").unwrap();
    assert_eq!(found.intent_hash, "abc123");
    assert_eq!(found.tls_state, TlsState::Created);
}

#[test]
fn test_lookup_missing_returns_none() {
    let ledger = WalLedger::new(10);
    assert!(ledger.get("nonexistent").is_none());
}

// ─── AT-935: Append failure → no dispatch ───────────────────────────────

#[test]
fn test_at935_queue_full_returns_error() {
    let mut ledger = WalLedger::new(1);
    let mut m = LedgerMetrics::new();

    // First append succeeds
    let r1 = intent("hash1", "g1", 0, TlsState::Created);
    assert!(ledger.append(r1, &mut m).is_ok());

    // Second append fails — queue full
    let r2 = intent("hash2", "g2", 0, TlsState::Created);
    assert_eq!(ledger.append(r2, &mut m), Err(LedgerAppendError::QueueFull));
}

#[test]
fn test_at935_queue_full_no_record_stored() {
    let mut ledger = WalLedger::new(1);
    let mut m = LedgerMetrics::new();

    let r1 = intent("hash1", "g1", 0, TlsState::Created);
    let _ = ledger.append(r1, &mut m);

    let r2 = intent("hash2", "g2", 0, TlsState::Created);
    let _ = ledger.append(r2, &mut m);

    // hash2 was NOT stored
    assert!(ledger.get("hash2").is_none());
    assert_eq!(ledger.queue_depth(), 1);
}

// ─── AT-906: WAL write errors counter ───────────────────────────────────

#[test]
fn test_at906_write_error_counter_increments() {
    let mut ledger = WalLedger::new(1);
    let mut m = LedgerMetrics::new();
    assert_eq!(m.wal_write_errors(), 0);

    let r1 = intent("hash1", "g1", 0, TlsState::Created);
    let _ = ledger.append(r1, &mut m);

    // This fails — counter should increment
    let r2 = intent("hash2", "g2", 0, TlsState::Created);
    let _ = ledger.append(r2, &mut m);
    assert_eq!(m.wal_write_errors(), 1);

    // Another failure
    let r3 = intent("hash3", "g3", 0, TlsState::Created);
    let _ = ledger.append(r3, &mut m);
    assert_eq!(m.wal_write_errors(), 2);
}

#[test]
fn test_at906_no_error_on_success() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    let _ = ledger.append(r, &mut m);
    assert_eq!(m.wal_write_errors(), 0);
}

// ─── AT-233: No resend after crash ──────────────────────────────────────

#[test]
fn test_at233_sent_intent_not_resent_on_replay() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    // Record intent as Created, then mark as Sent
    let mut r = intent("hash1", "g1", 0, TlsState::Created);
    r.sent_ts = 2000;
    r.tls_state = TlsState::Sent;
    let _ = ledger.append(r, &mut m);

    // On replay, this intent should be detected as "was_sent"
    assert!(ledger.was_sent("hash1"));

    // Replay should show it as in-flight (Sent is non-terminal)
    let outcome = ledger.replay();
    assert_eq!(outcome.in_flight_count, 1);
    assert!(outcome.in_flight_hashes.contains(&"hash1".to_string()));
}

#[test]
fn test_at233_created_intent_not_marked_sent() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    let _ = ledger.append(r, &mut m);

    // Created + sent_ts=0 → not sent
    assert!(!ledger.was_sent("hash1"));
}

#[test]
fn test_at233_unknown_hash_not_sent() {
    let ledger = WalLedger::new(10);
    assert!(!ledger.was_sent("unknown"));
}

// ─── AT-234: Detect fill on replay ──────────────────────────────────────

#[test]
fn test_at234_filled_intent_detected_on_replay() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Filled);
    let _ = ledger.append(r, &mut m);

    // Filled is terminal → not in-flight
    let outcome = ledger.replay();
    assert_eq!(outcome.in_flight_count, 0);
    assert_eq!(outcome.records_replayed, 1);
}

#[test]
fn test_at234_partial_fill_is_in_flight() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::PartialFill);
    let _ = ledger.append(r, &mut m);

    let outcome = ledger.replay();
    assert_eq!(outcome.in_flight_count, 1);
}

// ─── State updates ──────────────────────────────────────────────────────

#[test]
fn test_update_state_transitions() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    let _ = ledger.append(r, &mut m);

    // Transition to Sent
    assert!(ledger.update_state("hash1", TlsState::Sent, &mut m).is_ok());
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Sent);

    // Transition to Acked
    assert!(
        ledger
            .update_state("hash1", TlsState::Acked, &mut m)
            .is_ok()
    );
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Acked);
}

#[test]
fn test_update_state_unknown_hash_fails() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    match ledger.update_state("unknown", TlsState::Sent, &mut m) {
        Err(LedgerAppendError::WriteFailed { reason }) => {
            assert!(reason.contains("not found"));
        }
        other => panic!("expected WriteFailed, got {other:?}"),
    }
    assert_eq!(m.wal_write_errors(), 1);
}

#[test]
fn test_update_state_succeeds_when_queue_is_at_capacity() {
    let mut ledger = WalLedger::new(1);
    let mut m = LedgerMetrics::new();

    let _ = ledger.append(intent("hash1", "g1", 0, TlsState::Created), &mut m);
    assert_eq!(ledger.queue_depth(), ledger.queue_capacity());

    let result = ledger.update_state("hash1", TlsState::Sent, &mut m);
    assert!(result.is_ok(), "state update must not fail on full queue");
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Sent);

    // queue_depth stays 1 (unique intents)
    assert_eq!(ledger.queue_depth(), 1);
}

#[test]
fn test_update_state_unknown_hash_still_fails_at_capacity() {
    let mut ledger = WalLedger::new(1);
    let mut m = LedgerMetrics::new();

    let _ = ledger.append(intent("hash1", "g1", 0, TlsState::Created), &mut m);
    assert_eq!(ledger.queue_depth(), ledger.queue_capacity());

    match ledger.update_state("unknown", TlsState::Sent, &mut m) {
        Err(LedgerAppendError::WriteFailed { reason }) => {
            assert!(reason.contains("not found"));
        }
        other => panic!("expected WriteFailed, got {other:?}"),
    }
}

// ─── Replay ─────────────────────────────────────────────────────────────

#[test]
fn test_replay_empty_ledger() {
    let ledger = WalLedger::new(10);
    let outcome = ledger.replay();
    assert_eq!(outcome.records_replayed, 0);
    assert_eq!(outcome.in_flight_count, 0);
    assert!(outcome.in_flight_hashes.is_empty());
}

#[test]
#[allow(deprecated)] // TlsState::Rejected retained for WAL-replay of historical records
fn test_replay_mixed_states() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    // Created (in-flight)
    let _ = ledger.append(intent("h1", "g1", 0, TlsState::Created), &mut m);
    // Sent (in-flight)
    let _ = ledger.append(intent("h2", "g2", 0, TlsState::Sent), &mut m);
    // Filled (terminal)
    let _ = ledger.append(intent("h3", "g3", 0, TlsState::Filled), &mut m);
    // Cancelled (terminal)
    let _ = ledger.append(intent("h4", "g4", 0, TlsState::Cancelled), &mut m);
    // Acked (in-flight)
    let _ = ledger.append(intent("h5", "g5", 0, TlsState::Acked), &mut m);
    // AT-TLSM-06 partial coverage: Rejected (deprecated WAL-only) is terminal, must not appear in in-flight
    let _ = ledger.append(intent("h6", "g6", 0, TlsState::Rejected), &mut m);

    let outcome = ledger.replay();
    assert_eq!(outcome.records_replayed, 6);
    assert_eq!(outcome.in_flight_count, 3); // Created, Sent, Acked
    assert!(outcome.in_flight_hashes.contains(&"h1".to_string()));
    assert!(outcome.in_flight_hashes.contains(&"h2".to_string()));
    assert!(outcome.in_flight_hashes.contains(&"h5".to_string()));
    // Rejected is terminal — must NOT appear in in-flight
    assert!(!outcome.in_flight_hashes.contains(&"h6".to_string()));
}

// ─── Terminal states ────────────────────────────────────────────────────

#[test]
#[allow(deprecated)] // TlsState::Rejected retained for WAL-replay of historical records
fn test_terminal_states() {
    assert!(TlsState::Filled.is_terminal());
    assert!(TlsState::Cancelled.is_terminal());
    assert!(TlsState::Rejected.is_terminal());
    assert!(TlsState::Failed.is_terminal());
}

#[test]
fn test_non_terminal_states() {
    assert!(!TlsState::Created.is_terminal());
    assert!(!TlsState::Sent.is_terminal());
    assert!(!TlsState::Acked.is_terminal());
    assert!(!TlsState::PartialFill.is_terminal());
}

// ─── Queue telemetry ────────────────────────────────────────────────────

#[test]
fn test_queue_depth_and_capacity() {
    let mut ledger = WalLedger::new(5);
    let mut m = LedgerMetrics::new();
    assert_eq!(ledger.queue_depth(), 0);
    assert_eq!(ledger.queue_capacity(), 5);

    let _ = ledger.append(intent("h1", "g1", 0, TlsState::Created), &mut m);
    assert_eq!(ledger.queue_depth(), 1);

    let _ = ledger.append(intent("h2", "g2", 0, TlsState::Created), &mut m);
    assert_eq!(ledger.queue_depth(), 2);
}

// ─── Persisted record schema ────────────────────────────────────────────

#[test]
fn test_record_has_all_required_fields() {
    let r = IntentRecord {
        intent_hash: "abc123".to_string(),
        group_id: "group1".to_string(),
        leg_idx: 0,
        instrument: "BTC-PERP".to_string(),
        side: "buy".to_string(),
        reduce_only: true,
        qty_q: 1.0,
        limit_price_q: 50000.0,
        tls_state: TlsState::Created,
        created_ts: 1000,
        sent_ts: 2000,
        ack_ts: 3000,
        last_fill_ts: 4000,
        exchange_order_id: Some("EX123".to_string()),
        last_trade_id: Some("TR456".to_string()),
    };

    // Verify all CONTRACT.md §2.4 minimum persisted fields are present
    assert_eq!(r.intent_hash, "abc123");
    assert_eq!(r.group_id, "group1");
    assert_eq!(r.leg_idx, 0);
    assert_eq!(r.instrument, "BTC-PERP");
    assert_eq!(r.side, "buy");
    assert!(r.reduce_only);
    assert!((r.qty_q - 1.0).abs() < 1e-9);
    assert!((r.limit_price_q - 50000.0).abs() < 1e-9);
    assert_eq!(r.tls_state, TlsState::Created);
    assert_eq!(r.created_ts, 1000);
    assert_eq!(r.sent_ts, 2000);
    assert_eq!(r.ack_ts, 3000);
    assert_eq!(r.last_fill_ts, 4000);
    assert_eq!(r.exchange_order_id, Some("EX123".to_string()));
    assert_eq!(r.last_trade_id, Some("TR456".to_string()));
}

#[test]
fn test_legacy_record_missing_reduce_only_defaults_fail_closed() {
    let legacy = serde_json::json!({
        "intent_hash": "legacy-1",
        "group_id": "group1",
        "leg_idx": 0,
        "instrument": "BTC-PERP",
        "side": "buy",
        "qty_q": 1.0,
        "limit_price_q": 50000.0,
        "tls_state": "Created",
        "created_ts": 1000,
        "sent_ts": 0,
        "ack_ts": 0,
        "last_fill_ts": 0,
        "exchange_order_id": null,
        "last_trade_id": null
    });

    let parsed: IntentRecord =
        serde_json::from_value(legacy).expect("legacy record without reduce_only should parse");
    assert!(
        !parsed.reduce_only,
        "legacy record missing reduce_only must default to false (OPEN classification) per CONTRACT §2.4"
    );
}

// ─── TLSM transition validation ──────────────────────────────────────────

#[test]
fn test_illegal_transition_filled_to_sent() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    // Transition Created → Filled (valid)
    ledger
        .update_state("hash1", TlsState::Filled, &mut m)
        .unwrap();

    // Transition Filled → Sent (illegal: Filled is terminal)
    match ledger.update_state("hash1", TlsState::Sent, &mut m) {
        Err(LedgerAppendError::IllegalTransition { from, to }) => {
            assert_eq!(from, TlsState::Filled);
            assert_eq!(to, TlsState::Sent);
        }
        other => panic!("expected IllegalTransition, got {other:?}"),
    }
}

#[test]
fn test_illegal_transition_cancelled_to_acked() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    // Transition Created → Cancelled (valid)
    ledger
        .update_state("hash1", TlsState::Cancelled, &mut m)
        .unwrap();

    // Transition Cancelled → Acked (illegal: Cancelled is terminal)
    match ledger.update_state("hash1", TlsState::Acked, &mut m) {
        Err(LedgerAppendError::IllegalTransition { from, to }) => {
            assert_eq!(from, TlsState::Cancelled);
            assert_eq!(to, TlsState::Acked);
        }
        other => panic!("expected IllegalTransition, got {other:?}"),
    }
}

#[test]
fn test_valid_transition_created_to_filled() {
    // Out-of-order but valid per AT-210: exchange can skip intermediate states
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    assert!(
        ledger
            .update_state("hash1", TlsState::Filled, &mut m)
            .is_ok()
    );
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Filled);
}

#[test]
fn test_valid_transition_partial_fill_to_partial_fill() {
    // Idempotent: additional partial fill events
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    ledger
        .update_state("hash1", TlsState::PartialFill, &mut m)
        .unwrap();
    assert!(
        ledger
            .update_state("hash1", TlsState::PartialFill, &mut m)
            .is_ok()
    );
    assert_eq!(
        ledger.get("hash1").unwrap().tls_state,
        TlsState::PartialFill
    );
}

#[test]
fn test_valid_transition_created_to_sent() {
    // Normal flow
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    assert!(ledger.update_state("hash1", TlsState::Sent, &mut m).is_ok());
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Sent);
}

#[test]
fn test_illegal_transition_increments_write_error_counter() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r = intent("hash1", "g1", 0, TlsState::Created);
    ledger.append(r, &mut m).unwrap();

    ledger
        .update_state("hash1", TlsState::Filled, &mut m)
        .unwrap();
    assert_eq!(m.wal_write_errors(), 0);

    // Illegal transition: should increment wal_write_errors
    let _ = ledger.update_state("hash1", TlsState::Sent, &mut m);
    assert_eq!(m.wal_write_errors(), 1);
}

// ─── HOT-LOOP: queue full returns immediately ───────────────────────────

#[test]
fn test_queue_full_returns_immediately() {
    // This test verifies the append returns an error (not blocking)
    // when the queue is full — per §2.4.1.
    let mut ledger = WalLedger::new(0);
    let mut m = LedgerMetrics::new();
    let r = intent("h1", "g1", 0, TlsState::Created);

    // Capacity 0 → immediate error
    let result = ledger.append(r, &mut m);
    assert_eq!(result, Err(LedgerAppendError::QueueFull));
    assert_eq!(m.wal_write_errors(), 1);
}

// ─── TLSM ↔ WAL whitelist sync ──────────────────────────────────────────

/// Map TlsmState (soldier_core) to TlsState (soldier_infra).
///
/// The two enums have slightly different naming (PartiallyFilled vs PartialFill).
fn map_tlsm_to_tls(s: TlsmState) -> TlsState {
    match s {
        TlsmState::Created => TlsState::Created,
        TlsmState::Sent => TlsState::Sent,
        TlsmState::Acked => TlsState::Acked,
        TlsmState::PartiallyFilled => TlsState::PartialFill,
        TlsmState::Filled => TlsState::Filled,
        TlsmState::Cancelled => TlsState::Cancelled,
        // TlsmState has no Rejected variant — rejected events map to
        // TlsmState::Failed.  WAL's TlsState::Rejected is a WAL-only
        // state tested directly (see test_rejected_is_terminal and
        // test_rejected_valid_successors below).
        TlsmState::Failed => TlsState::Failed,
    }
}

/// Drive a TLSM from Created to the target state via the shortest event path.
/// Returns None if the target state is unreachable (shouldn't happen for valid states).
fn drive_tlsm_to(target: TlsmState) -> Option<Tlsm> {
    let mut tlsm = Tlsm::new();
    if tlsm.state() == target {
        return Some(tlsm);
    }
    // Event sequences to reach each non-Created state:
    let paths: &[(TlsmState, &[TlsmEvent])] = &[
        (TlsmState::Sent, &[TlsmEvent::Sent]),
        (TlsmState::Acked, &[TlsmEvent::Sent, TlsmEvent::Acked]),
        (
            TlsmState::PartiallyFilled,
            &[TlsmEvent::Sent, TlsmEvent::Acked, TlsmEvent::PartialFill],
        ),
        (
            TlsmState::Filled,
            &[TlsmEvent::Sent, TlsmEvent::Acked, TlsmEvent::Filled],
        ),
        (TlsmState::Cancelled, &[TlsmEvent::Cancelled]),
        (TlsmState::Failed, &[TlsmEvent::Failed]),
    ];
    for (state, events) in paths {
        if *state == target {
            for event in *events {
                drive(&mut tlsm, event.clone());
            }
            assert_eq!(tlsm.state(), target);
            return Some(tlsm);
        }
    }
    None
}

/// Verify that every transition the canonical TLSM produces is allowed by the
/// WAL ledger's `is_valid_successor()` whitelist.
///
/// This test drives the TLSM to each non-terminal state, fires all events,
/// and checks that every (from, to) pair accepted by Tlsm::apply() is also
/// accepted by TlsState::is_valid_successor(). Fails if the whitelist
/// drifts out of sync with the runtime TLSM.
#[test]
fn test_tlsm_wal_whitelist_sync() {
    let non_terminal_states = [
        TlsmState::Created,
        TlsmState::Sent,
        TlsmState::Acked,
        TlsmState::PartiallyFilled,
    ];
    let all_events = [
        TlsmEvent::Sent,
        TlsmEvent::Acked,
        TlsmEvent::PartialFill,
        TlsmEvent::Filled,
        TlsmEvent::Cancelled,
        TlsmEvent::Rejected,
        TlsmEvent::Failed,
    ];

    let mut missing = Vec::new();

    for &from_state in &non_terminal_states {
        for event in &all_events {
            let mut tlsm = drive_tlsm_to(from_state)
                .unwrap_or_else(|| panic!("cannot reach {:?}", from_state));
            let result = drive(&mut tlsm, event.clone());

            // Extract the to-state if the TLSM accepted the transition.
            let to_state = match result {
                TransitionResult::Transitioned { to, .. } => Some(to),
                TransitionResult::OutOfOrder { to, .. } => Some(to),
                TransitionResult::Ignored { .. } => None,
            };

            if let Some(to) = to_state {
                let tls_from = map_tlsm_to_tls(from_state);
                let tls_to = map_tlsm_to_tls(to);
                if !tls_from.is_valid_successor(tls_to) {
                    missing.push(format!(
                        "TLSM allows {:?}->{:?} but WAL whitelist rejects {:?}->{:?}",
                        from_state, to, tls_from, tls_to,
                    ));
                }
            }
        }
    }

    assert!(
        missing.is_empty(),
        "WAL whitelist out of sync with TLSM:\n{}",
        missing.join("\n"),
    );
}

// ─── WAL-only Rejected state (no TlsmState::Rejected counterpart) ───────

/// TlsState::Rejected is a WAL-only terminal state.  The TLSM maps rejected
/// events to TlsmState::Failed, but the WAL preserves the distinction.
/// These tests verify Rejected transitions directly at the WAL level.
#[test]
#[allow(deprecated)] // TlsState::Rejected retained for WAL-replay of historical records
fn test_rejected_is_terminal() {
    assert!(
        !TlsState::Rejected.is_valid_successor(TlsState::Sent),
        "Rejected is terminal — no transitions out"
    );
    assert!(!TlsState::Rejected.is_valid_successor(TlsState::Created));
    assert!(!TlsState::Rejected.is_valid_successor(TlsState::Acked));
    assert!(!TlsState::Rejected.is_valid_successor(TlsState::Filled));
}

#[test]
#[allow(deprecated)] // TlsState::Rejected retained for WAL-replay of historical records
fn test_rejected_valid_successors() {
    // Created and Sent can transition to Rejected (exchange rejection before ack).
    assert!(TlsState::Created.is_valid_successor(TlsState::Rejected));
    assert!(TlsState::Sent.is_valid_successor(TlsState::Rejected));
    // Acked cannot transition to Rejected (already acknowledged).
    assert!(!TlsState::Acked.is_valid_successor(TlsState::Rejected));
    assert!(!TlsState::PartialFill.is_valid_successor(TlsState::Rejected));
}

// ═══════════════════════════════════════════════════════════════════════════
// Fix 3: CSP-002 Duplicate intent_hash rejection
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fn test_duplicate_intent_hash_rejected() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let r1 = intent("hash1", "g1", 0, TlsState::Created);
    assert!(ledger.append(r1, &mut m).is_ok());

    // Second append with same hash must be rejected
    let r2 = intent("hash1", "g2", 1, TlsState::Created);
    assert_eq!(
        ledger.append(r2, &mut m),
        Err(LedgerAppendError::DuplicateIntentHash)
    );

    // Original record preserved
    let found = ledger.get("hash1").unwrap();
    assert_eq!(found.group_id, "g1");
    assert_eq!(found.leg_idx, 0);
}

#[test]
fn test_duplicate_intent_hash_increments_write_error() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    let _ = ledger.append(intent("hash1", "g1", 0, TlsState::Created), &mut m);
    assert_eq!(m.wal_write_errors(), 0);

    let _ = ledger.append(intent("hash1", "g2", 1, TlsState::Created), &mut m);
    assert_eq!(m.wal_write_errors(), 1);
}

#[test]
fn test_different_intent_hashes_accepted() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    assert!(
        ledger
            .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
            .is_ok()
    );
    assert!(
        ledger
            .append(intent("hash2", "g2", 0, TlsState::Created), &mut m)
            .is_ok()
    );
    assert_eq!(ledger.queue_depth(), 2);
    assert!(ledger.get("hash1").is_some());
    assert!(ledger.get("hash2").is_some());
}

// ═══════════════════════════════════════════════════════════════════════════
// Fix 2: WAL append-only update_state
// ═══════════════════════════════════════════════════════════════════════════

#[test]
fn test_append_only_preserves_old_entries() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    ledger
        .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
        .unwrap();
    assert_eq!(ledger.queue_depth(), 1);

    ledger
        .update_state("hash1", TlsState::Sent, &mut m)
        .unwrap();
    // queue_depth stays 1 (unique intents)
    assert_eq!(ledger.queue_depth(), 1);
    // get() returns latest state
    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Sent);
}

#[test]
fn test_replay_after_state_update_uses_latest_state() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    ledger
        .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
        .unwrap();
    ledger
        .update_state("hash1", TlsState::Filled, &mut m)
        .unwrap();

    let outcome = ledger.replay();
    // Filled is terminal — not in-flight
    assert_eq!(outcome.in_flight_count, 0);
    // records_replayed = unique intents
    assert_eq!(outcome.records_replayed, 1);
    assert!(outcome.in_flight_hashes.is_empty());
}

#[test]
fn test_state_update_succeeds_past_capacity() {
    let mut ledger = WalLedger::new(2);
    let mut m = LedgerMetrics::new();

    ledger
        .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
        .unwrap();
    ledger
        .append(intent("hash2", "g2", 0, TlsState::Created), &mut m)
        .unwrap();
    assert_eq!(ledger.queue_depth(), 2);

    // New append rejected — queue full
    assert_eq!(
        ledger.append(intent("hash3", "g3", 0, TlsState::Created), &mut m),
        Err(LedgerAppendError::QueueFull)
    );

    // But state transitions always succeed
    assert!(ledger.update_state("hash1", TlsState::Sent, &mut m).is_ok());
    assert!(
        ledger
            .update_state("hash2", TlsState::Filled, &mut m)
            .is_ok()
    );
    assert_eq!(ledger.queue_depth(), 2); // still 2 unique intents
}

#[test]
fn test_duplicate_append_rejected_after_state_transition() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();

    ledger
        .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
        .unwrap();
    ledger
        .update_state("hash1", TlsState::Filled, &mut m)
        .unwrap();

    // Re-appending same hash after state transition must still be rejected
    assert_eq!(
        ledger.append(intent("hash1", "g2", 1, TlsState::Created), &mut m),
        Err(LedgerAppendError::DuplicateIntentHash)
    );
}

/// Regression: duplicate on a full queue must return DuplicateIntentHash,
/// not QueueFull. The intent is already recorded and doesn't consume capacity.
#[test]
fn test_duplicate_on_full_queue_returns_duplicate_not_queue_full() {
    let mut ledger = WalLedger::new(2);
    let mut m = LedgerMetrics::new();

    ledger
        .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
        .unwrap();
    ledger
        .append(intent("hash2", "g2", 0, TlsState::Created), &mut m)
        .unwrap();
    assert_eq!(ledger.queue_depth(), 2);

    // Queue is full — but hash1 is already there, so the error must be
    // DuplicateIntentHash, not QueueFull.
    assert_eq!(
        ledger.append(intent("hash1", "g3", 1, TlsState::Created), &mut m),
        Err(LedgerAppendError::DuplicateIntentHash)
    );
}

// ─── Durable storage helpers ────────────────────────────────────────────

fn temp_wal_path(tag: &str) -> PathBuf {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .expect("clock before unix epoch")
        .as_nanos();
    std::env::temp_dir().join(format!(
        "soldier_ledger_{tag}_{}_{}.jsonl",
        std::process::id(),
        nanos
    ))
}

fn remove_if_exists(path: &Path) {
    let _ = std::fs::remove_file(path);
}

// ─── mark_sent ──────────────────────────────────────────────────────────

#[test]
fn test_mark_sent_updates_sent_ts_and_state() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();
    let mut record = intent("hash1", "g1", 0, TlsState::Created);
    record.sent_ts = 0;

    let _ = ledger.append(record, &mut m);
    ledger.mark_sent("hash1", 2222, &mut m).unwrap();

    let stored = ledger.get("hash1").unwrap();
    assert_eq!(stored.sent_ts, 2222);
    assert_eq!(stored.tls_state, TlsState::Sent);
    assert!(ledger.was_sent("hash1"));
}

// ─── LedgerTransitionSink ───────────────────────────────────────────────

#[test]
fn test_tlsm_transition_sink_updates_ledger_state() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();
    let _ = ledger.append(intent("hash1", "g1", 0, TlsState::Created), &mut m);

    {
        let mut sink = LedgerTransitionSink::new(&mut ledger, &mut m, "hash1");
        let mut tlsm = Tlsm::new();
        let _ = tlsm
            .apply_with_sink(TlsmEvent::Sent, &mut sink)
            .expect("ledger sink append should succeed");
    }

    assert_eq!(ledger.get("hash1").unwrap().tls_state, TlsState::Sent);
}

#[test]
fn test_tlsm_transition_sink_failure_keeps_tlsm_state_unchanged() {
    let mut ledger = WalLedger::new(10);
    let mut m = LedgerMetrics::new();
    let _ = ledger.append(intent("hash1", "g1", 0, TlsState::Created), &mut m);

    // Sink points at a missing intent hash so update_state fails.
    let mut sink = LedgerTransitionSink::new(&mut ledger, &mut m, "missing-hash");
    let mut tlsm = Tlsm::new();
    let result = tlsm.apply_with_sink(TlsmEvent::Sent, &mut sink);

    assert!(result.is_err(), "sink failure should propagate");
    assert_eq!(tlsm.state(), soldier_core::execution::TlsmState::Created);
}

// ─── Durable JSONL storage round-trip ───────────────────────────────────

#[test]
fn test_replay_round_trip_from_durable_storage() {
    let wal_path = temp_wal_path("replay_rt");

    // Phase 1: write intent + transition
    {
        let mut ledger = WalLedger::with_storage_path(10, &wal_path).expect("create wal");
        let mut m = LedgerMetrics::new();
        ledger
            .append(intent("hash1", "g1", 0, TlsState::Created), &mut m)
            .unwrap();
        ledger
            .update_state("hash1", TlsState::Sent, &mut m)
            .unwrap();
        assert_eq!(ledger.queue_depth(), 1);
    }

    // Phase 2: reload and verify
    {
        let ledger = WalLedger::with_storage_path(10, &wal_path).expect("reload wal");
        assert_eq!(ledger.queue_depth(), 1);
        let record = ledger.get("hash1").unwrap();
        assert_eq!(record.tls_state, TlsState::Sent);

        let replay = ledger.replay();
        assert_eq!(replay.records_replayed, 1);
        assert_eq!(replay.in_flight_count, 1);
    }

    remove_if_exists(&wal_path);
}

// ═══════════════════════════════════════════════════════════════════════════
// Trailing corruption tolerance (TRIP / NON-TRIP pairs per §0.Z.2.2 item A)
// ═══════════════════════════════════════════════════════════════════════════

/// Helper: serialize an IntentRecorded WAL event as a JSONL line (no newline).
fn wal_intent_line(hash: &str, group_id: &str) -> String {
    let record = intent(hash, group_id, 0, TlsState::Created);
    // Build the same JSON that write_event_to_file would produce.
    // WalEvent is private, so we construct the JSON manually matching
    // the serde(tag = "kind", rename_all = "snake_case") format.
    let record_json = serde_json::to_value(&record).unwrap();
    let event = serde_json::json!({
        "kind": "intent_recorded",
        "record": record_json
    });
    serde_json::to_string(&event).unwrap()
}

/// NON-TRIP: Single trailing corrupt line is tolerated.
/// Valid events before the corruption are returned.
#[test]
fn test_trailing_corruption_single_line_tolerated() {
    let path = temp_wal_path("trail_single");

    let content = format!(
        "{}\n{}\n{}\n",
        wal_intent_line("h1", "g1"),
        wal_intent_line("h2", "g2"),
        "THIS IS CORRUPT GARBAGE",
    );
    std::fs::write(&path, &content).unwrap();

    let ledger =
        WalLedger::with_storage_path(10, &path).expect("should tolerate trailing corruption");
    assert_eq!(ledger.queue_depth(), 2);
    assert!(ledger.get("h1").is_some());
    assert!(ledger.get("h2").is_some());

    remove_if_exists(&path);
}

/// NON-TRIP: Multiple trailing corrupt lines (double-crash) are tolerated.
/// Valid events before the corruption are returned.
#[test]
fn test_trailing_corruption_multiple_lines_tolerated() {
    let path = temp_wal_path("trail_multi");

    let content = format!(
        "{}\n{}\n{}\n{}\n{}\n",
        wal_intent_line("h1", "g1"),
        wal_intent_line("h2", "g2"),
        "CORRUPT LINE FROM CRASH 1",
        "CORRUPT LINE FROM CRASH 2",
        "{\"kind\":\"bogus\"}", // also corrupt (unknown variant)
    );
    std::fs::write(&path, &content).unwrap();

    let ledger = WalLedger::with_storage_path(10, &path)
        .expect("should tolerate multiple trailing corrupt lines");
    assert_eq!(ledger.queue_depth(), 2);
    assert!(ledger.get("h1").is_some());
    assert!(ledger.get("h2").is_some());

    remove_if_exists(&path);
}

/// TRIP: Mid-file corrupt line followed by a valid line → hard error.
/// This proves mid-file corruption is detected and rejected.
#[test]
fn test_midfile_corruption_returns_error() {
    let path = temp_wal_path("midfile_corrupt");

    let content = format!(
        "{}\nCORRUPT MID-FILE LINE\n{}\n",
        wal_intent_line("h1", "g1"),
        wal_intent_line("h2", "g2"),
    );
    std::fs::write(&path, &content).unwrap();

    let result = WalLedger::with_storage_path(10, &path);
    assert!(
        result.is_err(),
        "mid-file corruption must cause a hard error"
    );
    let err = result.unwrap_err();
    assert_eq!(err.kind(), std::io::ErrorKind::InvalidData);
    let msg = err.to_string();
    assert!(
        msg.contains("invalid wal event at line 2"),
        "error should identify the corrupt line number, got: {msg}"
    );
    assert!(
        msg.contains("followed by valid line 3"),
        "error should mention the valid line that proves mid-file corruption, got: {msg}"
    );

    remove_if_exists(&path);
}

/// Edge case: All lines corrupt → empty ledger (no valid events, all treated as trailing).
#[test]
fn test_all_lines_corrupt_returns_empty() {
    let path = temp_wal_path("all_corrupt");

    let content = "GARBAGE LINE 1\nGARBAGE LINE 2\n{\"bad\":true}\n";
    std::fs::write(&path, content).unwrap();

    // Sanity: file is non-empty (rules out "reader ignored the file").
    let file_len = std::fs::metadata(&path).unwrap().len();
    assert!(
        file_len > 0,
        "test file must be non-empty to prove reader processed it"
    );

    let ledger = WalLedger::with_storage_path(10, &path)
        .expect("all-corrupt file should be tolerated (all trailing)");
    assert_eq!(ledger.queue_depth(), 0);

    remove_if_exists(&path);
}

/// Round-trip: verify that wal_intent_line() output is parseable by the production reader.
#[test]
fn test_wal_intent_line_round_trip() {
    let path = temp_wal_path("roundtrip");
    let content = format!("{}\n", wal_intent_line("rt1", "g1"));
    std::fs::write(&path, &content).unwrap();

    let ledger = WalLedger::with_storage_path(10, &path)
        .expect("wal_intent_line output must be parseable by production reader");
    assert_eq!(
        ledger.queue_depth(),
        1,
        "round-trip: WAL reader must parse wal_intent_line output as a valid event"
    );
    assert!(ledger.get("rt1").is_some());

    remove_if_exists(&path);
}
