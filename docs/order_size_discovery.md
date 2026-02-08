# OrderSize Discovery Report (S1-008)

## Scope

OrderSize struct, sizing invariants, and mapping to contract sizing rules.
This report informs S1-004 (OrderSize canonical sizing implementation).

## Current implementation

**None.** Crates were reset to empty scaffolding (bootstrap commit `02b5f6c`).

- `crates/soldier_core/src/lib.rs` — contains only `crate_bootstrapped() -> bool`
- No `OrderSize` struct, no execution module, no tests

A prior implementation existed but was intentionally discarded for clean reimplementation.

## Call sites

None. No production or test code references OrderSize.

## Contract requirements (CONTRACT.md §1.0)

### OrderSize struct (MUST implement)

```rust
pub struct OrderSize {
    pub contracts: Option<i64>,     // integer contracts when applicable
    pub qty_coin: Option<f64>,      // BTC/ETH amount when applicable
    pub qty_usd: Option<f64>,       // USD amount when applicable
    pub notional_usd: f64,          // always populated (derived)
}
```

### Canonical unit rules

| `instrument_kind`               | Canonical field | `notional_usd` derivation     |
|----------------------------------|-----------------|-------------------------------|
| `option` / `linear_future`       | `qty_coin`      | `qty_coin * index_price`      |
| `perpetual` / `inverse_future`   | `qty_usd`       | `qty_usd` (already USD)       |

- Linear perpetuals (USDC-margined) are treated as `linear_future`.
- For `instrument_kind == option`, `qty_usd` MUST be unset.

### Contracts/amount consistency

- If both `contracts` and canonical amount are provided, they MUST match within tolerance.
- Tolerance: `contracts_amount_match_tolerance = 0.001` (0.1%).
- Formula: `abs(amount - contracts * contract_multiplier) / max(abs(amount), epsilon) <= 0.001` where `epsilon = 1e-9`.
- On mismatch: reject intent with `Rejected(ContractsAmountMismatch)` and set `RiskState::Degraded`.

### Derivation rules

- `option | linear_future`: derive `contracts` from `qty_coin` if contract multiplier is defined.
- `perpetual | inverse_future`: derive `contracts = round(qty_usd / contract_size_usd)` if defined; derive `qty_coin = qty_usd / index_price`.

### Acceptance tests

- **AT-277**: option uses `amount=qty_coin`, perp uses `amount=qty_usd`; option `qty_usd` unset; mismatches rejected.
- **AT-920**: contracts/amount mismatch beyond tolerance → `Rejected(ContractsAmountMismatch)`, dispatch count 0, `RiskState::Degraded`.

## Gaps vs contract (from clean slate)

Everything is a gap — full implementation needed:

1. `OrderSize` struct with all 4 fields
2. Constructor that selects canonical unit by `InstrumentKind`
3. `notional_usd` derivation (coin * index_price or passthrough)
4. `contracts` derivation from canonical amount + multiplier
5. Contracts/amount consistency check with tolerance `0.001`
6. Mismatch rejection with `Rejected(ContractsAmountMismatch)` reason code
7. `RiskState::Degraded` transition on mismatch
8. Observability: `debug log OrderSizeComputed{instrument_kind, notional_usd}` (per IMPLEMENTATION_PLAN)
9. Option constraint: `qty_usd` must be `None` for options

## Required tests (for S1-004)

| Test | What it proves |
|------|---------------|
| `test_option_canonical_qty_coin` | Option uses `qty_coin`, `notional_usd = qty_coin * index`, `qty_usd` unset |
| `test_perp_canonical_qty_usd` | Perp uses `qty_usd`, `notional_usd = qty_usd`, derives `qty_coin` |
| `test_linear_future_canonical_qty_coin` | Linear future uses `qty_coin` like options |
| `test_inverse_future_canonical_qty_usd` | Inverse future uses `qty_usd` like perps |
| `test_contracts_derived_from_canonical` | `contracts` correctly derived when multiplier provided |
| `test_contracts_amount_mismatch_rejected` | Mismatch beyond 0.001 tolerance → rejection + Degraded |
| `test_contracts_amount_within_tolerance` | Match within 0.001 tolerance → accepted |
| `test_option_qty_usd_must_be_unset` | Options with `qty_usd` set → rejected |
| `test_missing_canonical_amount_rejected` | Missing required canonical field → deterministic error (no panic) |

Required test alias (per IMPLEMENTATION_PLAN):
- `test_atomic_qty_epsilon_tolerates_float_noise_but_rejects_mismatch()`

## Minimal implementation diff (for S1-004)

**File:** `crates/soldier_core/src/execution/order_size.rs`

1. Define `OrderSize` struct (4 fields as above)
2. Import `InstrumentKind` from S1-002 (`crates/soldier_core/src/venue/types.rs`) — do NOT redefine
3. Implement `OrderSize::new(kind, qty_coin, qty_usd, contracts, index_price, contract_multiplier) -> Result<OrderSize, OrderSizeError>`
   - Select canonical field by kind
   - Compute `notional_usd`
   - Derive `contracts` if multiplier available
   - Validate contracts/amount consistency if both present
   - Return error (not panic) on invalid inputs
4. Define `OrderSizeError` enum with `ContractsAmountMismatch`, `MissingCanonicalAmount`, `InvalidIndexPrice`
5. Add `tracing::debug!` for `OrderSizeComputed`
6. Wire into `crates/soldier_core/src/execution/mod.rs` re-export

**Test file:** `crates/soldier_core/tests/test_order_size.rs` (9 tests listed above)

**Dependencies:** `InstrumentKind` may also be needed by S1-011 (Deribit instrument structs) — coordinate to avoid duplication. S1-002 defines `InstrumentKind` and `RiskState`, so S1-004 depends on both S1-002 and S1-008.
