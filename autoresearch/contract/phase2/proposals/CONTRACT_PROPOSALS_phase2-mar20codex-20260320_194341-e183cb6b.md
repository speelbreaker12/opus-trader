# Contract Proposals

- run_id: `phase2-mar20codex-20260320_194341-e183cb6b`
- proposals_file_hash: `d707b60a84433d0ec691c0fdb3bd29d95d4e6e12d542c1f8363c33a36b9e2467`
- proposal_count: `3`

## P-001

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codex-20260320_194341-e183cb6b/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001`
- source_finding: `F-001`
- source_finding_category: `weak_normative`
- change_type: `new_requirement`
- status: `pending_scope_review`
- dedupe_key: `cp001-position-epsilon-fallback-must`

### Rationale

Makes the reconciliation epsilon fallback a binding runtime rule at the latch-clear decision point so position drift cannot be masked by a looser implementation.

### Proposed Text

```text
- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon`.
- For reconciliation in this section, runtime MUST set `position_reconcile_epsilon` to the instrument's `min_amount`; if `min_amount` is undefined, runtime MUST use `1e-6`. Runtime MUST NOT use a looser fallback when deciding whether the latch may clear.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -25,4 +25,5 @@
 **Reconciliation success criteria (required):**
 - Ledger inflight intents (non-terminal) match exchange open orders by label (all matched within label disambiguation rules per §1.1.2).
-- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon` (default: instrument's `min_amount` or `1e-6` if undefined).
+- Exchange positions match ledger cumulative fills within `position_reconcile_epsilon`.
+- For reconciliation in this section, runtime MUST set `position_reconcile_epsilon` to the instrument's `min_amount`; if `min_amount` is undefined, runtime MUST use `1e-6`. Runtime MUST NOT use a looser fallback when deciding whether the latch may clear.
 - No missing trades over the last `reconcile_trade_lookback_sec` (default: 300s) as determined by REST `/get_user_trades` query. If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
```

## P-002

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codex-20260320_194341-e183cb6b/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001`
- source_finding: `F-002`
- source_finding_category: `stale_input_unspecified`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `cp001-trade-lookback-invalid-fail-closed`

### Rationale

Adds fail-closed handling for invalid trade-lookback inputs so a bad window cannot omit recent trades and clear OPEN blocking prematurely.

### Proposed Text

```text
- No missing trades over the last `reconcile_trade_lookback_sec` as determined by REST `/get_user_trades` query.
- If `reconcile_trade_lookback_sec` is unset, non-numeric, or `<= 0`, runtime MUST either normalize it to `300s` before issuing `/get_user_trades` or fail reconciliation and keep `open_permission_blocked_latch == true`; runtime MUST NOT clear the latch using an invalid lookback window.
- If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -26,4 +26,6 @@
 - Ledger inflight intents (non-terminal) match exchange open orders by label (all matched within label disambiguation rules per §1.1.2).
 - Exchange positions match ledger cumulative fills within `position_reconcile_epsilon` (default: instrument's `min_amount` or `1e-6` if undefined).
-- No missing trades over the last `reconcile_trade_lookback_sec` (default: 300s) as determined by REST `/get_user_trades` query. If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
+- No missing trades over the last `reconcile_trade_lookback_sec` as determined by REST `/get_user_trades` query.
+- If `reconcile_trade_lookback_sec` is unset, non-numeric, or `<= 0`, runtime MUST either normalize it to `300s` before issuing `/get_user_trades` or fail reconciliation and keep `open_permission_blocked_latch == true`; runtime MUST NOT clear the latch using an invalid lookback window.
+- If the REST query fails (network error, timeout, HTTP error, or unparseable response), reconciliation MUST fail closed — the latch MUST remain set and OPEN intents MUST remain blocked.
 - All reconcile-class reason codes cleared (no unresolved WS gaps, inventory mismatches, or session termination flags).
```

## P-003

- fixture: `s2_2_4_open_permission_latch_latest`
- source_path: `contract/phase2/outputs/phase2-mar20codex-20260320_194341-e183cb6b/s2_2_4_open_permission_latch_latest/proposals.json`
- section: `2.2.4 Open Permission Latch (Reconcile-Required, Sticky Until Cleared) — CP-001`
- source_finding: `F-003`
- source_finding_category: `missing_at_pair`
- change_type: `new_requirement`
- status: `proposed`
- dedupe_key: `cp001-reconcile-stall-delay-startup-at`

### Rationale

Adds an acceptance-test pair for the startup fallback and warning path so the 30s normalization rule cannot drift without detection.

### Proposed Text

```text
AT-NEW
- Given: startup begins with `reconcile_stall_max_delay_s` missing, `0`, or a negative value.
- When: configuration normalization completes before reconciliation stall observability evaluates.
- Then: runtime MUST treat `reconcile_stall_max_delay_s` as `30s` and emit a startup warning log.
- Pass criteria: effective threshold is `30s` and one startup warning log is emitted during startup.
- Fail criteria: invalid value is retained, a non-`30s` threshold is used, or the startup warning log is missing.
```

### Diff Preview

```diff
--- a/specs/CONTRACT.md
+++ b/specs/CONTRACT.md
@@ -44,6 +44,13 @@
 - Pass criteria: log + counter emitted with deterministic cadence and failing criterion; latch remains set.
 - Fail criteria: missing log/counter, missing failing criterion payload, repeated spam emission without criterion change/new episode, or latch cleared without reconciliation success.
 
+AT-NEW
+- Given: startup begins with `reconcile_stall_max_delay_s` missing, `0`, or a negative value.
+- When: configuration normalization completes before reconciliation stall observability evaluates.
+- Then: runtime MUST treat `reconcile_stall_max_delay_s` as `30s` and emit a startup warning log.
+- Pass criteria: effective threshold is `30s` and one startup warning log is emitted during startup.
+- Fail criteria: invalid value is retained, a non-`30s` threshold is used, or the startup warning log is missing.
+
 AT-1100
 - Given: reconciliation runs and REST `/get_user_trades` over the last `reconcile_trade_lookback_sec` returns trades that are not present in the local ledger (missing trades).
```
