# RECONCILIATION_MATRIX.md
Version: 0.1

Purpose
- Make reconciliation failure modes finite + checkable.
- Close the "false-safe reopen" class of incidents.
- Bind every reconciliation trigger to:
  (a) a deterministic gate action (latch + risk state),
  (b) required reconciliation actions,
  (c) explicit clear criteria,
  (d) at least one AT-###.

Normative anchors in CONTRACT.md
- Open Permission Latch semantics (OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing) :contentReference[oaicite:0]{index=0}
- Reconciliation success criteria (label match, position epsilon, no missing trades, all reconcile reasons cleared) :contentReference[oaicite:1]{index=1}
- Allowed OpenPermissionReasonCode values (reconcile-only) :contentReference[oaicite:2]{index=2}
- Reconciliation triggers include startup, timer cadence, WS gap, orphan fill :contentReference[oaicite:3]{index=3}

Table legend
- Gate action MUST be stated as state changes:
  - RiskState: Healthy/Degraded/... (if applicable)
  - open_permission_blocked_latch: true/false
  - open_permission_reason_codes: add/remove reason codes
- "Clear criteria" must reference the contract's reconciliation success criteria.

---

## Matrix

| RM-ID | Trigger | Detection signal | Gate action (must be explicit) | Required reconciliation actions (deterministic order) | Clear criteria (must all hold) | Allowed ops while reconciling | /status proof fields | ATs | Contract refs |
|---|---|---|---|---|---|---|---|---|---|
| RM-001 | Startup | process start | Set `open_permission_blocked_latch=true`; add `RESTART_RECONCILE_REQUIRED` | REST snapshot reconcile: open orders + positions + recent trades; label match inflight intents | Reconciliation success criteria satisfied AND reason code cleared | OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing cancel/replace rejected | latch fields + reason codes; connectivity_degraded true | AT-010, AT-011, AT-403 | §2.2.4, §3.4, §7.0 |
| RM-002 | WS book gap | `prevChangeId != last_changeId` | Enter Degraded; latch=true; add `WS_BOOK_GAP_RECONCILE_REQUIRED` | Resubscribe; full book snapshot rebuild; reconcile positions/orders | Success criteria + clear WS_BOOK_GAP reason | OPEN blocked; reduce-only closes/hedges allowed; risk-increasing cancel/replace rejected | connectivity_degraded true; reason_codes includes WS_BOOK_GAP | AT-271, AT-408, AT-120 | §3.4, §2.2.4, §2.2.5, §7.0 |
| RM-003 | WS trades gap | trade_seq jump / non-monotonic | Enter Degraded; latch=true; add `WS_TRADES_GAP_RECONCILE_REQUIRED` | Pull REST trades lookback; dedupe; reconcile fills vs ledger; reconcile positions | Success criteria + clear WS_TRADES_GAP reason | OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing cancel/replace rejected | connectivity_degraded true; reason_codes includes WS_TRADES_GAP | AT-272, AT-202, AT-120, AT-212 | §3.4, §2.2.4, §2.2.5, §7.0 |
| RM-004 | Session termination | private WS disconnect / 10028 | Set latch=true; add `SESSION_TERMINATION_RECONCILE_REQUIRED` (also Degraded if specified by handler) | Force REST snapshot reconcile (open orders + positions + trades) | Success criteria + clear SESSION_TERMINATION reason | OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing cancel/replace rejected | connectivity_degraded true; reason_codes includes SESSION_TERMINATION | AT-409, AT-120 | §3.4, §2.2.4, §2.2.5, §7.0 |
| RM-005 | Inventory mismatch | positions != ledger fills beyond epsilon | latch=true; add `INVENTORY_MISMATCH_RECONCILE_REQUIRED` | REST positions + trades; recompute ledger derived position; reconcile delta; fix TLSM terminal states if needed | Positions match within `position_reconcile_epsilon` AND reason cleared | OPEN blocked; CLOSE/HEDGE allowed; cancel/replace risk-increasing rejected | connectivity_degraded true; reason_codes includes INVENTORY_MISMATCH | AT-403 (status), (add/point AT for mismatch if exists) | §2.2.4, §3.4, §7.0 |
| RM-006 | Orphan fill | fill/trade seen with no local Sent/Ack | latch=true; add `INVENTORY_MISMATCH_RECONCILE_REQUIRED` (or keep existing reason; must not clear until fixed) | Process orphan fill via REST/WS reconcile; TLSM transitions to Filled; no duplicate dispatch | TLSM terminal state correct AND no duplicate order created AND reason cleared | OPEN blocked until cleared; close/hedge allowed | /status shows latch true during fix; after fix latch clears | AT-210 | §3.4 |
| RM-007 | Ghost open order | exchange open order has no ledger inflight label match | latch=true; add `INVENTORY_MISMATCH_RECONCILE_REQUIRED` | CancelStaleOrder(order_id) OR adopt into ledger if allowed by rules; re-run label match | "Ledger inflight intents match exchange open orders by label" holds | OPEN blocked until cleared | /status latch+reasons; connectivity_degraded true | AUTO | §2.2.4, §3.5 |
| RM-008 | Ledger inflight missing on exchange | ledger inflight intent but exchange has no open order + no fills | latch=true; keep reason from trigger (restart/gap/etc.) | Mark intent terminal as Rejected/Expired deterministically; DO NOT resend unless WAL proves unsent (crash rules) | Label match holds; no "phantom inflight" remains | OPEN blocked until cleared | /status latch+reasons cleared after success | AUTO | §2.2.4, §3.4, §3.5, CRASH_MATRIX |
| RM-009 | Mixed-state group detected in reconciliation | group has mixed leg outcomes | latch=true (if opens must remain paused); Degraded if required | EmergencyFlattenGroup(group_id) immediately during reconciliation | Exposure repaired to neutral and group terminal state consistent | OPEN blocked until cleared; emergency close allowed per rules | /status shows Degraded/ReduceOnly; latch true | AT-210 (or dedicated mixed-state AT if exists) | §3.4 |
| RM-010 | Timer-based periodic reconcile | every 5-10s | No state change if already Healthy + latch false; if any drift found => latch true + reason | Run reconcile checks: label match + positions epsilon + trade lookback | If drift found, clear only after success criteria | No extra restrictions unless latch set | /status consistent; connectivity_degraded reflects latch/bunker | AUTO | §3.4, §7.0 |
| RM-011 | Latch clear gate | reconciliation "passes" | Must clear latch ONLY after success criteria; opens allowed only if TradingMode Active | Clear reason_codes to []; latch=false; requires_reconcile=false | Success criteria satisfied AND TradingMode Active at dispatch time | OPEN allowed only if Active | /status latch invariants; mode reasons | AT-011 | §2.2.4, §2.2.3, §7.0 |
| RM-012 | CorrectiveActions enumeration | reconcile decides fix | N/A (meta) | CorrectiveActions must be enumerated deterministically (CancelStaleOrder/ReplaceIOC/EmergencyFlattenGroup/ReduceOnlyDeltaHedge) | N/A | N/A | N/A | AUTO | §3.4 |

Notes
- If you add a new reconcile trigger, you MUST add a new RM-### row and at least one AT.
- Reason codes MUST be one of: RESTART_RECONCILE_REQUIRED, WS_BOOK_GAP_RECONCILE_REQUIRED, WS_TRADES_GAP_RECONCILE_REQUIRED, INVENTORY_MISMATCH_RECONCILE_REQUIRED, SESSION_TERMINATION_RECONCILE_REQUIRED. :contentReference[oaicite:4]{index=4}
- Latch semantics: OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing cancel/replace rejected per §2.2.5. :contentReference[oaicite:5]{index=5}
