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
- Open Permission Latch semantics (OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing) — §2.2.4
- Reconciliation success criteria (label match, position epsilon, no missing trades, all reconcile reasons cleared) — §3.4
- Allowed OpenPermissionReasonCode values (reconcile-only) — §2.2.4
- Reconciliation triggers include startup, timer cadence, WS gap, orphan fill, exchange-initiated changes, margin drift — §2.2.4, §3.4, §3.6, §4.6

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

| RM-013 | Exchange-initiated position change | REST position delta not attributable to any intent (liquidation, auto-exercise, unknown) | Set `open_permission_blocked_latch=true`; add `EXCHANGE_INITIATED_RECONCILE_REQUIRED`; enter Degraded | Classify delta source (liquidation/auto-exercise/unknown); adjust ledger to exchange truth; record in WAL with source tag; emit operator alert for EXCHANGE_UNKNOWN | Ledger matches exchange positions within epsilon AND reason code cleared AND source classified | OPEN blocked; CLOSE/HEDGE/CANCEL allowed; no automatic re-entry into liquidated positions | latch fields + reason codes; connectivity_degraded true; exchange_initiated_event logged | AT-1285, AT-1286, AT-1287, AT-1288, AT-1291 | §3.6, §3.6.1, §3.6.2, §3.6.4, §2.2.4 |
| RM-014 | Maintenance / circuit breaker cancel | Multiple orders cancelled simultaneously by exchange (>= maintenance_cancel_threshold) | Set `open_permission_blocked_latch=true`; add `EXCHANGE_INITIATED_RECONCILE_REQUIRED` | Mark all affected TLSM as `Canceled` with source tag `EXCHANGE_CANCELLED`; verify venue accepting orders before re-dispatch; REST snapshot reconcile | Venue confirmed accepting orders AND all TLSM terminal states correct AND reason code cleared | OPEN blocked; no automatic re-dispatch of cancelled orders; CLOSE/HEDGE/CANCEL allowed | latch fields + reason codes; VenueMaintenanceCancelDetected logged | AT-1289, AT-1290 | §3.6.3, §3.5, §2.2.4 |
| RM-015 | Margin drift critical | `margin_drift_pct > margin_drift_critical_pct` | Set `open_permission_blocked_latch=true`; add `MARGIN_DRIFT_RECONCILE_REQUIRED`; enter Degraded | Recalibrate agent margin to exchange truth; reset `cumulative_funding_usd` to zero; identify drift source (funding/fees/exchange-initiated); refresh funding + fee caches | `margin_drift_pct < margin_drift_warn_pct` AND reason code cleared | OPEN blocked; CLOSE/HEDGE/CANCEL allowed | latch fields + reason codes; MarginDriftCritical logged; margin values in /status | AT-1295, AT-1296, AT-1297 | §4.6.2, §2.2.4, §7.0 |
| RM-016 | Funding rate cache hard-stale | `funding_cache_age > funding_cache_hard_s` | Set `open_permission_blocked_latch=true`; add `FUNDING_STALE_RECONCILE_REQUIRED`; enter Degraded | Force `TradingMode::ReduceOnly` via PolicyGuard; continue polling funding rate | Funding rate cache refreshed (age < `funding_cache_soft_s`) AND reason code cleared | OPEN blocked; CLOSE/HEDGE/CANCEL allowed | latch fields + reason codes; RiskState Degraded; funding_cache_hard_stale_total incremented | AT-1293, AT-1309 | §4.6.1, §2.2.4, §7.0 |

Notes
- If you add a new reconcile trigger, you MUST add a new RM-### row and at least one AT.
- Reason codes MUST be one of: `RESTART_RECONCILE_REQUIRED`, `WS_BOOK_GAP_RECONCILE_REQUIRED`, `WS_TRADES_GAP_RECONCILE_REQUIRED`, `WS_DATA_STALE_RECONCILE_REQUIRED`, `INVENTORY_MISMATCH_RECONCILE_REQUIRED`, `SESSION_TERMINATION_RECONCILE_REQUIRED`, `EXCHANGE_INITIATED_RECONCILE_REQUIRED`, `MARGIN_DRIFT_RECONCILE_REQUIRED`, `FUNDING_STALE_RECONCILE_REQUIRED`.
- Latch semantics: OPEN blocked; CLOSE/HEDGE/CANCEL allowed except risk-increasing cancel/replace rejected per §2.2.5.
