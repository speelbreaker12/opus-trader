# Story Premortem: S1-011

> Reference: `specs/DESIGN_PATTERNS.md` (§0 Principles apply to every section below)
> This document replaces both the old premortem and `/slice-preflight`. No production code in this step.

## 0) What we're building
- Story: S1-011 —Define Deribit public instrument structs for metadata mapping
- Contract clause(s): §1.0 Instrument Units & Notional Invariants (AT-333)
- Acceptance tests: AT-333
- Touch scope: `crates/soldier_infra/src/deribit/public/mod.rs`, `crates/soldier_infra/src/deribit/mod.rs`, `crates/soldier_infra/src/lib.rs`, `crates/soldier_infra/Cargo.toml`
- **Risk rating**: LOW
  - Pure data-structure definition (no logic, no side effects, no risk gates).

## 1) Clause audit (contract → AT traceability)

| AT | Contract § | Clause text (abbreviated) | Type (MUST/SHOULD/MAY) | Testable? |
|----|-----------|---------------------------|------------------------|-----------|
| AT-333 | §1.0 Instrument Units & Notional Invariants | "instrument metadata is fetched from `/public/get_instruments`... values come from fetched metadata (no hardcoded defaults)" | MUST | Yes —verify struct includes all required fields and deserializes from API response |

- [x] Every claimed AT traced to a normative clause
- [x] No informational-only ATs counted as enforcement

## 2) Assumptions (each must become a test or get killed)
| # | Assumption | How it breaks | Test that proves it | Validated? |
|---|-----------|---------------|---------------------|------------|
| 1 | Deribit `/public/get_instruments` response includes `kind`, `tick_size`, `amount_step`, `min_trade_amount`, `contract_size` fields | Deribit API changes field names or removes fields | Deserialize a sample API response fixture and assert all fields populated | Pending |
| 2 | `serde(rename)` correctly maps Deribit field names to internal struct fields (e.g. `min_trade_amount` -> `min_amount`) | Rename typo causes silent `None` on optional field or deserialization failure | Roundtrip test with known JSON fixture | Pending |
| 3 | The struct is pub-exported from soldier_infra and importable by soldier_core | Module visibility wrong, missing `pub mod` re-export | `cargo test -p soldier_infra` compiles and soldier_core can import | Pending |

## 3) Top 5 failure modes
| # | What goes wrong | Detection | Fail-closed mitigation | AT that catches it |
|---|----------------|-----------|----------------------|-------------------|
| 1 | Missing field in struct (e.g. `contract_multiplier` omitted) | Downstream code fails to compile when accessing the field | Compilation error blocks integration | AT-333 (field presence) |
| 2 | Wrong serde rename (e.g. `contract_size` vs `contract_multiplier`) | Deserialization silently produces `None` or `0` for the mis-renamed field | Make critical fields non-Option (so deserialization fails if the field is absent due to a wrong rename). Note: `#[serde(deny_unknown_fields)]` rejects extra fields from the wire, not missing required fields, so it does not catch wrong renames causing silent None. Recommend `deny_unknown_fields` only on test fixture structs -- using it in production would break when Deribit adds new API fields. | AT-333 (values from fetched metadata) |
| 3 | `kind` field not included, blocking InstrumentKind derivation in S1-002 | S1-002 cannot derive InstrumentKind from metadata | S1-002 test failures | AT-333 |
| 4 | Struct not pub-exported from soldier_infra | soldier_core cannot import the struct, blocking S1-002 | `cargo check` on dependent crate fails | AT-333 |
| 5 | Numeric field type mismatch (e.g. `tick_size` as `u64` instead of `f64`) | Deserialization fails on real API data containing decimals | Fixture-based deserialization test with real API response shape | AT-333 |

## 4) Open decisions (resolve before coding)

### Decision: Deribit field naming convention
- **What is ambiguous / missing**: Deribit API uses `min_trade_amount` and `contract_size`, but the contract refers to `min_amount` and `contract_multiplier`. The struct must map between these.
- **Evidence**: CONTRACT.md §1.0: "tick_size, amount_step, min_amount, and contract_multiplier"; Deribit API docs use `min_trade_amount`, `contract_size`.
- **Options**:
  1. Option A —Use Deribit field names verbatim in struct, rename at consumption point in soldier_core. Pros: struct is a faithful API mirror. Cons: misalignment with contract terminology.
  2. Option B —Use contract terminology in struct with `#[serde(rename = "...")]` for Deribit names. Pros: contract-aligned throughout. Cons: rename adds a mapping layer.
- **Chosen**: B —contract-aligned naming with serde renames. The struct serves the contract, not the API.
- **Why not others**: Option A pushes renaming to every consumer, increasing error surface.
- **Scope control**:
  - What we're NOT doing yet: response pagination, error handling for API calls, caching logic.
  - What unblocks us if this choice is wrong: serde renames are localized to one struct; easy to change.

### Decision: Which fields to include
- **What is ambiguous / missing**: Deribit returns many fields; which are required for this story?
- **Evidence**: CONTRACT.md AT-333 requires `tick_size`, `amount_step`, `min_amount`, `contract_multiplier`. S1-002 needs `kind`. S1-003/S1-006 need the struct to exist for cache wrapping.
- **Options**:
  1. Option A —Minimal struct: only the 5 fields required by contract + kind.
  2. Option B —Comprehensive struct: include all Deribit fields for future use.
- **Chosen**: A —minimal struct with only contract-required fields plus `instrument_name` for identity.
- **Why not others**: B adds untested surface area and violates YAGNI.
- **Scope control**:
  - What we're NOT doing yet: settlement fields, Greeks-related fields, expiry fields (deferred to S1-012).
  - What unblocks us if this choice is wrong: adding fields later is backward-compatible.

- [x] No unresolved decisions remain
- [x] Each decision grounded in evidence (file + line, not memory)

## 5) Wrong implementation gate
| AT | Wrong impl that passes | Why it's wrong | Tightening (new AT / golden vector / property test) |
|----|----------------------|----------------|---------------------------------------------------|
| AT-333 | Struct with all fields as `Option<f64>`, deserialization always succeeds but fields are `None` | Downstream code receives `None` for required fields, may unwrap or default unsafely | Golden vector: deserialize known Deribit fixture, assert all 5 required fields are `Some`/non-default |
| AT-333 | Struct with hardcoded default values via `#[serde(default)]` on required fields | Passes test but violates "no hardcoded defaults" contract clause | Test: deserialize empty JSON `{}`, assert it FAILS (no silent defaults for required fields) |
| AT-333 | Struct compiles but fields use wrong numeric types (e.g., tick_size: i64 instead of f64) | Deserialization succeeds for integer-valued samples but fails on real API data with decimals (e.g., tick_size=0.0001) | Golden vector: deserialize fixture with decimal values, assert no precision loss |

- [x] Every AT has at least one wrong impl identified
- [x] Every wrong impl is blocked by a tightened AT or new test
- [x] No AT remains where a wrong impl is easier than the correct one

## 6) Proof plan (AT → enforcement → tests)

| AT | Enforcement point | Proving test(s) | TRIP? | NON-TRIP? | Causality proof | Isolated? |
|----|-------------------|-----------------|-------|-----------|-----------------|-----------|
| AT-333 | InstrumentStruct (soldier_infra::venue) | test_deribit_instrument_struct_deserializes_all_required_fields | N/A (infra struct) | N/A (infra struct) | Field presence: all 5 fields populated from fixture | Yes |

Note: AT-333 enforcement lives in S1-002 (InstrumentKind derivation). This story provides the data substrate, not the enforcement point. TRIP/NON-TRIP testing is deferred to S1-002 where the enforcement logic lives.

- [x] Every safety-critical AT has TRIP + NON-TRIP (N/A for infra struct —enforcement in S1-002)
- [x] Every test proves causality (not just existence)
- [x] Each AT isolates one clause
- [x] No CLAIMED-NOT-PROVEN entries without a plan to fix

## 7) Economic risk (loss_mode)
- **If this fails in prod, worst financial outcome**: No direct financial risk from struct definition. Risk is indirect: if struct is wrong, downstream S1-002/S1-003 will use wrong metadata for sizing, potentially causing wrong exposure. But those stories have their own gates.
- **Fail-closed cap on loss**: Compilation failure blocks deployment. If struct deserializes wrong data, S1-003's cache TTL gate catches stale/missing metadata.
- **Drift metric**: `instrument_cache_refresh_errors_total` (defined in S1-006) will catch deserialization failures at runtime.
- **Loss boundary**: No direct loss boundary needed for a data struct. Downstream ReduceOnly gate (S1-003) limits blast radius.
- **Rollback plan**: Revert the struct definition; downstream crates fail to compile, preventing deployment of broken code.

## 8) Conflict scan & hot zones
- **Invariants/gates impacted**: None directly. This is a new struct definition.
- **If conflict with CONTRACT.md**: No conflict identified.
- Files with recent churn or shared ownership: `crates/soldier_infra/` is new infrastructure; no existing churn.
- Struct fields I'm assuming exist (verify before coding): Deribit API response fields (`kind`, `tick_size`, `amount_step`, `min_trade_amount`, `contract_size`).
- State machine transitions affected: None.

## 9) Constraint I expect to hit
Prior Postmortem: NONE
Reused Guardrail: NONE

- What will slow me down: Uncertainty about exact Deribit API field names and types without live API access.
- Exploit: Use Deribit public API documentation and sample responses to build a test fixture.
- Smallest fix that prevents it next time: Maintain a checked-in fixture file with a real API response for regression testing.

## 10) STOPLIGHT + Exit criteria

**STOPLIGHT**: YELLOW

**Debt Register** (required if YELLOW, DEFERRED items only):

| Item | Severity | Why deferred | Owner | Target slice | AT/proof to add |
|------|----------|-------------|-------|-------------|-----------------|
| Assumptions #1-#2: Deribit API field names/types and serde rename correctness are unvalidated without live API data | Medium | DEFERRED: cannot validate exact field names and serde mapping without a real Deribit API response | S1-011 owner | Pre-implementation (resolve with real API samples) | Deserialize a real `/public/get_instruments` response; assert all fields populated |

- [x] §1 clause audit: every AT traced to normative clause
- [x] §2 all assumptions validated or killed (DEFERRED: Assumptions #1-#2 pending live API data validation)
- [x] §3 all failure modes have detection + mitigation
- [x] §4 all decisions resolved, grounded in evidence
- [x] §5 wrong impl gate: every AT tightened, no easy wrong impl survives
- [x] §6 proof plan: TRIP + NON-TRIP for all safety-critical ATs, no CLAIMED-NOT-PROVEN
- [x] §7 loss_mode documented with fail-closed boundary + rollback plan
- [x] §8 conflict scan clean (no CONTRACT.md conflicts)
- [x] No new debt without owner + target slice (resolved by DEFERRED register entry above)
