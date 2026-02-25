# Story Premortem: S1-002

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-002 —Implement InstrumentKind derivation and RiskState enum per contract definitions
- Contract clause(s): §1.0 Instrument Units & Notional Invariants
- Acceptance tests: AT-333
- Touch scope: `crates/soldier_core/src/venue/mod.rs`, `crates/soldier_core/src/venue/types.rs`, `crates/soldier_core/src/risk/state.rs`, `crates/soldier_core/src/risk/mod.rs`, `crates/soldier_core/src/lib.rs`, `crates/soldier_core/tests/test_instrument_kind_mapping.rs`
- **Risk rating**: LOW
  - Pure enum definitions and mapping logic. No risk gates, no order flow, no financial transactions.

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-333 | §1.0 Instrument Units & Notional Invariants | "instrument metadata is fetched from `/public/get_instruments`... quantization/sizing uses `tick_size`, `amount_step`, `min_amount`, and `contract_multiplier`... values come from fetched metadata (no hardcoded defaults)" | MUST | Yes —verify InstrumentKind derived from fetched metadata `kind` field |
| AT-333 | §1.0 Definitions | "instrument_kind: one of `option | linear_future | inverse_future | perpetual` (derived from venue metadata). Linear Perpetuals (USDC-margined): treat as `linear_future` for sizing" | MUST | Yes —test mapping from Deribit `kind` to contract enum |
| (implicit) | §1.0 Definitions | "RiskState (health/cause layer): `Healthy | Degraded | Maintenance | Kill`" | MUST | Yes —verify enum variants exist |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Deribit `kind` field values are `option`, `future`, `option_combo` (not `perpetual`, `linear_future`, etc.) | If Deribit uses different values, mapping produces wrong InstrumentKind | Table-driven test mapping Deribit `kind` + settlement/margin fields to InstrumentKind | Pending |
| 2 | USDC-margined perpetuals have detectable metadata distinguishing them from regular futures | If no metadata flag differentiates them, mapping to `linear_future` is guesswork | Test with fixture for USDC-margined perpetual, assert `linear_future` | Pending |
| 3 | S1-011 struct includes `kind` field accessible to this conversion logic | If S1-011 omits `kind`, conversion cannot derive InstrumentKind | Compile-time check: conversion function takes S1-011 struct as input | Pending |
| 4 | RiskState enum requires exactly 4 variants: Healthy, Degraded, Maintenance, Kill | CONTRACT.md defines these 4; adding/removing variants breaks downstream state machines | Compile test: exhaustive match on RiskState covers exactly 4 variants | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | USDC-margined perpetual mapped to `perpetual` instead of `linear_future` | Wrong canonical sizing (qty_usd instead of qty_coin), wrong exposure calculation | Test with USDC-margined perp fixture asserting `linear_future` | AT-333 |
| 2 | Unknown Deribit `kind` value silently defaults to an arbitrary InstrumentKind | Wrong sizing for new instrument types Deribit adds | Return `Err` or map to most-restrictive kind on unknown input; test unknown kind | AT-333 |
| 3 | RiskState missing a variant (e.g. `Maintenance` omitted) | Downstream code cannot represent intermediate health states | Exhaustive match test on RiskState | Implicit (contract definition) |
| 4 | Metadata fields (tick_size etc.) passed through incorrectly from S1-011 struct | Wrong quantization downstream | test_instrument_metadata_uses_get_instruments asserts passthrough | AT-333 |
| 5 | InstrumentKind enum uses wrong string serialization (e.g. `LinearFuture` instead of `linear_future`) | Serialization mismatch with contract-defined values | serde roundtrip test asserting snake_case serialization | AT-333 |

## 4) Open decisions (resolve before coding)

### Decision: How to distinguish perpetual vs linear_future vs inverse_future
- **What is ambiguous / missing**: Deribit API returns `kind: "future"` for all futures. The contract requires distinguishing `perpetual`, `linear_future`, and `inverse_future`. The mapping logic needs additional metadata.
- **Evidence**: CONTRACT.md: "Linear Perpetuals (USDC-margined): treat as `linear_future` for sizing (canonical `qty_coin`), even if their venue symbol says PERPETUAL." Deribit API: `kind` is `option` or `future`; settlement currency and instrument name pattern differentiate subtypes.
- **Options**:
  1. Option A —Use `settlement_currency` + `is_perpetual` (or instrument name pattern) to disambiguate: BTC-settled futures = `inverse_future`, USDC-settled perpetuals = `linear_future` (treated as), named perpetuals = `perpetual`.
  2. Option B —Use only instrument name pattern matching (e.g. contains "PERPETUAL").
- **Chosen**: A —use settlement_currency + instrument metadata for robust disambiguation.
- **Why not others**: B is fragile and relies on naming conventions that could change.
- **Scope control**:
  - What we're NOT doing yet: `option_combo` handling, exotic instrument types.
  - What unblocks us if this choice is wrong: mapping is centralized in one conversion function; easy to fix.

### Decision: Fail behavior for unknown instrument kind
- **What is ambiguous / missing**: What happens if Deribit returns a `kind` value we don't recognize?
- **Evidence**: CONTRACT.md does not specify behavior for unknown instrument kinds.
- **Options**:
  1. Option A —Return an error, blocking the instrument from being cached.
  2. Option B —Map to the most restrictive kind (e.g. treat as inverse_future for conservative sizing).
- **Chosen**: A —return an error. Unknown instruments should not be silently accepted.
- **Why not others**: B masks a real problem; an unknown instrument kind means our model is incomplete.
- **Scope control**:
  - What we're NOT doing yet: auto-detection of new instrument types.
  - What unblocks us if this choice is wrong: error is logged and visible; we add the new kind when discovered.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-333 | Hardcode InstrumentKind based on instrument name string matching instead of metadata fields | Passes tests with known instruments but breaks for new instruments or name changes | Golden vector: test with synthetic instrument that has unusual name but correct metadata; assert kind derived from metadata not name |
| AT-333 | Map all futures to `linear_future` regardless of settlement currency | Passes for USDC-margined perps but wrong for BTC-settled inverse futures | Table-driven test: include both USDC-margined perp and BTC-settled inverse future in test cases |
| AT-333 | RiskState enum with only 2 variants (Healthy, Kill) passing basic tests | Passes simple health checks but cannot represent Degraded or Maintenance | Test: construct each of the 4 variants and assert they are distinct; exhaustive match |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-333 | InstrumentKind derivation (venue::types) | test_instrument_kind_mapping (table-driven: Deribit metadata -> InstrumentKind) | Yes (wrong metadata -> error or wrong kind) | Yes (correct metadata -> correct kind) | Exact enum variant comparison per fixture | Yes |
| AT-333 | InstrumentKind derivation (venue::types) | test_instrument_metadata_uses_get_instruments | N/A | Yes (metadata fields pass through) | Field value equality from fixture | Yes |

- [x] Every safety-critical AT has TRIP + NON-TRIP
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: Wrong InstrumentKind leads to wrong canonical sizing (qty_coin vs qty_usd). For example, treating an inverse future as a linear future could cause 10-100x sizing error depending on BTC price. However, this is caught by downstream dispatch guards (contracts/amount mismatch in S1-007).
- **Fail-closed cap on loss**: If InstrumentKind derivation fails (returns error), the instrument is not cached, triggering stale cache -> ReduceOnly (S1-003). If derivation is wrong, S1-007 contracts/amount mismatch rejects the intent.
- **Drift metric**: `instrument_cache_refresh_errors_total` catches derivation failures; `order_intent_reject_unit_mismatch_total` catches wrong-kind sizing downstream.
- **Loss boundary**: ReduceOnly via S1-003 stale cache gate. Downstream mismatch rejection (S1-007) is second line of defense.
- **Rollback plan**: Revert mapping logic; stale cache triggers ReduceOnly, blocking OPENs.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None directly. Defines enums consumed by PolicyGuard (S1-003) and Dispatcher (S1-007).
- **If conflict with CONTRACT.md**: No conflict identified.
- Files with recent churn or shared ownership: `crates/soldier_core/src/venue/` and `crates/soldier_core/src/risk/` are new modules.
- Struct fields I'm assuming exist (verify before coding): S1-011 Deribit instrument struct with `kind`, `tick_size`, `amount_step`, `min_amount`, `contract_multiplier` fields.
- State machine transitions affected: None. RiskState is defined here but state transitions are in S1-003.

## 9) Constraint I expect to hit
- What will slow me down: Determining the exact Deribit metadata fields that distinguish perpetual/linear/inverse futures without live API access.
- Exploit: Use Deribit API documentation and known instrument examples to build comprehensive test fixtures.
- Smallest fix that prevents it next time: Check in a set of real Deribit `/public/get_instruments` response samples as test fixtures.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Assumption #2: USDC-margined perpetual metadata detection is unvalidated without live API data | Medium | Cannot validate without live Deribit API access to inspect USDC-margined perpetual metadata fields | S1-002 owner | Pre-implementation (resolve with real API samples) | Test with real USDC-margined perpetual fixture once API data is available |

- [x] §1 clause audit: every AT traced to normative clause
- [ ] §2 all assumptions validated or killed (Assumption #2 pending: USDC-margined perpetual metadata detection)
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice

Prior Postmortem: NONE
Reused Guardrail: NONE
