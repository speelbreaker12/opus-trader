---
provenance:
  tool: claude-code
  model: claude-opus-4-20250514
  prompt_style: R1-agent (reconciliation)
  cycle: recon-v3.1-upgrade
  phase_equivalent: R6
source_batch: BATCH_DISPATCH_reconciliation.md
story_id: S1-004
story_title: "OrderSize canonical sizing"
gate_result: GO
story_verdict: RECONCILED
extraction_date: "2026-02-23"
---

# RECONCILIATION AUDIT: S1-004 (OrderSize canonical sizing)

## A) GATE RESULT

```
GATE: GO
Reason: Premortem §10 STOPLIGHT = GREEN. All required artifacts present. No blockers.
```

## B) AT AUDIT TABLE

| AT ID | Contract § | Enforcement point (file:line::function) | Proving test(s) | Causal proof? | Fail-closed? | §5 wrong impls blocked? | §4 decision as chosen? | Verdict |
|-------|-----------|----------------------------------------|-----------------|---------------|-------------|------------------------|----------------------|---------|
| AT-277 | §1.0 Instrument Units & Notional Invariants | `crates/soldier_core/src/execution/order_size.rs:97-133::build_order_size` | test_at277_option_sizing (line 13), test_at277_perpetual_sizing (line 29), test_option_canonical_is_qty_coin (line 48), test_perpetual_canonical_is_qty_usd (line 78), test_linear_future_canonical_is_qty_coin (line 63), test_inverse_future_canonical_is_qty_usd (line 92), test_notional_usd_always_populated (line 110) | Yes — field-value equality assertions for qty_coin, qty_usd, notional_usd against contract worked examples | Yes — validates index_price >0 finite (line 85), canonical_qty >0 finite (line 88), contract_multiplier >0 finite (line 91); returns typed errors on failure | Yes (see §5 below) | Yes (see §4 below) | **PROVEN** |

### Enforcement point detail:
- `order_size.rs:97-132`: `match input.instrument_kind` branches for Option/LinearFuture vs Perpetual/InverseFuture
- `order_size.rs:83-95`: Input validation rejects non-finite/non-positive index_price, canonical_qty, contract_multiplier

### Fail-closed verification:
- Zero index_price: **Rejected** (line 85-86, `InvalidIndexPrice`) — tested `test_zero_index_price_rejected` (test file line 178)
- NaN index_price: **Rejected** (line 85, `!is_finite()`) — tested `test_nan_index_price_rejected` (test file line 208)
- Negative index_price: **Rejected** (line 85, `<= 0.0`) — tested `test_negative_index_price_rejected` (test file line 193)
- Zero canonical_qty: **Rejected** (line 88-89) — tested `test_zero_canonical_qty_rejected` (test file line 223)
- Invalid contract_multiplier: **Rejected** (line 91-95) — tested `test_invalid_contract_multiplier_rejected` (test file line 238)
- No `unwrap()` in production code: **CONFIRMED**

## C) PREMORTEM CROSS-REFERENCE

### §2 Assumptions

| # | Assumption | Predicted test | Actual status |
|---|-----------|---------------|---------------|
| 1 | `index_price` always > 0 | Test with index_price=0 → must reject | **TESTED**: `test_zero_index_price_rejected` (line 178). Also NaN (line 208), negative (line 193). |
| 2 | InstrumentKind correctly classifies USDC-margined linear perps as `linear_future` | Test: USDC-margined perp → canonical must be qty_coin | **PARTIALLY TESTED**: Classification is S1-002 scope. OrderSize correctly defers to InstrumentKind input. |
| 3 | qty_coin and qty_usd are mutually exclusive for canonical | Test: option → qty_usd must be None; perp → qty_coin is derived | **TESTED**: `test_at277_option_sizing` (line 23) asserts `qty_usd == None`. |

### §4 Decisions

| Decision | Chosen option | Implemented? | Evidence (file:line) |
|----------|--------------|-------------|---------------------|
| OrderSize constructor API shape | A — `build_order_size(OrderSizeInput)` | **YES** | `order_size.rs:83` |
| What to do when index_price is zero or NaN | A — Return error (fail-closed) | **YES** | `order_size.rs:85-86` |

### §5 Wrong Impls

| Wrong impl | Tightening test exists? | Test name | Catches the wrong impl? |
|-----------|------------------------|-----------|------------------------|
| Hardcode notional_usd=30_000 | **YES** | `test_option_canonical_is_qty_coin` (line 48): qty_coin=1.5, index_price=50_000 → notional_usd=75_000 | **YES** |
| Set qty_usd=None for ALL instrument kinds | **YES** | `test_at277_perpetual_sizing` (line 29): asserts `qty_usd == Some(30_000)` | **YES** |
| Leave qty_coin/qty_usd fields swapped | **YES** | `test_at277_option_sizing` (line 13) + `test_at277_perpetual_sizing` (line 29) | **YES** |
| Use mark_price instead of index_price | **YES** | Constructor API only receives `index_price` — structural prevention | **YES** |

## D) DESIGN RISK NOTES

- No fail-open paths found.
- No hidden assumptions.
- No silent reject paths. All rejections return typed `OrderSizeError`.
- No unwrap() in production code.
- **INFO**: No tracing log for OrderSize computation success. Observability debt.

## E) REMEDIATION PLAN

```
[INFO]      No P0 or P1 gaps found for S1-004.
[INFO]      Observability: no tracing log for successful computation.
```

## F) SCOPE CHECK

All scope.touch files exist. No scope drift.

```
READY FOR SELF_REVIEW
```
