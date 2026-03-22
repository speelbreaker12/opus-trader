#### **2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001**
Profile: CSP

**Goal:** Prevent "false-safe opens" after restart, WS gaps, or session termination until reconciliation proves state truth.

**Semantics:**
- If `open_permission_blocked_latch == true`:
  - OPEN intents MUST be blocked.
  - CLOSE / HEDGE / CANCEL intents MUST remain allowed, except risk-increasing cancels/replaces MUST be rejected per §2.2.5.
- When `open_permission_blocked_latch == true`, the latch feeds into PolicyGuard's `SystemIntegrityAxis` as a `DEGRADED` input (§2.2.3.2), producing `TradingMode::ReduceOnly`. OPEN blocking is enforced both directly (latch gate) and indirectly (via PolicyGuard TradingMode dispatch authorization).
  - _Indirect path acceptance test:_ See §2.2.3.2 SystemIntegrityAxis ATs which MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into SystemIntegrityAxis, producing `TradingMode::ReduceOnly`.

**State fields:**
- `open_permission_blocked_latch` (bool; `true` means OPEN blocked)
- `open_permission_reason_codes` (`OpenPermissionReasonCode[]`; MUST be `[]` iff `open_permission_blocked_latch == false`)
- `open_permission_requires_reconcile` (bool; MUST equal `open_permission_blocked_latch` for v5.2 - all reason codes are reconcile-class)

**Acceptance Tests (References):**
- AT-027 in §7.0 validates `/status` latch field invariants.

**Deterministic reconstruction (required; no persistence):**
- On startup, set `open_permission_blocked_latch = true` with reason `RESTART_RECONCILE_REQUIRED`.
- The latch MUST clear only after reconciliation succeeds.

**Reconciliation success criteria (required):**
- Ledger inflight intents (non-terminal) match exchange open orders by label (all matched within label disambiguation rules per §1.1.2).
- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon` (default: instrument's `min_amount` or `1e-6` if undefined).
- No missing trades over the last `reconcile_trade_lookback_sec` (default: 300s) as determined by REST `/get_user_trades` query. If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
- All reconcile-class reason codes cleared (no unresolved WS gaps, inventory mismatches, or session termination flags).

**Reconciliation stall observability (deterministic, no override-clear):**
- If reconciliation remains blocked and `open_permission_blocked_latch` stays true for longer than `reconcile_stall_max_delay_s` (default: 30s), runtime MUST emit structured log `RECONCILE_STALL` and increment counter metric `reconcile_stall_total`.
- If `reconcile_stall_max_delay_s` is missing or ≤ 0 at startup, runtime MUST treat it as the default (30s) and emit a startup warning log.
- `RECONCILE_STALL` payload MUST include the failing criterion that is preventing reconciliation success.
- Emission cadence MUST be deterministic: for a continuous stall episode, emit once when the threshold is first exceeded; re-emit only if the failing criterion changes during that same episode.
- A new emission episode starts only after reconciliation success clears the stall condition/latch, and a later stall exceeds the threshold again.
- This observability rule MUST NOT clear or override the latch; latch clears only after reconciliation success criteria are satisfied.

AT-1243
- Given: `open_permission_blocked_latch == true` and reconciliation remains blocked beyond `reconcile_stall_max_delay_s`.
- When: reconciliation stall observability evaluates.
- Then: runtime emits structured `RECONCILE_STALL` log with the failing criterion, increments `reconcile_stall_total`, and keeps latch set with no override-clear.
- And: for one continuous stall episode, emission occurs once at first threshold exceedance, with re-emission only on failing-criterion change; a new episode can emit again only after clear and re-stall.
- Pass criteria: log + counter emitted with deterministic cadence and failing criterion; latch remains set.
- Fail criteria: missing log/counter, missing failing criterion payload, repeated spam emission without criterion change/new episode, or latch cleared without reconciliation success.

AT-1100
- Given: reconciliation runs and REST `/get_user_trades` over the last `reconcile_trade_lookback_sec` returns trades that are not present in the local ledger (missing trades).
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked until the missing trades are resolved and a subsequent reconciliation pass succeeds.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite missing trades, or latch clears prematurely.

AT-1263
- Given: `open_permission_blocked_latch == true`; REST `/get_user_trades` returns network error, timeout, HTTP error, or unparseable response.
- When: reconciliation success criteria are evaluated.
- Then: reconciliation fails; `open_permission_blocked_latch` remains true; OPEN blocked.
- Pass criteria: latch held; reconciliation reported failed. Fail criteria: latch clears on transport failure.

AT-1268
- Given: reconciliation runs; ledger inflight intents (non-terminal) do NOT match exchange open orders by label (e.g., ledger has an inflight BUY that exchange does not list, or exchange lists an order not in ledger).
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite inflight intent mismatch, or latch clears prematurely.

AT-1269
- Given: reconciliation runs; exchange position differs from ledger cumulative fills by more than `position_reconcile_epsilon`.
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite position exceeding epsilon, or latch clears prematurely.

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

AT-1242
- Given: the system is running with `open_permission_blocked_latch==false` (latch clear, normal operation).
- When: one of the following trigger events occurs: (a) WS book gap detected, (b) WS trades gap detected, (c) WS data becomes stale beyond threshold, (d) inventory mismatch detected between ledger and exchange, (e) exchange session termination received.
- Then: `open_permission_blocked_latch` MUST be set to `true` and `open_permission_reason_codes` MUST contain the corresponding reason code (`WS_BOOK_GAP_RECONCILE_REQUIRED`, `WS_TRADES_GAP_RECONCILE_REQUIRED`, `WS_DATA_STALE_RECONCILE_REQUIRED`, `INVENTORY_MISMATCH_RECONCILE_REQUIRED`, or `SESSION_TERMINATION_RECONCILE_REQUIRED` respectively); OPEN intents MUST be blocked.
- Pass criteria: latch transitions to `true` with the correct reason code; OPEN dispatch count remains 0 while latch is set.
- Fail criteria: latch remains `false` after trigger event, reason code is missing/incorrect, or OPEN dispatches while latch is set.

AT-1270
- Given: `open_permission_blocked_latch == true` with `open_permission_reason_codes` containing both `WS_BOOK_GAP_RECONCILE_REQUIRED` and `INVENTORY_MISMATCH_RECONCILE_REQUIRED`.
- When: the WS book gap trigger resolves (reconciliation for that criterion succeeds) but inventory mismatch remains unresolved.
- Then: `open_permission_blocked_latch` MUST remain `true`; `open_permission_reason_codes` MUST contain `INVENTORY_MISMATCH_RECONCILE_REQUIRED` and MUST NOT contain `WS_BOOK_GAP_RECONCILE_REQUIRED`; OPEN intents MUST remain blocked.
- And: latch clears only when ALL reason codes are resolved and full reconciliation succeeds.
- Pass criteria: latch stays true with only the remaining reason code; OPEN dispatch count remains 0.
- Fail criteria: latch clears while any reason code remains, or reason_codes list is incorrect after partial resolution.

AT-011
- Given: `open_permission_blocked_latch==true` for a WS gap reason (e.g., `WS_TRADES_GAP_RECONCILE_REQUIRED`).
- When: reconciliation succeeds (all criteria in this section are satisfied).
- Then: the latch clears (`open_permission_blocked_latch==false` and `open_permission_reason_codes==[]`), and opens may proceed only if PolicyGuard computes `TradingMode::Active`.
- Pass criteria: latch fields match the invariants immediately after reconciliation; opens remain blocked unless mode is Active.
- Fail criteria: latch clears without reconciliation success, or opens proceed while latch remains true.

AT-1271
- Given: any state transition that sets `open_permission_blocked_latch` to `true` (startup, WS gap, WS trades gap, WS data stale, inventory mismatch, session termination).
- When: the latch transitions to `true`.
- Then: `open_permission_reason_codes` MUST be non-empty and MUST contain at least one valid `OpenPermissionReasonCode` corresponding to the trigger.
- And: conversely, any state where `open_permission_reason_codes == []` MUST have `open_permission_blocked_latch == false`.
- Pass criteria: biconditional invariant holds at every latch mutation point; no state where latch=true with empty codes or latch=false with non-empty codes.
- Fail criteria: latch set to true with empty reason_codes, or reason_codes non-empty with latch false.

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
- Note: This AT tests the Hard rule (runtime-binding and EvidenceChain failures MUST NOT appear in `open_permission_reason_codes`) in isolation. The Hard rule is unconditional — it applies regardless of whether reconcile-class triggers are concurrently active. The "no reconcile-class triggers" precondition isolates the test from latch interactions but does not limit the Hard rule's scope.

AT-1253
- Given: runtime binding cert is missing/stale/FAIL AND a reconcile-class trigger is concurrently active (e.g., `WS_BOOK_GAP_RECONCILE_REQUIRED`).
- When: `open_permission_reason_codes` are computed.
- Then: `open_permission_reason_codes` contains the reconcile-class reason code but MUST NOT contain runtime-binding or EvidenceChain failure codes.
- Pass criteria: only reconcile-class codes in reason list; no F1/Evidence codes despite concurrent cert failure.
- Fail criteria: F1/Evidence codes appear in `open_permission_reason_codes`.

- _Indirect path acceptance test:_ AT-1272 in this section MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into `SystemIntegrityAxis`, producing `TradingMode::ReduceOnly` and blocking OPEN dispatch through PolicyGuard authorization.

AT-1272
- Given: `open_permission_blocked_latch == true` due to any reconcile-class reason code.
- When: PolicyGuard evaluates `SystemIntegrityAxis` and dispatch authorization for an OPEN intent.
- Then: `open_permission_blocked_latch == true` MUST feed `DEGRADED` into `SystemIntegrityAxis`, `TradingMode` MUST resolve to `ReduceOnly`, and the OPEN intent MUST be rejected through PolicyGuard dispatch authorization.
- Pass criteria: `DEGRADED` input is recorded in `SystemIntegrityAxis`; `TradingMode::ReduceOnly` is computed; OPEN dispatch count remains 0.
- Fail criteria: the latch does not feed `DEGRADED`, `TradingMode` resolves to `Active`, or OPEN dispatch is allowed.

AT-1273
- Given: startup occurs with `reconcile_stall_max_delay_s` missing, and separately with `reconcile_stall_max_delay_s <= 0`.
- When: runtime initializes reconciliation stall observability before reconciliation begins.
- Then: runtime MUST treat the effective threshold as the default `30s` and emit a startup warning log in both cases.
- And: if reconciliation later remains blocked continuously, `RECONCILE_STALL` emission MUST first occur only after the default `30s` threshold is exceeded.
- Pass criteria: startup warning log emitted for both invalid-input cases; effective threshold equals `30s`; later stall observability uses the default threshold.
- Fail criteria: no startup warning is emitted, effective threshold differs from `30s`, or later stall observability uses the invalid configured value.
