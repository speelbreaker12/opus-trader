# Contract Review Package

- run_id: `phase2-p4-opl-20260319_032304-1aa3453e`
- contract_file_hash: `5305f46bb335a7d41ac16aa4a249302de523172fec4392ecadf0655aedd9e72c`
- proposals_file_hash: `f401e5a8d49ddb1d33a5f2673cd2d06a81f407706d281be499917908a121dcd6`
- proposal_count: `5`

## Manual Review Checklist

1. Read every proposal below.
2. Record one decision per proposal in `REVIEW_DECISIONS_<run_id>.json`.
3. Use `accepted`, `rejected`, or `pending_scope_review` only.
4. Re-run `harness.sh contract render-review --accepted-only` after writing review decisions.
5. Do not apply any accepted-only patch if the live `CONTRACT.md` hash differs from the recorded `contract_file_hash`.
6. Keep `sample_contract_patch` proposals rejected unless explicitly moved to a first-party fixture.

## P-001 — missing_at_pair

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-p4-opl-20260319_032304-1aa3453e/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `§2.2.4 Reconciliation success criteria`
- change_type: `new_requirement`
- source_finding: `F-001`
- current_status: `proposed`

### Rationale

Reconciliation criteria 1 (inflight intent matching) and 2 (position within epsilon) lack failure-path ATs. An implementation could skip either check and prematurely clear the latch, allowing OPEN intents. AT-1100 and AT-1263 cover criterion 3 (missing trades/REST failure); criteria 1 and 2 need equivalent coverage to prevent selective omission.

### Proposed Text

```text
AT-PROP-400
- Given: reconciliation runs; ledger inflight intents (non-terminal) do NOT match exchange open orders by label (e.g., ledger has an inflight BUY that exchange does not list, or exchange lists an order not in ledger).
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite inflight intent mismatch, or latch clears prematurely.

AT-PROP-401
- Given: reconciliation runs; exchange position differs from ledger cumulative fills by more than `position_reconcile_epsilon`.
- When: reconciliation success criteria are evaluated.
- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
- Fail criteria: reconciliation succeeds despite position exceeding epsilon, or latch clears prematurely.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -2999,1 +2999,16 @@
 - Fail criteria: reconciliation succeeds despite missing trades, or latch clears prematurely.
 
+AT-PROP-400
+- Given: reconciliation runs; ledger inflight intents (non-terminal) do NOT match exchange open orders by label (e.g., ledger has an inflight BUY that exchange does not list, or exchange lists an order not in ledger).
+- When: reconciliation success criteria are evaluated.
+- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
+- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
+- Fail criteria: reconciliation succeeds despite inflight intent mismatch, or latch clears prematurely.
+
+AT-PROP-401
+- Given: reconciliation runs; exchange position differs from ledger cumulative fills by more than `position_reconcile_epsilon`.
+- When: reconciliation success criteria are evaluated.
+- Then: reconciliation MUST fail; `open_permission_blocked_latch` MUST remain `true`; OPEN intents MUST remain blocked.
+- Pass criteria: reconciliation fails; latch remains set; OPEN blocked.
+- Fail criteria: reconciliation succeeds despite position exceeding epsilon, or latch clears prematurely.
+
 **Allowed values (reconcile-only):** `OpenPermissionReasonCode[]`
```

## P-002 — missing_at_pair

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-p4-opl-20260319_032304-1aa3453e/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `§2.2.4 Acceptance Tests`
- change_type: `new_requirement`
- source_finding: `F-002`
- current_status: `proposed`

### Rationale

AT-1242 tests each trigger event individually and AT-011 tests reconciliation clearing a single reason. No AT covers concurrent reason codes where one resolves and another remains. An implementation could incorrectly clear the latch when removing one code even though another code is still active, allowing premature OPEN dispatch.

### Proposed Text

```text
AT-PROP-402
- Given: `open_permission_blocked_latch == true` with `open_permission_reason_codes` containing both `WS_BOOK_GAP_RECONCILE_REQUIRED` and `INVENTORY_MISMATCH_RECONCILE_REQUIRED`.
- When: the WS book gap trigger resolves (reconciliation for that criterion succeeds) but inventory mismatch remains unresolved.
- Then: `open_permission_blocked_latch` MUST remain `true`; `open_permission_reason_codes` MUST contain `INVENTORY_MISMATCH_RECONCILE_REQUIRED` and MUST NOT contain `WS_BOOK_GAP_RECONCILE_REQUIRED`; OPEN intents MUST remain blocked.
- And: latch clears only when ALL reason codes are resolved and full reconciliation succeeds.
- Pass criteria: latch stays true with only the remaining reason code; OPEN dispatch count remains 0.
- Fail criteria: latch clears while any reason code remains, or reason_codes list is incorrect after partial resolution.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -3038,0 +3039,10 @@
 
+AT-PROP-402
+- Given: `open_permission_blocked_latch == true` with `open_permission_reason_codes` containing both `WS_BOOK_GAP_RECONCILE_REQUIRED` and `INVENTORY_MISMATCH_RECONCILE_REQUIRED`.
+- When: the WS book gap trigger resolves (reconciliation for that criterion succeeds) but inventory mismatch remains unresolved.
+- Then: `open_permission_blocked_latch` MUST remain `true`; `open_permission_reason_codes` MUST contain `INVENTORY_MISMATCH_RECONCILE_REQUIRED` and MUST NOT contain `WS_BOOK_GAP_RECONCILE_REQUIRED`; OPEN intents MUST remain blocked.
+- And: latch clears only when ALL reason codes are resolved and full reconciliation succeeds.
+- Pass criteria: latch stays true with only the remaining reason code; OPEN dispatch count remains 0.
+- Fail criteria: latch clears while any reason code remains, or reason_codes list is incorrect after partial resolution.
```

## P-003 — gate_interaction_gap

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-p4-opl-20260319_032304-1aa3453e/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `§2.2.4 Semantics`
- change_type: `new_requirement`
- source_finding: `F-003`
- current_status: `proposed`

### Rationale

Dual enforcement is claimed (direct latch gate + indirect via PolicyGuard SystemIntegrityAxis DEGRADED producing ReduceOnly) but only the direct path has ATs in §2.2.4. If the PolicyGuard integration breaks, the secondary enforcement layer fails silently. A cross-reference to §2.2.3.2 SystemIntegrityAxis ATs makes both enforcement paths auditable without duplicating test ownership.

### Proposed Text

```text
Add cross-reference after the Semantics dual-enforcement statement (line 2959): "Acceptance test for the indirect PolicyGuard path: see §2.2.3.2 SystemIntegrityAxis ATs which MUST verify that `open_permission_blocked_latch == true` feeds DEGRADED into SystemIntegrityAxis, producing `TradingMode::ReduceOnly`."
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -2959,1 +2959,2 @@
 - When `open_permission_blocked_latch == true`, the latch feeds into PolicyGuard's `SystemIntegrityAxis` as a `DEGRADED` input (§2.2.3.2), producing `TradingMode::ReduceOnly`. OPEN blocking is enforced both directly (latch gate) and indirectly (via PolicyGuard TradingMode dispatch authorization).
+  - _Indirect path acceptance test:_ See §2.2.3.2 SystemIntegrityAxis ATs which MUST verify that `open_permission_blocked_latch == true` feeds `DEGRADED` into SystemIntegrityAxis, producing `TradingMode::ReduceOnly`.
```

## P-004 — stale_input_unspecified

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-p4-opl-20260319_032304-1aa3453e/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `§2.2.4 Reconciliation stall observability`
- change_type: `new_requirement`
- source_finding: `F-004`
- current_status: `proposed`

### Rationale

The `reconcile_stall_max_delay_s` parameter has no inline default in §2.2.4, unlike `reconcile_trade_lookback_sec` (default: 300s) and `position_reconcile_epsilon` (default: min_amount or 1e-6) which both specify defaults inline. The config appendix (line 6077) defines 30s but the normative §2.2.4 text is silent. A missing or invalid (≤0) value has undefined behavior — it could disable stall detection entirely (silent failure) or cause immediate spam emission on every tick.

### Proposed Text

```text
Amend the stall observability paragraph (line 2980) to add inline default matching the config appendix: change `reconcile_stall_max_delay_s` to `reconcile_stall_max_delay_s` (default: 30s). Additionally, add fail-closed clause: "If `reconcile_stall_max_delay_s` is missing or ≤ 0 at startup, runtime MUST treat it as the default (30s) and emit a startup warning log."
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -2980,1 +2980,2 @@
-- If reconciliation remains blocked and `open_permission_blocked_latch` stays true for longer than `reconcile_stall_max_delay_s`, runtime MUST emit structured log `RECONCILE_STALL` and increment counter metric `reconcile_stall_total`.
+- If reconciliation remains blocked and `open_permission_blocked_latch` stays true for longer than `reconcile_stall_max_delay_s` (default: 30s), runtime MUST emit structured log `RECONCILE_STALL` and increment counter metric `reconcile_stall_total`.
+- If `reconcile_stall_max_delay_s` is missing or ≤ 0 at startup, runtime MUST treat it as the default (30s) and emit a startup warning log.
```

## P-005 — missing_at_pair

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-p4-opl-20260319_032304-1aa3453e/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `§2.2.4 State fields`
- change_type: `new_requirement`
- source_finding: `F-005`
- current_status: `proposed`

### Rationale

The biconditional invariant (reason_codes MUST be [] iff latch == false) is only tested in the forward direction by AT-011 (reconciliation clears latch → codes empty). No AT tests the reverse: that latch=true always implies non-empty reason_codes. A bug could set latch=true with empty codes, hiding the blocking reason from operators and /status consumers.

### Proposed Text

```text
AT-PROP-403
- Given: any state transition that sets `open_permission_blocked_latch` to `true` (startup, WS gap, WS trades gap, WS data stale, inventory mismatch, session termination).
- When: the latch transitions to `true`.
- Then: `open_permission_reason_codes` MUST be non-empty and MUST contain at least one valid `OpenPermissionReasonCode` corresponding to the trigger.
- And: conversely, any state where `open_permission_reason_codes == []` MUST have `open_permission_blocked_latch == false`.
- Pass criteria: biconditional invariant holds at every latch mutation point; no state where latch=true with empty codes or latch=false with non-empty codes.
- Fail criteria: latch set to true with empty reason_codes, or reason_codes non-empty with latch false.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -3024,0 +3025,10 @@
 
+AT-PROP-403
+- Given: any state transition that sets `open_permission_blocked_latch` to `true` (startup, WS gap, WS trades gap, WS data stale, inventory mismatch, session termination).
+- When: the latch transitions to `true`.
+- Then: `open_permission_reason_codes` MUST be non-empty and MUST contain at least one valid `OpenPermissionReasonCode` corresponding to the trigger.
+- And: conversely, any state where `open_permission_reason_codes == []` MUST have `open_permission_blocked_latch == false`.
+- Pass criteria: biconditional invariant holds at every latch mutation point; no state where latch=true with empty codes or latch=false with non-empty codes.
+- Fail criteria: latch set to true with empty reason_codes, or reason_codes non-empty with latch false.
```
