# S1-005 Reconciliation: R1 Preflight Audit

> **Story**: S1-005 — S1.3 Dispatcher amount mapping
> **Enforcement Point**: DispatcherChokepoint
> **Enforcing Contract ATs**: AT-277
> **Auditor**: Claude Opus 4.6 (R1 reconciliation)
> **Date**: 2026-02-23
> **Mode**: READ-ONLY preflight audit

---

## A) GATE RESULT

**GATE: CONDITIONAL PASS** — AT-277 enforcement is structurally sound for the S1-005 scope (dispatch mapping).

**R5 remediation update (2026-02-24):**
- `GAP-S1-005-001` FIXED: integration-test compile path is restored via `test-helpers` feature wiring in `crates/soldier_core/Cargo.toml:15` and `crates/soldier_core/Cargo.toml:18` (prior fix commit `efecb6c`).
- `GAP-S1-005-002` FIXED: explicit negative amount TRIP regression added at `crates/soldier_core/tests/test_dispatch_map.rs:753` (`test_dispatch_map_negative_amount_returns_err`).
- Guard causality remains anchored at `crates/soldier_core/src/execution/dispatch_map.rs:209` (`amount <= 0.0` -> `InvalidAmount`).

---

## B) AT AUDIT TABLE

### AT-277: Dispatcher mapping validates option sizing and amount field

| Dimension | Evidence | Verdict |
|-----------|----------|---------|
| **Enforcement point** | `dispatch_map.rs:199-206` (`map_to_dispatch_unchecked`) — match on `InstrumentKind` selects `qty_coin` for `Option\|LinearFuture`, `qty_usd` for `Perpetual\|InverseFuture` | LOCATED |
| **File:line:function** | `/Users/admin/Desktop/opus-trader/crates/soldier_core/src/execution/dispatch_map.rs:194-222::map_to_dispatch_unchecked` | -- |
| **Fail-closed (missing qty_coin)** | Line 201-202: `.ok_or(DispatchMapError::MissingQtyCoin)?` — coin-sized instrument without qty_coin returns error | VERIFIED |
| **Fail-closed (missing qty_usd)** | Line 204: `.ok_or(DispatchMapError::MissingQtyUsd)?` — USD-sized instrument without qty_usd returns error | VERIFIED |
| **Fail-closed (NaN/Inf/zero/neg)** | Line 209: `if !amount.is_finite() \|\| amount <= 0.0` → `Err(InvalidAmount)` | VERIFIED |
| **Fail-closed (contracts present)** | Line 187-189: `if order_size.contracts.is_some()` → `Err(ContractsRequireValidation)` — forces callers through `validate_and_dispatch` | VERIFIED |
| **Fail-closed (reduce_only default)** | Line 213-215: `IntentClass::Open => false`, `Close\|Hedge\|Cancel => true` — exhaustive match, no wildcard | VERIFIED |
| **Fail-closed (intent class unknown)** | `IntentClass` is a 4-variant enum (`Open, Close, Hedge, Cancel`) with exhaustive match — compiler enforces coverage | VERIFIED |
| **Causal proof (option -> qty_coin)** | `test_option_amount_is_qty_coin` (test_dispatch_map.rs:18-32): asserts `req.amount == 0.3` for `InstrumentKind::Option` | **PROVEN** |
| **Causal proof (linear_future -> qty_coin)** | `test_linear_future_amount_is_qty_coin` (test_dispatch_map.rs:36-50): asserts `req.amount == 2.0` for `LinearFuture` | **PROVEN** |
| **Causal proof (perpetual -> qty_usd)** | `test_perpetual_amount_is_qty_usd` (test_dispatch_map.rs:54-68): asserts `req.amount == 30_000.0` for `Perpetual` | **PROVEN** |
| **Causal proof (inverse_future -> qty_usd)** | `test_inverse_future_amount_is_qty_usd` (test_dispatch_map.rs:72-86): asserts `req.amount == 10_000.0` for `InverseFuture` | **PROVEN** |
| **Causal proof (exactly one field)** | `test_option_only_one_amount_field` (test_dispatch_map.rs:92-108): asserts `qty_coin.is_some()` and `qty_usd.is_none()` for Option | **PROVEN** |
| **Causal proof (missing coin -> error)** | `test_missing_qty_coin_error` (test_dispatch_map.rs:112-123): asserts `Err(MissingQtyCoin)` | **PROVEN** |
| **Causal proof (missing usd -> error)** | `test_missing_qty_usd_error` (test_dispatch_map.rs:127-138): asserts `Err(MissingQtyUsd)` | **PROVEN** |
| **Causal proof (contracts -> require validation)** | `test_map_to_dispatch_rejects_contracts_without_validation` (test_dispatch_map.rs:143-153): asserts `Err(ContractsRequireValidation)` | **PROVEN** |
| **Causal proof (reduce_only table)** | `test_intent_class_reduce_only_table` (test_dispatch_map.rs:219-241): table-driven, covers all 4 IntentClass variants | **PROVEN** |
| **Causal proof (NaN amount)** | `test_dispatch_map_nan_amount_returns_err` (test_dispatch_map.rs:729-738): asserts `Err(InvalidAmount)` | **PROVEN** |
| **Causal proof (zero amount)** | `test_dispatch_map_zero_amount_returns_err` (test_dispatch_map.rs:742-751): asserts `Err(InvalidAmount)` | **PROVEN** |
| **AT-277 contract roundtrip (option)** | `test_at277_option_dispatch_roundtrip` (test_dispatch_map.rs:247-261): option qty_coin=0.3 -> amount=0.3, qty_usd=None | **PROVEN** |
| **AT-277 contract roundtrip (perpetual)** | `test_at277_perpetual_dispatch_roundtrip` (test_dispatch_map.rs:265-282): perp qty_usd=30_000 -> amount=30_000 | **PROVEN** |

**Summary**: AT-277 enforcement is **PROVEN** across all 6 fail-closed categories. 32 tests pass (with `--features test-helpers`). Causal proof is demonstrated via dispatch count (error return = no dispatch), specific error variants, and amount-field value assertions.

---

## C) PREMORTEM CROSS-REFERENCE

### C.1 -- Section 2: Assumptions

| # | Assumption | Premortem Status | Audit Finding |
|---|-----------|------------------|---------------|
| 1 | OrderSize from S1-004 always has the correct canonical field populated | Pending | **VALIDATED** — `build_order_size()` in `order_size.rs:88-164` enforces field population per instrument_kind. Tests in `test_order_size.rs` verify. `dispatch_map.rs` also defends with `MissingQtyCoin`/`MissingQtyUsd` errors (defense-in-depth). |
| 2 | Deribit API accepts exactly one of amount/contracts, not both | Killed (premortem) | **CONFIRMED KILLED** — External API constraint, not testable in unit tests. Premortem correctly killed this assumption. |
| 3 | Intent classification (OPEN/CLOSE/HEDGE) is available at dispatch time | Pending | **VALIDATED** — `IntentClass` is a required parameter to `map_to_dispatch()` (dispatch_map.rs:183). The `intent_assembly.rs:86-93` `choke_intent_to_dispatch` function maps from `ChokeIntentClass` to `IntentClass` with exhaustive match. |
| 4 | Linear perpetuals (USDC-margined) use qty_coin like linear_future | Pending | **VALIDATED** — `InstrumentKind::LinearFuture` is the classification for USDC-margined perpetuals (venue/types.rs:14,20-21). `dispatch_map.rs:200` matches `LinearFuture` to `qty_coin`. Test `test_linear_future_amount_is_qty_coin` proves this. |

### C.2 -- Section 4: Decisions

| Decision | Chosen | Audit Finding |
|----------|--------|---------------|
| Outbound request representation | Option A — Single `amount: f64` field | **IMPLEMENTED AS CHOSEN** — `DispatchRequest` (dispatch_map.rs:44-52) has a single `amount: f64` field, matching Deribit API shape. No dual `qty_coin`/`qty_usd` optional fields. |
| reduce_only for unknown intent classification | Option A — Treat unknown as OPEN, reduce_only=false | **IMPLEMENTED AS CHOSEN** — `IntentClass` is a closed enum with exhaustive match (dispatch_map.rs:213-216). No unknown/default arm exists; the compiler enforces all variants are handled. The OPEN variant maps to `reduce_only=false`. |

### C.3 -- Section 5: Wrong Implementation Gate

| Wrong Impl | Tightening | Audit Finding |
|------------|-----------|---------------|
| Always send amount=qty_coin regardless of instrument_kind | Golden vector: perpetual must produce amount=30_000 | **BLOCKED** — `test_perpetual_amount_is_qty_usd` (line 54-68) and `test_at277_perpetual_dispatch_roundtrip` (line 265-282) assert perpetual uses qty_usd=30_000. The wrong impl would fail these tests. |
| Set reduce_only=true for ALL intents | Golden vector: OPEN must produce reduce_only=false | **BLOCKED** — `test_open_intent_not_reduce_only` (line 159-170) and `test_intent_class_reduce_only_table` (line 219-241) assert OPEN maps to reduce_only=false. |
| Send both amount fields | Negative test: exactly one field set | **BLOCKED** — `test_option_only_one_amount_field` (line 92-108) asserts qty_usd is None for options. `DispatchRequest` struct only has one `amount` field (Decision A), making it structurally impossible to send both. |
| Map reduce_only correctly but forget amount > 0 validation | Golden vector: amount=0 rejected | **BLOCKED** — `test_dispatch_map_zero_amount_returns_err` (line 742-751) asserts zero amount is rejected. NaN is also covered (line 729-738). |

---

## D) DESIGN RISK NOTES

### D.1 -- No tracing/logging on reject paths in dispatch_map.rs

The `map_to_dispatch()` and `map_to_dispatch_unchecked()` functions return `Result::Err` on failures (MissingQtyCoin, MissingQtyUsd, InvalidAmount, ContractsRequireValidation) but emit **zero** `tracing::` calls. In production, these rejections would be silent at the dispatch_map level. The observability relies entirely on callers (e.g., `intent_assembly.rs:232` has `tracing::warn!` for assembly failures, and `open_runtime.rs` callers log rejections). This is acceptable for a pure-function mapper but means `grep tracing dispatch_map.rs` returns zero results.

**Risk**: LOW. Observability is provided by the caller layer (`intent_assembly.rs`, `open_runtime.rs`). However, the `validate_and_dispatch` path's `MismatchMetrics` counter (`reject_unit_mismatch_total`) provides metric observability specifically for AT-920 rejections.

### D.2 -- validate_and_dispatch has zero production callsites (partially mitigated)

The `dispatch_map.rs:224` TODO says: `// TODO(slice-N): Wire into production dispatch — currently only called from unit tests`. However, `intent_assembly.rs:126` calls `validate_and_dispatch` in `assemble_sizing()`, and `open_runtime.rs:392` documents that `build_open_intent_with_assembly` exercises the full chain. The TODO comment is **stale** -- `validate_and_dispatch` IS wired via `intent_assembly.rs`. This is a documentation debt, not a structural gap.

### D.3 -- Negative amount not tested

The guard at `dispatch_map.rs:209` rejects `amount <= 0.0`, which covers zero and negative values. Tests cover NaN (`test_dispatch_map_nan_amount_returns_err`) and zero (`test_dispatch_map_zero_amount_returns_err`), but there is **no explicit test for negative amounts** (e.g., `qty_coin = Some(-1.0)`). The guard logic covers it, but the test gap means a regression (e.g., changing `<=` to `<`) would not be caught for the negative case specifically.

### D.4 -- Compilation bug: test_at920_mismatch_caller_sets_degraded_and_blocks_open

On committed HEAD (fa2d65d), `test_dispatch_map.rs:715` calls `GateResults::all_passed()` which is gated behind `#[cfg(any(test, feature = "test-helpers"))]`. The `test` cfg is not set on the library crate when compiled for integration tests, and the `test-helpers` feature is not declared in the committed `Cargo.toml`. This causes a compilation failure, meaning **all 32 tests in test_dispatch_map.rs cannot run on committed HEAD**. The working tree adds `[features] test-helpers = []` to Cargo.toml which fixes this, but the committed code is broken.

**Risk**: HIGH. This means CI (if running `cargo test --test test_dispatch_map` without `--features test-helpers`) cannot verify AT-277 enforcement. The fix in the working tree (adding the feature) resolves it.

### D.5 -- DispatchConsistencyProof::unchecked() bypass still exists

`dispatch_map.rs:128` provides `DispatchConsistencyProof::unchecked(passed: bool)` with a `TODO(slice-2)` to eliminate all callsites. `intent_assembly.rs:128` calls `unchecked(false)` on mismatch, which is the correct fail-closed usage. However, the `unchecked` constructor remains available, and any caller could forge a `true` proof without actual validation. The `#[must_use]` attribute and restricted constructor set mitigate misuse but do not prevent it.

---

## E) REMEDIATION PLAN

| # | Finding | Severity | Remediation | Owner |
|---|---------|----------|-------------|-------|
| R1 | **Compilation bug**: committed HEAD cannot compile `test_dispatch_map.rs` (missing `test-helpers` feature in Cargo.toml) | **P0** | **FIXED** — `crates/soldier_core/Cargo.toml:15` enables self-referencing dev-dep with `features = ["test-helpers"]`; `crates/soldier_core/Cargo.toml:18` declares feature. Landed in `efecb6c`. | S1-005 recon |
| R2 | **Missing negative amount test**: `dispatch_map.rs:209` rejects `amount <= 0.0` but no test exercises a negative input (e.g., `qty_coin = Some(-1.0)`) | **P1** | **FIXED** — `crates/soldier_core/tests/test_dispatch_map.rs:753` adds `test_dispatch_map_negative_amount_returns_err` (TRIP) and now proves negative-path rejection causally. | S1-005 recon |
| R3 | **Stale TODO comment**: `dispatch_map.rs:224` says `validate_and_dispatch` is only called from unit tests, but `intent_assembly.rs:126` provides a production callsite | **P2** | Remove or update the TODO comment at `dispatch_map.rs:224` | S1-005 recon |
| R4 | **No tracing on reject paths in dispatch_map.rs** | **P3** (info) | Consider adding `tracing::warn!` for `InvalidAmount` and `MissingQty*` errors. Currently delegated to callers; acceptable for a pure-function mapper. | Debt |
| R5 | **DispatchConsistencyProof::unchecked() still exists** | **P3** (tracked) | Already tracked as `TODO(slice-2)`. No change needed for S1-005. | Slice-2 debt |

---

## F) SCOPE CHECK

### F.1 -- scope.touch verification

| File | In scope.touch | Exists | Audited |
|------|---------------|--------|---------|
| `crates/soldier_core/src/execution/dispatch_map.rs` | Yes | Yes | Yes -- 285 lines, full audit above |
| `crates/soldier_core/src/execution/mod.rs` | Yes | Yes | Yes -- re-exports `dispatch_map` types at lines 61-63 |
| `crates/soldier_core/src/lib.rs` | Yes | Yes | Yes -- declares `pub mod execution` at line 3 |
| `crates/soldier_core/tests/test_dispatch_map.rs` | Yes | Yes | Yes -- 32 tests, all pass with `--features test-helpers` |

### F.2 -- scope.avoid verification

| Pattern | Violation Check |
|---------|----------------|
| `crates/soldier_core/src/risk/**` | `dispatch_map.rs` imports `crate::risk::RiskState` (line 15) but does not modify any risk module files. `RiskState` is used read-only in `ValidatedDispatch`. No violation. |
| `crates/soldier_infra/**` | No imports or modifications. No violation. |

### F.3 -- Extra files touched (outside scope.touch)

| File | Relationship | Finding |
|------|-------------|---------|
| `crates/soldier_core/src/execution/order_size.rs` | Dependency (S1-004) | Referenced by `dispatch_map.rs` via `use crate::execution::OrderSize`. Not modified by S1-005. |
| `crates/soldier_core/src/venue/types.rs` | Dependency (S1-002) | Referenced by `dispatch_map.rs` via `use crate::venue::InstrumentKind`. Not modified by S1-005. |
| `crates/soldier_core/src/execution/intent_assembly.rs` | Consumer | Calls `validate_and_dispatch` (line 126). Provides production wiring. Not in S1-005 scope but validates production integration. |

### F.4 -- PRD entry consistency

| Field | prd.json Value | Reality |
|-------|---------------|---------|
| `passes` | `true` | Tests pass (with feature flag fix) |
| `enforcing_contract_ats` | `["AT-277"]` | AT-277 is enforced in dispatch_map.rs via exhaustive match |
| `enforcement_point` | `DispatcherChokepoint` | `map_to_dispatch` is the chokepoint for amount mapping |
| `implementation_tests` | `["crates/soldier_core/tests/test_dispatch_map.rs"]` | Correct -- 32 tests |
| `reason_codes.values` | `["TooSmallAfterQuantization"]` | **MISMATCH**: The actual reason codes from `dispatch_map.rs` are `MissingQtyCoin`, `MissingQtyUsd`, `ContractsRequireValidation`, `InvalidAmount`, `ContractsAmountMismatch`. `TooSmallAfterQuantization` is from the quantize module, not dispatch_map. This appears to be a prd.json copy-paste error but is non-blocking since the real error types exist in code. |
| `loss_mode.drift_metric` | `"N/A -- mapping correctness, no runtime metric"` | Acceptable for a stateless pure function; MismatchMetrics provides AT-920 counter when contracts are involved. |

---

## Appendix: Git Status (end of audit)

```
Working tree has modifications including Cargo.toml (test-helpers feature),
dispatch_map.rs (ValidatedDispatch field privacy), test_dispatch_map.rs (accessor changes).
These are working-tree-only changes; committed HEAD has the compilation bug (R1).
```

---

**READY FOR SELF_REVIEW**
