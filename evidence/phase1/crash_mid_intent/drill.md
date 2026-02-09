# Crash Mid-Intent Drill Evidence

## Invariant

CONTRACT.md AT-935, AT-233, §2.4: A crash before dispatch must not cause duplicate dispatch on restart. WAL replay detects in-flight intents and classifies them for reconciliation.

## Automated Test Results

`cargo test -p soldier_infra --test test_crash_mid_intent` — 7 tests PASS.

### Scenarios Tested

| Scenario | WAL State | sent_ts | Restart Action | Test |
|----------|-----------|---------|---------------|------|
| Crash before dispatch | Created | 0 | Discard (stale signal) | `test_crash_mid_intent_no_duplicate_dispatch` |
| Crash after dispatch | Sent | >0 | Reconcile with exchange | `test_crash_after_dispatch_detected_on_replay` |
| Terminal states | Filled/Cancelled/Rejected/Failed | * | No action needed | `test_terminal_states_not_in_flight_on_restart` |
| Mixed states | Various | Various | Per-intent classification | `test_mixed_states_on_restart` |
| Ghost state check | Created | 0 | Safe to discard | `test_no_ghost_state_after_crash` |
| WAL append failure | (none) | N/A | No dispatch possible | `test_wal_append_failure_prevents_dispatch` |
| Fsync barrier | Created | 0 | Durable before dispatch | `test_durable_append_with_fsync_barrier` |

### Key Findings

1. **Unsent intents (Created, sent_ts=0):** Safe to discard on restart. The signal that created them is stale. No exchange order exists.
2. **Sent intents (Sent/Acked, sent_ts>0):** Must be reconciled with the exchange via `get_open_orders` / `get_order_state`. Never re-dispatch.
3. **Terminal intents (Filled/Cancelled/etc.):** No action needed. Already resolved.
4. **WAL failure:** If `durable_append()` fails, the chokepoint gate (`RecordedBeforeDispatch`) rejects the intent. No dispatch without WAL record.
