---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_DISPATCH_reconciliation.md
story_id: S1-005
story_title: "Dispatcher amount mapping"
gate_result: GO
story_verdict: RECONCILED
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-005 (Dispatcher amount mapping)

## A) GATE RESULT

```
GATE: GO
Reason: Premortem §10 STOPLIGHT = GREEN. All required artifacts present. No blockers.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Dispatcher Rules | `crates/soldier_core/src/execution/dispatch_map.rs:140-163::map_to_dispatch_unchecked` (amount mapping) and `dispatch_map.rs:126-138::map_to_dispatch` (contracts gate) | test_option_amount_is_qty_coin (line 18), test_perpetual_amount_is_qty_usd (line 54), test_linear_future_amount_is_qty_coin (line 36), test_inverse_future_amount_is_qty_usd (line 72), test_at277_option_dispatch_roundtrip (line 247), test_at277_perpetual_dispatch_roundtrip (line 265), test_option_only_one_amount_field (line 92), test_open_intent_not_reduce_only (line 159), test_close_intent_is_reduce_only (line 174), test_intent_class_reduce_only_table (line 219) | Yes — outbound `amount` field asserted against expected canonical value; reduce_only asserted per intent class | Yes — missing qty_coin/qty_usd returns typed error; contracts present forces validation path | Yes (see §5 below) | Yes (see §4 below) | **PROVEN** |

### Enforcement point detail:
- `dispatch_map.rs:145-152`: `match instrument_kind` selects qty_coin for Option/LinearFuture, qty_usd for Perpetual/InverseFuture
- `dispatch_map.rs:154-157`: `match intent` maps Open→false, Close/Hedge/Cancel→true for reduce_only
- `dispatch_map.rs:126-138`: Contracts present → must use validate_and_dispatch path

### Fail-closed verification:
- Missing qty_coin: **Rejected** (`MissingQtyCoin`) — tested (line 112)
- Missing qty_usd: **Rejected** (`MissingQtyUsd`) — tested (line 127)
- Contracts without validation: **Rejected** (`ContractsRequireValidation`) — tested (line 143)
- No unwrap() in production code: **CONFIRMED**

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | OrderSize from S1-004 always has correct canonical field | Round-trip test | **TESTED**: `test_at277_option_dispatch_roundtrip` (line 247), `test_at277_perpetual_dispatch_roundtrip` (line 265) |
| 2 | Deribit API accepts exactly one of amount/contracts | Killed in premortem | **KILLED** |
| 3 | Intent classification available at dispatch time | Table-driven intent test | **TESTED**: `test_intent_class_reduce_only_table` (line 219) — all 4 intent classes |
| 4 | Linear perpetuals use qty_coin like linear_future | Test USDC perp → qty_coin | **TESTED**: `test_linear_future_amount_is_qty_coin` (line 36) |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| Outbound request representation | A — Single `amount: f64` field | **YES** | `dispatch_map.rs:44-52`: `DispatchRequest { pub amount: f64, pub reduce_only: bool }` |
| reduce_only mapping for unknown intent | A — Fail-closed | **YES** — exhaustive match on closed enum; no "unknown" case possible | `dispatch_map.rs:154-157` |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Always send amount=qty_coin | **YES** | `test_perpetual_amount_is_qty_usd` (line 54), `test_inverse_future_amount_is_qty_usd` (line 72) | **YES** |
| Set reduce_only=true for ALL intents | **YES** | `test_open_intent_not_reduce_only` (line 159) | **YES** |
| Send both amount fields | **N/A** | DispatchRequest has single `amount: f64` — structural prevention | **YES** |
| Map reduce_only correctly but forget amount > 0 validation | **PARTIAL** | No dispatch-level guard; upstream build_order_size catches | **WEAK** |

## D) DESIGN RISK NOTES

- **INFO**: amount > 0 not validated at dispatch level (upstream catches).
- **INFO**: Cancel → reduce_only=true is conservative design choice not in contract.
- No silent reject paths.
- No unwrap() in production code.

## E) REMEDIATION PLAN

```
[INFO]      No amount > 0 guard in dispatch mapping. Low risk.
[INFO]      Cancel → reduce_only=true is conservative. INFO.
```

## F) SCOPE CHECK

All scope.touch files exist. No scope drift.

```
READY FOR SELF_REVIEW
```
