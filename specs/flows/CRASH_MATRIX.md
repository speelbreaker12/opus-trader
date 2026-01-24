# CRASH_MATRIX (v0.1)

**Purpose:** Crash-consistency closure for intent dispatch + WAL/TruthCapsule/DecisionSnapshot + reconciliation.

This document is **derived** from CONTRACT.md. It must not contradict the contract; if it does, the contract wins.

Key contract constraints this matrix operationalizes:
- **RecordedBeforeDispatch is mandatory** for dispatch.
- **Replay Safe:** never resend unless WAL state says unsent.
- **Crash recovery:** replay WAL on startup and reconcile with exchange.
- **Trade-id idempotency:** dedupe fill events by `processed_trade_ids`.
- **TruthCapsule pre-dispatch:** block dispatch if missing; fail-closed on logging failure.

---

## Crash Matrix

**Columns**
- **Crash Point ID**: stable ID for this crash boundary case.
- **Boundary / crash moment**: the before/after edge.
- **Durable facts at crash**: what MUST already be written/known at that moment.
- **Deterministic recovery action**: exactly what to do on restart.
- **Resend rule**: whether sending is allowed on restart and under what proof.
- **Proof (AT)**: contract acceptance test(s) that prove the behavior.
- **Contract refs**: section anchors where the rule is defined.

| Crash Point ID | Boundary / crash moment | Durable facts at crash | Deterministic recovery action | Resend rule | Proof (AT) | Contract refs |
|---|---|---|---|---|---|---|
| CM-001 | Crash **after send**, **before ACK** | WAL has intent + `sent_ts` recorded (or equivalent inflight marker) | On restart: replay WAL → reconcile exchange open orders/trades → continue without duplication | **NO resend** unless WAL explicitly marks unsent | AT-233 | §2.4 / §2.4.1 |
| CM-002 | Crash **after fill**, **before local update** | Exchange has a fill; local WAL may not yet reflect fill | On restart: query exchange trades → update TLSM/WAL → trigger sequencer | No resend; apply fills idempotently | AT-234 | §2.4.1 |
| CM-003 | WAL enqueue fails at **RecordedBeforeDispatch** | WAL enqueue failed; `wal_write_errors` increments | Fail-closed: block OPEN dispatch; keep hot loop ticking; EvidenceChainState becomes not-GREEN within window | Sending forbidden for OPEN until enqueue succeeds | AT-906, AT-107 | §2.4.1; §2.2.2 |
| CM-011 | Crash **after WAL RecordedBeforeDispatch succeeds**, **before network send** | WAL has durable intent record; **no `sent_ts`** (unsent state); no exchange order/ACK yet | On restart: replay WAL → **reconcile first** (labels + open orders + trades) → if still unsent and OPEN is permitted, dispatch exactly once and record `sent_ts` | **Send allowed exactly once** iff WAL explicitly indicates **unsent** *after reconciliation*; otherwise forbidden | AT-935 | §2.4 / §2.4.1; §3.4 |
| CM-012 | Crash **after ACK**, **before local state update** | Exchange ACK received; `sent_ts` exists; `ack_ts` missing; TLSM not advanced | On restart: replay WAL → reconcile open orders/trades → update TLSM and record `ack_ts` | **No resend**; reconcile-first and update local state | AT-940 | §2.4.1; §3.4 |
| CM-004 | TruthCapsule missing at **first dispatch** | No TruthCapsule exists for `(group_id, leg_idx, intent_hash)` | Block dispatch; enter fail-closed state (Degraded + ReduceOnly via canonical triggers) | Sending forbidden until TruthCapsule exists | AT-046 | §4.3.2 |
| CM-005 | TruthCapsule write fails / queue overflow | `truth_capsule_write_errors` or writer backpressure | Block opens; enter Degraded/ReduceOnly until healthy | Sending forbidden for OPEN while logging unhealthy | AT-250, AT-252 | §4.3.2; §2.2.2 |
| CM-006 | Duplicate WS trade event delivered | `processed_trade_ids` already contains `trade_id` | Treat duplicate as NOOP | N/A (fill path) | AT-270 | §2.4.1 |
| CM-007 | Fill occurs during WS disconnect; REST sweep sees it first | trade visible via REST; WS replay later | Apply REST trade → record processed_trade_id → ignore later WS trade | N/A (fill path) | AT-269, AT-121 | §2.4.1; §3.5 |
| CM-008 | Orphan fill: exchange trade exists, local inflight lacks ACK | local TLSM inflight; exchange trades show Filled | Reconcile via REST/WS → update TLSM to Filled; run sequencer; no duplicate dispatch | No resend; reconcile first | AT-210 | §3.4 |
| CM-013 | Crash **during reconciliation** (WS reconnect / REST snapshot) | Degraded + latch set; reconciliation in progress; no final state committed | On restart: re-run reconciliation idempotently; resume only after reconciliation passes | **No dispatch** until reconciliation completes | AT-941 | §3.4; §2.2.4 |
| CM-009 | Ghost exchange open order has `s4:` label but no local ledger intent | Exchange open order exists; no matching ledger | Cancel stale order and log | N/A (cancel path) | AT-122 | §3.5 |
| CM-010 | Replay Safe (general) | WAL contains in-flight intents + intent_hashes | Rebuild in-flight from WAL; reconcile by label + trade_ids; only then progress | **Never resend** unless WAL says unsent | AT-233, AT-269 | §1.1.1; §2.4 |
| CM-014 | Crash **during retention reclaim** | Reclaim in progress; partial deletions possible; WAL/hot partitions must be untouched | On restart: resume reclaim safely; preserve WAL, hot partitions, and replay-window data | N/A (retention) | AT-942 | §7.2; §5.2 |

---

## Next hardening targets (v0.2)

- CM-011/012/013/014 implemented. Next: add rows only for new crash boundaries introduced by future changes (e.g., any non-atomic WAL fsync path or new replay inputs).
