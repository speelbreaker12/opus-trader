#### **2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001**
Profile: CSP

**Goal:** Prevent "false-safe opens" after restart, WS gaps, or session termination until reconciliation proves state truth.

**Semantics:**
- If `open_permission_blocked_latch == true`:
  - OPEN intents MUST be blocked.
  - CLOSE / HEDGE / CANCEL intents MUST remain allowed, except risk-increasing cancels/replaces MUST be rejected per §2.2.5.

**State fields:**
- `open_permission_blocked_latch` (bool; `true` means OPEN blocked)
- `open_permission_reason_codes` (`OpenPermissionReasonCode[]`; MUST be `[]` iff `open_permission_blocked_latch == false`)
- `open_permission_requires_reconcile` (bool; MUST equal `open_permission_blocked_latch` for v5.2 - all reason codes are reconcile-class)

**Acceptance Tests (References):**
- AT-027 in §7.0 validates `/status` latch field invariants.

**Deterministic reconstruction (preferred; no persistence):**
- On startup, set `open_permission_blocked_latch = true` with reason `RESTART_RECONCILE_REQUIRED`.
- The latch MUST clear only after reconciliation succeeds.

**Reconciliation success criteria (required):**
- Ledger inflight intents (non-terminal) match exchange open orders by label (all matched within label disambiguation rules per §1.1.2).
- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon` (default: instrument's `min_amount` or `1e-6` if undefined).
- No missing trades over the last `reconcile_trade_lookback_sec` (default: 300s) as determined by REST `/get_user_trades` query.
- All reconcile-class reason codes cleared (no unresolved WS gaps, inventory mismatches, or session termination flags).

AT-1100
- Given: reconciliation runs and REST `/get_user_trades` over the last `reconcile_trade_lookback_sec` returns trades that are not present in the local ledger (missing trades).
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked until the missing trades are resolved and a subsequent reconciliation pass succeeds.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite missing trades, or latch clears prematurely.

**Allowed values (reconcile-only):** `OpenPermissionReasonCode[]`
- `RESTART_RECONCILE_REQUIRED`
- `WS_BOOK_GAP_RECONCILE_REQUIRED`
- `WS_TRADES_GAP_RECONCILE_REQUIRED`
- `WS_DATA_STALE_RECONCILE_REQUIRED`
- `INVENTORY_MISMATCH_RECONCILE_REQUIRED`
- `SESSION_TERMINATION_RECONCILE_REQUIRED`

**Hard rule:** Runtime-binding and EvidenceChain failures MUST NOT appear in `open_permission_reason_codes` (they are cleared by cert/evidence recovery, not reconciliation).

**Acceptance Tests (REQUIRED):**
AT-010
- Given: `open_permission_blocked_latch==true` with `open_permission_reason_codes` containing `RESTART_RECONCILE_REQUIRED`.
- When: the system evaluates an OPEN intent for dispatch.
- Then: no OPEN order is dispatched; CLOSE/HEDGE/CANCEL intents remain dispatchable, except risk-increasing cancels/replaces are rejected (per §2.2.5), subject to Kill semantics in §2.2.3.
- Pass criteria: OPEN dispatch count remains 0; CLOSE/HEDGE/CANCEL dispatch is permitted; risk-increasing cancel/replace is rejected.
- Fail criteria: any OPEN is dispatched while the latch is true.

AT-430
- Given: startup occurs with no persisted latch state.
- When: initialization completes before reconciliation runs.
- Then: `open_permission_blocked_latch == true`, `open_permission_reason_codes` contains `RESTART_RECONCILE_REQUIRED`, and `open_permission_requires_reconcile == true`.
- Pass criteria: latch fields match expected startup values and OPEN remains blocked.
- Fail criteria: latch not set, reason missing, or OPEN allowed before reconciliation.

AT-011
- Given: `open_permission_blocked_latch==true` for a WS gap reason (e.g., `WS_TRADES_GAP_RECONCILE_REQUIRED`).
- When: reconciliation succeeds (all criteria in this section are satisfied).
- Then: the latch clears (`open_permission_blocked_latch==false` and `open_permission_reason_codes==[]`), and opens may proceed only if PolicyGuard computes `TradingMode::Active`.
- Pass criteria: latch fields match the invariants immediately after reconciliation; opens remain blocked unless mode is Active.
- Fail criteria: latch clears without reconciliation success, or opens proceed while latch remains true.

AT-402
- Given: `open_permission_blocked_latch==true` with `open_permission_reason_codes` containing `RESTART_RECONCILE_REQUIRED` and a cancel/replace that increases exposure.
- When: cancel/replace permission is evaluated.
- Then: the cancel/replace is rejected until reconciliation clears the latch.
- Pass criteria: risk-increasing cancel blocked while latch is true; allowed only after latch clears and other gates allow.
- Fail criteria: risk-increasing cancel allowed while latch is true.

AT-110
- Given: `open_permission_blocked_latch==true`.
- When: an order placement intent is evaluated with `reduce_only` missing or null.
- Then: it MUST be treated as OPEN and blocked.
- Pass criteria: no order placement is dispatched.
- Fail criteria: any order placement dispatch occurs while `reduce_only` is missing and latch is true.

AT-411
- Given: runtime binding cert is missing/stale/FAIL OR (`EvidenceChainState != GREEN` and `enforced_profile != CSP`), and no reconcile-class triggers are active.
- When: `open_permission_reason_codes` are computed.
- Then: `open_permission_reason_codes` does not include runtime-binding or EvidenceChain failures, and `open_permission_blocked_latch` is unchanged.
- Pass criteria: no F1/Evidence codes in reason list; latch not set without a reconcile trigger.
- Fail criteria: any F1/Evidence code appears or latch is set without a reconcile trigger.


