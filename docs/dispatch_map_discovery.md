# Dispatch Map Discovery Report (S1-009)

## Scope

Dispatcher amount mapping for Deribit requests (canonical amount selection + mismatch rejection).
This report informs S1-005 (Dispatcher amount mapping) and S1-007 (Dispatcher mismatch rejection).

## Current implementation

**None.** Crates were reset to empty scaffolding (bootstrap commit `02b5f6c`).

- `crates/soldier_core/src/lib.rs` — contains only `crate_bootstrapped() -> bool`
- No dispatch mapping logic, no `DeribitOrderAmount`, no tests

A prior implementation existed but was intentionally discarded for clean reimplementation.

## Call sites

None. No production or test code references dispatch mapping.

## Contract requirements (CONTRACT.md §1.0)

### Dispatcher Rules (Deribit request mapping)

1. Determine `instrument_kind` from instrument metadata (`option | linear_future | inverse_future | perpetual`)
2. Compute size fields:
   - `option | linear_future`: canonical = `qty_coin`; derive `contracts` if contract multiplier is defined
   - Linear perpetuals (USDC-margined) are treated as `linear_future`
   - `perpetual | inverse_future`: canonical = `qty_usd`; derive `contracts = round(qty_usd / contract_size_usd)` if defined; derive `qty_coin = qty_usd / index_price`
3. **Outbound order size field**: always send exactly one canonical "amount" value:
   - coin instruments → send `amount = qty_coin`
   - USD-sized instruments → send `amount = qty_usd`
4. If `contracts` exists, it must be consistent with the canonical amount before dispatch (reject if not)

### Mismatch rejection rules

- Tolerance: `contracts_amount_match_tolerance = 0.001` (0.1%)
- Formula: `abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon) <= 0.001` where `epsilon = 1e-9`
- On mismatch: reject intent with `Rejected(ContractsAmountMismatch)` and set `RiskState::Degraded`
- Dispatch count must remain 0 on rejection

### Reduce-only flag (IMPLEMENTATION_PLAN S1.3)

- Outbound `reduce_only` flag MUST be set from intent classification:
  - `CLOSE`/`HEDGE` intents → `reduce_only=true`
  - `OPEN` intents → `reduce_only=false` or omitted
- This flag MUST NOT be derived from `TradingMode`

### Acceptance tests

- **AT-277**: option uses `amount=qty_coin` (coin), perp uses `amount=qty_usd` (USD); option `qty_usd` unset; mismatches rejected
- **AT-920**: contracts/amount mismatch beyond tolerance → `Rejected(ContractsAmountMismatch)`, dispatch count 0, `RiskState::Degraded`

## Gaps vs contract (from clean slate)

Everything is a gap — full implementation needed:

1. `map_order_size_to_deribit_amount()` function selecting canonical amount by `InstrumentKind`
2. Outbound `DeribitOrderAmount` struct (or equivalent) with exactly one `amount` field
3. Contracts consistency validation using tolerance `0.001`
4. Contracts derivation from canonical amount when multiplier/contract_size is available
5. `qty_coin` derivation for USD-sized instruments: `qty_usd / index_price`
6. Mismatch rejection with `Rejected(ContractsAmountMismatch)` reason code
7. `RiskState::Degraded` transition on mismatch
8. `reduce_only` flag from intent classification (not TradingMode)
9. Observability: counter `order_intent_reject_unit_mismatch_total`
10. Rejection for invalid `index_price <= 0` on USD-sized instruments

## Required tests (for S1-005 and S1-007)

### S1-005 (Dispatcher amount mapping)

| Test | What it proves |
|------|---------------|
| `test_dispatch_amount_field_coin_vs_usd` | Option/linear sends `amount=qty_coin`; perp/inverse sends `amount=qty_usd` |
| `test_dispatch_derives_qty_coin_for_usd` | USD-sized instruments derive `qty_coin = qty_usd / index_price` |
| `test_dispatch_derives_contracts_from_canonical` | `contracts` derived via rounding when multiplier available |
| `test_dispatch_rejects_missing_canonical` | Missing canonical amount → rejection |
| `test_dispatch_rejects_invalid_index_price` | `index_price <= 0` for USD instruments → rejection |
| `test_reduce_only_flag_set_by_intent_classification` | CLOSE/HEDGE → `reduce_only=true`; OPEN → false/omitted |

### S1-007 (Dispatcher mismatch rejection)

| Test | What it proves |
|------|---------------|
| `test_dispatch_mismatch_rejects_and_degrades` | Contracts/amount mismatch → `Rejected(ContractsAmountMismatch)` + `RiskState::Degraded` |
| `test_dispatch_mismatch_within_tolerance_accepted` | Match within 0.001 tolerance → accepted |
| `test_dispatch_mismatch_missing_multiplier_rejects` | `contracts` present but no multiplier → rejection |
| `test_dispatch_mismatch_zero_dispatch_count` | On rejection, dispatch count remains 0 |

## Minimal implementation diff

### S1-005 — Dispatcher amount mapping

**File:** `crates/soldier_core/src/execution/dispatch_map.rs`

1. Import `InstrumentKind` from S1-002 and `OrderSize` from S1-004
2. Define `DeribitOrderAmount { amount: f64, derived_qty_coin: Option<f64> }`
3. Define `DispatchRejectReason` enum including `ContractsAmountMismatch`, `MissingCanonicalAmount`, `InvalidIndexPrice`
4. Implement `map_order_size_to_deribit_amount(kind, order_size, contract_multiplier, index_price) -> Result<DeribitOrderAmount, DispatchReject>`
   - Select canonical amount by kind
   - Derive `qty_coin` for USD-sized instruments
   - Derive `contracts` when multiplier available
5. Add `reduce_only` mapping from intent classification
6. Wire into `crates/soldier_core/src/execution/mod.rs` re-export

**Test file:** `crates/soldier_core/tests/test_dispatch_map.rs`

### S1-007 — Dispatcher mismatch rejection

**File:** Same `dispatch_map.rs`

1. Add contracts/amount consistency check with tolerance `0.001`
2. Reject with `ContractsAmountMismatch` on mismatch
3. Set `RiskState::Degraded` on mismatch rejection
4. Increment `order_intent_reject_unit_mismatch_total` counter
5. Handle missing multiplier when contracts present

**Test file:** `crates/soldier_core/tests/test_dispatch_map.rs`

### Dependencies

- `InstrumentKind` from S1-002 (`crates/soldier_core/src/venue/types.rs`)
- `OrderSize` from S1-004 (`crates/soldier_core/src/execution/order_size.rs`)
- `RiskState` from S1-002 (`crates/soldier_core/src/risk/state.rs`)
- Intent classification (OPEN/CLOSE/HEDGE) — may need to be defined or imported
