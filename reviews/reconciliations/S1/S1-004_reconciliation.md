# R1 Preflight Reconciliation: S1-004

**Story**: S1-004 — S1.2 OrderSize canonical sizing
**Enforcement Point**: DispatcherChokepoint
**Enforcing Contract ATs**: AT-277
**Auditor Mode**: READ-ONLY
**Date**: 2026-02-23

---

## A) GATE RESULT

**PASS** -- all enforcement points located, fail-closed behavior verified across the 6 categories for the core builder, causal proof is PROVEN for AT-277, and no contract misalignment found. Minor remediation items identified (test coverage gaps for Inf/negative on certain inputs; missing observability metric counter).

---

## B) AT AUDIT TABLE

### AT-277: Dispatcher mapping validates option sizing and qty_usd unset

| Dimension | Finding | Status |
|-----------|---------|--------|
| **Enforcement point** | `build_order_size()` at `crates/soldier_core/src/execution/order_size.rs:88-164` | LOCATED |
| **File:line::function** | `order_size.rs:88::build_order_size` | Confirmed |
| **Premortem §6 cross-ref** | §6 claims enforcement at `OrderSize (execution::order_size)` | MATCH |

#### Fail-closed verification (6 categories):

| Category | Input field(s) | Code guard | Test coverage | Verdict |
|----------|---------------|------------|---------------|---------|
| **Missing/None** | `contract_multiplier: None` | Lines 113,121 / 145,153: `match input.contract_multiplier { None => None }` -- gracefully produces `contracts: None` | `test_no_multiplier_no_contracts` (line 167) | COVERED |
| **NaN** | `index_price: NaN` | Line 90: `!input.index_price.is_finite()` rejects NaN | `test_nan_index_price_rejected` (line 212) | COVERED |
| **NaN** | `canonical_qty: NaN` | Line 93: `!input.canonical_qty.is_finite()` rejects NaN | Not directly tested (NaN canonical_qty) but covered by `is_finite()` check. Assembly-level test `test_assembly_nan_qty_fails_closed` (test_intent_assembly.rs:49) tests through pipeline | WEAK -- no unit-level NaN canonical_qty test |
| **NaN/Inf** | Output `notional_usd` | Line 109: `!notional_usd.is_finite()` | `test_order_size_nan_notional_returns_err` (line 259) | COVERED |
| **Inf** | `index_price: Inf` | Line 90: `!input.index_price.is_finite()` rejects Inf | Not directly tested with `f64::INFINITY` | WEAK -- code handles it but no dedicated test |
| **Inf** | `canonical_qty: Inf` | Line 93: `!input.canonical_qty.is_finite()` rejects Inf | Not directly tested with `f64::INFINITY` | WEAK -- code handles it but no dedicated test |
| **Negative** | `index_price < 0` | Line 90: `input.index_price <= 0.0` | `test_negative_index_price_rejected` (line 197) | COVERED |
| **Negative** | `canonical_qty < 0` | Line 93: `input.canonical_qty <= 0.0` | Not directly tested (negative canonical_qty) | WEAK -- code handles it but no dedicated test |
| **Zero** | `index_price = 0` | Line 90: `input.index_price <= 0.0` | `test_zero_index_price_rejected` (line 182) | COVERED |
| **Zero** | `canonical_qty = 0` | Line 93: `input.canonical_qty <= 0.0` | `test_zero_canonical_qty_rejected` (line 227) | COVERED |
| **Out-of-domain** | `contract_multiplier = 0.0` | Lines 96-100: `!mult.is_finite() \|\| mult <= 0.0` | `test_invalid_contract_multiplier_rejected` (line 242) -- tests 0.0 | COVERED (0.0 only) |
| **Out-of-domain** | `contract_multiplier: NaN/Inf/negative` | Lines 96-100: same guard handles all non-finite/non-positive | No tests for NaN/Inf/negative multiplier specifically | WEAK -- code handles it but tests only cover 0.0 |
| **Narrowing cast** | `contracts: f64 -> i64` | Lines 116-118 / 148-150: overflow check `rounded > i64::MAX as f64 \|\| rounded < i64::MIN as f64` | `test_order_size_overflow_contracts_returns_err` (line 276) | COVERED |
| **Corrupt** | Not applicable -- all inputs are typed f64/enum, no parsing from strings/bytes | N/A | N/A | N/A |

#### Causal proof (AT-277 specifics):

| AT-277 clause | Proving test | Proof type | Verdict |
|---------------|-------------|------------|---------|
| Option uses `qty_coin=0.3`, `notional_usd=30_000`, `qty_usd` unset | `test_at277_option_sizing` (line 17) | Field value equality: `qty_coin==Some(0.3)`, `qty_usd==None`, `notional_usd==30_000` | **PROVEN** |
| Perp uses `qty_usd=30_000`, `qty_coin=0.3`, `notional_usd=30_000` | `test_at277_perpetual_sizing` (line 34) | Field value equality: `qty_usd==Some(30_000)`, `qty_coin.unwrap()==0.3`, `notional_usd==30_000` | **PROVEN** |
| Contracts/amount mismatch -> reject + degrade | Enforced by `validate_and_dispatch` in dispatch_map.rs (S1-005 scope), tested by `test_assembly_mismatch_sets_degraded` (test_intent_assembly.rs:98) | Assembly pipeline proof | **PROVEN** (cross-story) |
| Option `qty_usd` MUST be unset | `test_at277_option_sizing` (line 27): `assert_eq!(size.qty_usd, None)` | Direct assertion | **PROVEN** |

**Overall AT-277 verdict**: **PROVEN**

---

## C) PREMORTEM CROSS-REFERENCE

### C.1) Section 2 -- Assumptions

| # | Assumption | Implementation evidence | Test evidence | Verdict |
|---|-----------|------------------------|---------------|---------|
| 1 | `index_price` always > 0 | `order_size.rs:90`: `!input.index_price.is_finite() \|\| input.index_price <= 0.0` returns `Err(InvalidIndexPrice)` | `test_zero_index_price_rejected` (line 182), `test_negative_index_price_rejected` (line 197), `test_nan_index_price_rejected` (line 212) | VALIDATED |
| 2 | USDC-margined linear perps classified as `LinearFuture` | `venue/types.rs:71-74`: `is_linear => LinearFuture` regardless of `is_perpetual` flag | Tested in S1-002 scope (`test_instrument_kind.rs`). `test_linear_future_canonical_is_qty_coin` (test_order_size.rs:67) validates sizing given `LinearFuture` input | VALIDATED |
| 3 | `qty_coin` and `qty_usd` mutually exclusive for canonical | `order_size.rs:127-131`: Option/LinearFuture branch sets `qty_usd: None`. `order_size.rs:156-161`: Perpetual/InverseFuture branch sets both `qty_usd: Some()` and `qty_coin: Some()` (derived) | `test_at277_option_sizing` asserts `qty_usd==None`. `test_at277_perpetual_sizing` asserts `qty_usd==Some(30_000)`. `test_option_canonical_is_qty_coin` asserts `qty_usd==None` | VALIDATED |

### C.2) Section 4 -- Decisions

| Decision | Chosen option | Implementation evidence | Verdict |
|----------|--------------|------------------------|---------|
| Constructor API shape: Option A (function taking instrument_kind, qty, index_price) | A -- single function | `build_order_size(input: &OrderSizeInput)` at order_size.rs:88. `OrderSizeInput` has `instrument_kind`, `canonical_qty`, `index_price`, `contract_multiplier`. No builder pattern. | IMPLEMENTED AS CHOSEN |
| Invalid index_price: Option A (return error, fail-closed) | A -- Result<OrderSize, OrderSizeError> | `order_size.rs:90-91`: returns `Err(InvalidIndexPrice)`. Not fail-open (no fallback to 0.0 or default). | IMPLEMENTED AS CHOSEN |

### C.3) Section 5 -- Wrong implementation gate

| Wrong impl | Blocking test | Blocked? |
|-----------|--------------|----------|
| Hardcode `notional_usd=30_000` for `qty_coin=0.3` | `test_option_canonical_is_qty_coin` (line 52): uses `qty=1.5`, `price=50_000`, expects `notional=75_000`. `test_notional_usd_always_populated` (line 114): table-driven with 4 different (qty, price, expected) tuples | **BLOCKED** -- multiple price points prevent hardcoding |
| Set `qty_usd=None` for ALL kinds | `test_at277_perpetual_sizing` (line 34): asserts `qty_usd==Some(30_000)`. `test_perpetual_canonical_is_qty_usd` (line 82): asserts `qty_usd==Some(50_000)` | **BLOCKED** |
| Swap `qty_coin`/`qty_usd` fields | `test_at277_option_sizing` (line 17): asserts `qty_coin==Some(0.3)` and `qty_usd==None`. `test_at277_perpetual_sizing` (line 34): asserts `qty_usd==Some(30_000)` and `qty_coin.unwrap()==0.3` | **BLOCKED** |
| Use `mark_price` instead of `index_price` | The API requires `index_price` as explicit input; there is no `mark_price` field on `OrderSizeInput`. The struct design prevents this by construction. | **BLOCKED** (by type design) |

---

## D) DESIGN RISK NOTES

### D.1) No observability on reject/degrade paths within `build_order_size`

The function `build_order_size()` at `order_size.rs:88` returns `Result<OrderSize, OrderSizeError>` but contains **zero** `tracing::` calls. When an error occurs, there is no log emission at the point of failure. Observability is deferred to callers:

- `intent_assembly.rs:122`: `map_err(|e| AssemblySizingError::InvalidOrderSize(format!("{e:?}")))` -- formats the error into a string, but the `tracing::warn!` only fires at lines 206/232, at the assembly level, not the order-size level.

**Risk**: Low. The assembly layer does log, so production errors are visible. But the lack of structured tracing fields (instrument_kind, canonical_qty, index_price) at the rejection point makes root-cause debugging harder.

### D.2) Missing `order_size_computed_total` metric

The PRD (`plans/prd.json` lines 911-915) declares an observability metric `order_size_computed_total` (counter). A grep of the entire `soldier_core` crate shows **zero** references to this metric name. It is not implemented anywhere.

The premortem section 7 also references `order_size_computed_total` as a drift metric.

**Risk**: Low-medium. The metric was specified for drift detection (if mismatches spike, sizing is broken). Without it, the only signal is downstream `order_intent_reject_unit_mismatch_total` (if that exists).

### D.3) `TooSmallAfterQuantization` reason code in PRD entry may be misattributed

The PRD entry for S1-004 (`plans/prd.json:901-905`) lists `reason_codes.values: ["TooSmallAfterQuantization"]`. This reject reason is defined in `quantize.rs` and `reject_reason.rs` and belongs to the quantization gate, not OrderSize construction. S1-004's own error enum is `OrderSizeError` (InvalidIndexPrice, InvalidCanonicalQty, InvalidContractMultiplier, InvalidNotional, ContractsOverflow). The `TooSmallAfterQuantization` is from the downstream quantizer (S1-009 scope).

**Risk**: Metadata inaccuracy only. No production impact, but could confuse future auditors.

### D.4) `OrderSizeError` lacks `Display` impl

`OrderSizeError` at `order_size.rs:62` only derives `Debug`, not `Display`. When formatted via `format!("{e:?}")` in `intent_assembly.rs:122`, the output is Rust debug format, not human-friendly. This is a minor observability quality issue.

### D.5) `TODO(slice-N)` comment still present

`order_size.rs:75`: `// TODO(slice-N): Wire into production dispatch -- currently only called from unit tests`. However, `build_order_size` IS wired into production via:
- `intent_assembly.rs:121`: `let order_size = build_order_size(&osi)`
- `open_runtime.rs:408`: `assemble_sizing(...)` which calls `build_order_size`

The TODO comment is stale and should be removed.

---

## E) REMEDIATION PLAN

| # | Finding | Severity | Category | Remediation |
|---|---------|----------|----------|-------------|
| R1 | Missing test: `canonical_qty = f64::NAN` | P2 | Test gap | Add `test_nan_canonical_qty_rejected` asserting `Err(InvalidCanonicalQty(_))` |
| R2 | Missing test: `canonical_qty = f64::INFINITY` | P2 | Test gap | Add `test_inf_canonical_qty_rejected` asserting `Err(InvalidCanonicalQty(_))` |
| R3 | Missing test: `canonical_qty = -1.0` (negative) | P2 | Test gap | Add `test_negative_canonical_qty_rejected` asserting `Err(InvalidCanonicalQty(-1.0))` |
| R4 | Missing test: `index_price = f64::INFINITY` | P2 | Test gap | Add `test_inf_index_price_rejected` asserting `Err(InvalidIndexPrice(_))` |
| R5 | Missing test: `contract_multiplier = NaN/Inf/negative` | P3 | Test gap | Add tests for `Some(f64::NAN)`, `Some(f64::INFINITY)`, `Some(-1.0)` all asserting `Err(InvalidContractMultiplier(_))` |
| R6 | Missing `order_size_computed_total` metric | P2 | Observability | Emit counter in `build_order_size` success path (or in `assemble_sizing` after successful build) |
| R7 | No tracing in `build_order_size` error paths | P3 | Observability | Add `tracing::warn!` with structured fields on each error return |
| R8 | Stale `TODO(slice-N)` comment at `order_size.rs:75` | P3 | Code hygiene | Remove or update comment -- function IS wired via `intent_assembly.rs:121` |
| R9 | PRD `reason_codes` lists `TooSmallAfterQuantization` -- belongs to quantizer, not OrderSize | P3 | Metadata | Update `plans/prd.json` S1-004 entry to list correct reason codes (InvalidIndexPrice, InvalidCanonicalQty, etc.) or leave empty if order-size errors are surfaced as `AssemblyFailed` |
| R10 | `OrderSizeError` missing `Display` impl | P3 | Observability | Add `impl Display for OrderSizeError` for better log readability |

**No P0 or P1 findings.**

All R1-R5 (test gaps) are for code paths that ARE correctly guarded by the `is_finite() || <= 0.0` checks. The code is fail-closed. The tests simply do not exercise every specific variant of bad input.

---

## F) SCOPE CHECK

### Files in scope.touch vs actual implementation:

| File | PRD scope.touch | Actually modified | Status |
|------|----------------|-------------------|--------|
| `crates/soldier_core/src/execution/order_size.rs` | Yes | Yes (165 lines, full implementation) | OK |
| `crates/soldier_core/src/execution/mod.rs` | Yes | Yes (line 40: `pub mod order_size;`, line 97: re-exports) | OK |
| `crates/soldier_core/src/lib.rs` | Yes | Yes (line 3: `pub mod execution;` -- provides path to order_size) | OK |
| `crates/soldier_core/tests/test_order_size.rs` | Yes | Yes (290 lines, 17 tests, all passing) | OK |

### Out-of-scope modifications: None detected for this story.

### Integration wiring (outside scope.touch but valid):

| File | Relationship |
|------|-------------|
| `crates/soldier_core/src/execution/intent_assembly.rs` | Calls `build_order_size` at line 121. This is the production integration path (S1-010 scope). |
| `crates/soldier_core/src/execution/open_runtime.rs` | Calls `assemble_sizing` at line 408, which calls `build_order_size`. Production entry point. |

### Test run verification:
```
cargo test -p soldier_core --test test_order_size
17 passed; 0 failed; 0 ignored
```

### Contract alignment summary:

| CONTRACT.md clause | Implementation | Aligned? |
|-------------------|----------------|----------|
| OrderSize struct: contracts, qty_coin, qty_usd, notional_usd | `order_size.rs:28-38` -- all 4 fields present with correct types | YES |
| option/linear_future: canonical = qty_coin | `order_size.rs:103-132` -- match arm sets `qty_coin: Some(qty_coin)`, `qty_usd: None` | YES |
| perpetual/inverse_future: canonical = qty_usd | `order_size.rs:134-162` -- match arm sets `qty_usd: Some(qty_usd)`, `qty_coin: Some(derived)` | YES |
| notional_usd = qty_coin * index_price (coin) or qty_usd (USD) | `order_size.rs:106` and `order_size.rs:137` | YES |
| Option qty_usd MUST be unset (AT-277) | `order_size.rs:124-130` -- explicit `qty_usd: None` with AT-277 comment | YES |
| Deribit outbound: option sends `amount=qty_coin` | Enforced by `dispatch_map.rs` (S1-005 scope), not S1-004 | N/A (cross-story) |

---

## Git status at end of audit:

Verified: only this reconciliation file was created. No source code modifications.

---

READY FOR SELF_REVIEW
