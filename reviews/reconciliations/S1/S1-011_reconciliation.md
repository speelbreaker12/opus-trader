# S1-011 Reconciliation R1 Preflight Audit

**Story**: S1-011 -- S1.1 Deribit instrument structs
**Enforcement Point**: DispatcherChokepoint (indirect -- this story provides data substrate)
**Enforcing Contract ATs**: AT-333
**Auditor**: Claude Opus 4.6 (recon R1)
**Date**: 2026-02-23
**Mode**: READ-ONLY

---

## A) GATE RESULT

**PASS (YELLOW)** -- Story implementation is sound for its stated scope (infra struct definition). One design deviation from premortem and one minor debt item carry forward.

| Check | Status |
|-------|--------|
| AT-333 enforcement present | YES (structural via required fields + deser tests) |
| Fail-closed behavior | YES (missing required fields cause deser failure; compile-time enforcement) |
| Tests prove causality | PROVEN (15/15 pass; per-field omission + empty JSON + fixture roundtrip) |
| Premortem wrong-impls blocked | YES (all 3 wrong-impls from SS5 are blocked by tests) |
| Premortem decisions implemented | PARTIAL (SS4 chose Option B but naming is Option A -- see D1 below) |
| Premortem assumptions validated | 2/3 validated; 1 deferred (live API data) |
| Observability on reject/degrade | N/A for struct definition; `tracing::warn` on Unknown kind |
| No `unwrap()` in production code | CLEAN |
| All scope.touch files modified | YES (all 4 files present and correctly wired) |
| Tests compile and pass | YES (15 passed, 0 failed) |

---

## B) AT AUDIT TABLE

### AT-333: Instrument metadata from `/public/get_instruments`

| Audit Dimension | Finding | Evidence |
|-----------------|---------|----------|
| **1. Enforcement point** | `crates/soldier_infra/src/deribit/public/mod.rs:57::DeribitInstrument` (struct definition with required fields). Not a runtime enforcement point -- this is the data substrate. Runtime enforcement lives in downstream S1-002/S1-004. | File:57 -- `pub struct DeribitInstrument` |
| **2. Fail-closed behavior** | | |
| 2a. Missing required field | PASS -- `tick_size`, `min_trade_amount`, `contract_size` are bare `f64` (not `Option`), so deserialization fails if absent. Test: `test_required_fields_individually_enforced` (line 215) proves each. | File:80,83,94 (field defs); test file:215-237 |
| 2b. NaN/invalid values | NOT TESTED -- No NaN/infinity guard on `f64` fields. However, this is a struct definition story, not a validation story. NaN guards belong in downstream quantization (S1-004). | Premortem SS3 item #5 covers type mismatch |
| 2c. Unknown enum variant | PASS -- `DeribitInstrumentKind::Unknown` via `#[serde(other)]` (line 28); `SettlementPeriod::Unknown` via `#[serde(other)]` (line 42). Forward-compatible. | File:28,42; test:243-247 |
| 2d. Stale data | N/A -- No caching in this story. Staleness handled by S1-003. | |
| 2e. Parse error | PASS -- Required fields without `serde(default)` cause `serde_json::Error` on bad input. | test:189-195 (empty JSON), test:215-237 (per-field) |
| 2f. Missing data | PASS -- Same as 2a. | |
| **3. Causal proof** | **PROVEN** | |
| 3a. Field presence proof | `test_contract_required_fields_present` (line 86): asserts `tick_size=0.5`, `min_trade_amount=10.0`, `contract_size=10.0`, `contract_multiplier()=10.0` | test:86-97 |
| 3b. Empty JSON rejection proof | `test_empty_json_fails_deserialization` (line 189): `serde_json::from_str::<DeribitInstrument>("{}").is_err()` | test:189-195 |
| 3c. Per-field omission proof | `test_required_fields_individually_enforced` (line 215): removes each of 11 required fields one at a time, asserts deser fails | test:215-237 |
| 3d. amount_step optionality proof | `test_amount_step_none_when_absent` (line 102): `None` when absent. `test_amount_step_some_when_present` (line 111): `Some(1.0)` when present | test:102-116 |
| 3e. Kind mapping proof | `test_unknown_kind_maps_to_none` (line 261): `Unknown` maps to `None` | test:261-264 |
| **4. SS5 wrong-impls blocked** | See section C below | |
| **5. Observability** | `tracing::warn` at file:130 for unknown kind. No metrics (N/A for struct def). | |

**Verdict**: PROVEN

---

## C) PREMORTEM CROSS-REFERENCE

### SS2 Assumptions

| # | Assumption | Status | Evidence |
|---|-----------|--------|----------|
| 1 | Deribit API fields include `kind`, `tick_size`, `amount_step`, `min_trade_amount`, `contract_size` | PARTIALLY VALIDATED -- Fixture-based testing confirms struct can deserialize these fields. Live API validation deferred (YELLOW debt item from premortem). | test fixtures at test file:11-67 |
| 2 | `serde(rename)` correctly maps Deribit field names | DEVIATION -- Premortem chose Option B (contract-aligned naming with serde renames) but implementation uses Deribit's native names directly (`min_trade_amount` not `min_amount`, `contract_size` not `contract_multiplier`). A `contract_multiplier()` method alias exists. See D1 below. | File:83 (`min_trade_amount`), File:94 (`contract_size`), File:116-118 (`contract_multiplier()`) |
| 3 | Struct is pub-exported and importable by soldier_core | VALIDATED -- `pub mod public` in `deribit/mod.rs:6`, re-exports in `deribit/mod.rs:10-13`, `pub mod deribit` in `lib.rs:5`. Test: `test_pub_reexport` (line 173). | `deribit/mod.rs:6,10-13`; `lib.rs:5`; test:173-177 |

### SS4 Decisions

| Decision | Chosen | Implemented | Match? | Notes |
|----------|--------|-------------|--------|-------|
| Field naming convention | B -- contract-aligned with serde renames | A -- Deribit-native names, `contract_multiplier()` method alias | **MISMATCH** | See D1. The struct field names are `min_trade_amount` and `contract_size` (Deribit names), not `min_amount` and `contract_multiplier` (contract names). The premortem explicitly chose Option B. However, functionally equivalent: consumers access `contract_multiplier()` via the method. |
| Which fields to include | A -- minimal (5 contract fields + kind + identity) | A -- minimal plus lifecycle fields (`is_active`, `settlement_period`, currencies, timestamps, `is_perpetual`) | **MATCH** (superset) | Implementation includes more fields than the "minimal 5+kind" option, but all are from the venue API (not fabricated). Additional fields support downstream stories (S1-012 expiry, S1-002 kind derivation). |

### SS5 Wrong-Impl Gate

| Wrong Impl | Blocked? | Blocking Test | Evidence |
|------------|----------|---------------|---------|
| All fields `Option<f64>`, deser always succeeds with `None` | YES | `test_required_fields_individually_enforced` -- removing any required field causes deser failure. `test_contract_required_fields_present` -- asserts concrete values, not `None`. | test:215-237, test:86-97 |
| Hardcoded defaults via `#[serde(default)]` on required fields | YES | `test_empty_json_fails_deserialization` -- empty JSON fails. `test_required_fields_individually_enforced` -- per-field removal fails. The 4 `serde(default)` annotations are ONLY on genuinely optional fields: `amount_step`, `expiration_timestamp`, `is_perpetual`, `tick_size_steps`. | File:89,97,104,108; test:189-195, test:215-237 |
| Wrong numeric types (e.g. `tick_size: i64`) | YES | `test_contract_required_fields_present` -- asserts decimal values (`tick_size=0.5`). ETH option fixture uses `tick_size=0.0005`. If type were `i64`, these would fail or silently truncate. | test:91 (`0.5`), fixture:38 (`0.0005`) |

---

## D) DESIGN RISK NOTES

### D1: Naming Convention Deviation from Premortem (LOW risk)

**Finding**: The premortem SS4 chose Option B (contract-aligned naming with serde renames: `min_amount`, `contract_multiplier`) but the implementation uses Option A (Deribit's native names: `min_trade_amount`, `contract_size`).

**Impact**: LOW. The `contract_multiplier()` method (file:116-118) provides contract-aligned access. However, direct field access uses `instr.min_trade_amount` (Deribit terminology) rather than `instr.min_amount` (contract terminology). This creates a terminology gap that could confuse developers reading contract docs alongside code.

**Risk**: A developer writing downstream code might use `instr.contract_size` directly rather than `instr.contract_multiplier()`, creating inconsistent terminology in the codebase. No runtime or correctness risk -- purely a naming/readability concern.

**Recommendation**: Either (a) add a `min_amount()` method alias similar to `contract_multiplier()`, or (b) update the premortem to reflect the actual design choice and document why Option A was preferred in practice. LOW priority.

### D2: `amount_step` is `Option<f64>` with `serde(default)` (ACCEPTABLE)

**Finding**: `amount_step` is one of the 4 fields cited in AT-333 ("quantization/sizing uses `tick_size`, `amount_step`, `min_amount`, and `contract_multiplier`"). It is `Option<f64>` with `#[serde(default)]`, meaning it silently defaults to `None` when absent from the API response.

**Impact**: ACCEPTABLE. The Deribit API genuinely does not return `amount_step` for all instruments (the BTC perpetual fixture at test:11-26 omits it). Making it `Option` is the correct representation. The "no hardcoded defaults" clause in AT-333 means "don't fabricate values" not "don't use `Option`." Downstream quantization (S1-004) must handle `None` with fail-closed logic per CONTRACT.md SS2.4.

**Risk**: If downstream code does `.unwrap_or(1.0)` or similar optimistic default on `amount_step`, AT-333 is violated. This is an S1-004 concern, not S1-011.

### D3: No `deny_unknown_fields` on `DeribitInstrument` (ACCEPTABLE)

**Finding**: The struct does not use `#[serde(deny_unknown_fields)]`. CLAUDE.md recommends it for config structs.

**Impact**: ACCEPTABLE. The premortem SS3 item #2 explicitly discusses this: "`deny_unknown_fields` rejects extra fields from the wire, not missing required fields, so it does not catch wrong renames causing silent None. Recommend `deny_unknown_fields` only on test fixture structs -- using it in production would break when Deribit adds new API fields." This is the correct decision for an external API response struct.

### D4: `map_deribit_kind_to_input` Not Consumed by soldier_core (INFO)

**Finding**: The function `map_deribit_kind_to_input` (file:124-134) is defined and tested but has zero callers in `soldier_core`. It is only called in the test file.

**Impact**: INFO. This function was likely intended for S1-002 consumption. Its existence is harmless. soldier_core does not import anything from `soldier_infra::deribit` yet (grep confirms zero hits).

### D5: No NaN/Infinity Guards on f64 Fields (DEFERRED)

**Finding**: `tick_size`, `min_trade_amount`, `contract_size` are bare `f64` with no validation against `NaN`, `Infinity`, negative values, or zero.

**Impact**: DEFERRED. This is explicitly outside S1-011's scope (struct definition only). Validation belongs in downstream quantization/sizing stories (S1-004). However, this is a valid concern for the overall system -- if the venue returns `tick_size: NaN`, the struct will happily deserialize it.

---

## E) REMEDIATION PLAN

| # | Finding | Severity | Action Required | Owner | Target |
|---|---------|----------|----------------|-------|--------|
| R1 | SS4 naming decision deviation (D1) | LOW | Either add `min_amount()` method alias or update premortem to reflect actual design choice | S1-011 owner | Recon self_review |
| R2 | Live API validation of field names (premortem debt) | MEDIUM | Deserialize a real Deribit `/public/get_instruments` response in a test (can be a checked-in fixture from manual API call) | S1-011 owner | Pre-production |
| R3 | NaN/Infinity guards (D5) | LOW | Add validation in downstream quantization/sizing (S1-004), not in struct definition | S1-004 owner | S1-004 |
| R4 | `map_deribit_kind_to_input` uncalled (D4) | INFO | No action needed; will be consumed by S1-002 or successors | N/A | N/A |

**Blocking remediations**: 0
**Non-blocking remediations**: 2 (R1, R2)
**Deferred to other stories**: 1 (R3)
**Info only**: 1 (R4)

---

## F) SCOPE CHECK

### Files in scope.touch -- all present and correctly wired

| File | Present | Role | Verified |
|------|---------|------|----------|
| `crates/soldier_infra/src/deribit/public/mod.rs` | YES | Struct definitions (DeribitInstrument, DeribitInstrumentKind, SettlementPeriod, TickSizeStep) + `map_deribit_kind_to_input` | YES -- 143 lines, all types defined |
| `crates/soldier_infra/src/deribit/mod.rs` | YES | Re-exports from `public` module | YES -- line 10-13 re-exports all 5 symbols |
| `crates/soldier_infra/src/lib.rs` | YES | `pub mod deribit` declaration | YES -- line 5 |
| `crates/soldier_infra/Cargo.toml` | YES | Dependencies: `serde`, `serde_json`, `tracing` | YES -- lines 7-10 |

### Test file

| File | Tests | All Pass |
|------|-------|----------|
| `crates/soldier_infra/tests/test_deribit_instrument.rs` | 15 | YES (15 passed, 0 failed) |

### Out-of-scope files -- no modifications detected

No files outside `scope.touch` were modified by this story. Confirmed via `git status` and grep that no `soldier_core` files reference `DeribitInstrument` or `soldier_infra::deribit`.

---

## Read-Only Integrity Check

No production code or test files were modified during this audit. `git status --porcelain` at start confirmed no S1-011 scope files were in a modified state (all modifications are in unrelated files: `CLAUDE.md`, `soldier_core` files, etc.).

---

READY FOR SELF_REVIEW
