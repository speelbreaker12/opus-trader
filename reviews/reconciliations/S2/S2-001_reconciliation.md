---
provenance:
  tool: internal
  model: claude-opus-4-6
  prompt_style: none
  cycle: NONE
  phase_equivalent: R1
  review_basis: "STORY_SCOPE (R1 Read-Only)"
  story_id: S2-001
  slice_id: S2
  head_commit: "a106eb983ee2d744e3a3f94eddf2b3f39de1a43d"
  generated_at: "2026-02-26T22:00:00Z"
  artifact_provenance: manual
  schema_version: "evidence_ledger.v1"
---

# Evidence Ledger: S2-001

**Story**: S2-001 -- Compute intent_hash from quantized fields only and exclude timestamps
**Risk**: LOW
**Enforcement point**: WAL (declared); actual enforcement is `compute_intent_hash()` in `hash.rs` (pure function)
**Story verdict**: PARTIAL (R1 interim)

---

## 1. Proof Scope

### PRD Entry

- **ID**: S2-001
- **Description**: Compute intent_hash from quantized fields only and exclude timestamps.
- **Enforcement point (declared)**: WAL
- **Enforcing ATs**: AT-201, AT-343, AT-928, AT-218
- **Implementation tests**: `crates/soldier_core/tests/test_idempotency.rs::test_at218_deterministic_hash`
- **Scope.touch**: `hash.rs`, `mod.rs`, `lib.rs`, `test_idempotency.rs`

### Premortem Summary (from /tmp/S2-001_premortem_fresh.md)

- **STOPLIGHT**: YELLOW
- **Reason**: AT-201 and AT-928 are not enforceable within this story's scope.
- **Key assumptions (S2)**: xxhash64 determinism, 0xFF separator safety (UTF-8 guarantee), `to_le_bytes()` platform-independence, caller passes quantized inputs (not validated here).
- **Key decisions (S4)**: xxhash64 per CONTRACT (no discretion), seed=0.
- **Wrong-impl traps (S5)**: Constant hash (blocked by field-sensitivity tests), timestamp normalization trick (blocked by compile-time struct exhaustiveness test).

---

## 2. Enforcement Point Locations

| Invariant | File | Line | Function | Notes |
|-----------|------|------|----------|-------|
| Hash uses quantized integer inputs (i64 qty_steps, i64 price_ticks) | `crates/soldier_core/src/idempotency/hash.rs` | 16-29 | `IntentHashInput` struct | Type system enforces: fields are `i64` and `u32`, not `f64`. |
| Hash excludes timestamps | `crates/soldier_core/src/idempotency/hash.rs` | 16-29 | `IntentHashInput` struct | No timestamp field exists in the struct. |
| Hash formula matches CONTRACT | `crates/soldier_core/src/idempotency/hash.rs` | 38-57 | `compute_intent_hash()` | xxhash64 over instrument+side+qty_steps+price_ticks+group_id+leg_idx with 0xFF separators. |
| Hash is deterministic | `crates/soldier_core/src/idempotency/hash.rs` | 38-57 | `compute_intent_hash()` | Pure function: no state, no randomness, no timestamps, no I/O. |
| 0xFF field separator prevents boundary ambiguity | `crates/soldier_core/src/idempotency/hash.rs` | 40-54 | `compute_intent_hash()` | 0xFF byte between every field; 0xFF cannot appear in valid UTF-8 strings. |
| Module re-export | `crates/soldier_core/src/idempotency/mod.rs` | 5 | `pub use` | Exports `IntentHashInput`, `compute_intent_hash`, `format_intent_hash`, `intent_hash_ih16`. |
| Crate module declaration | `crates/soldier_core/src/lib.rs` | 4 | `pub mod idempotency` | Module declared at crate root. |

---

## 3. Proving Test Locations

| AT | Test file | Line | Test function | What it proves |
|----|-----------|------|---------------|----------------|
| AT-218 | `crates/soldier_core/tests/test_idempotency.rs` | 26 | `test_at218_deterministic_hash` | Same input -> same hash (determinism). |
| AT-218 | `crates/soldier_core/tests/test_idempotency.rs` | 35 | `test_at218_two_codepaths_same_hash` | Independently constructed identical inputs -> identical hash. |
| AT-343 | `crates/soldier_core/tests/test_idempotency.rs` | 65 | `test_at343_no_timestamp_in_hash` | Hash output is time-independent (calls twice, asserts equality). |
| AT-343 | `crates/soldier_core/tests/test_idempotency.rs` | 81 | `test_at343_no_timestamp_field` | Compile-time proof: struct literal exhaustiveness means adding a timestamp field breaks compilation. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 98 | `test_uses_integer_qty_steps` | Different qty_steps -> different hash. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 110 | `test_uses_integer_price_ticks` | Different price_ticks -> different hash. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 127 | `test_different_instrument_different_hash` | Different instrument -> different hash. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 138 | `test_different_side_different_hash` | Different side -> different hash. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 149 | `test_different_group_id_different_hash` | Different group_id -> different hash. |
| (field sensitivity) | `crates/soldier_core/tests/test_idempotency.rs` | 160 | `test_different_leg_idx_different_hash` | Different leg_idx -> different hash. |
| (formatting) | `crates/soldier_core/tests/test_idempotency.rs` | 174 | `test_format_intent_hash_length` | Format produces 16-char hex string. |
| (formatting) | `crates/soldier_core/tests/test_idempotency.rs` | 186 | `test_ih16_is_full_hash_hex` | ih16 == full formatted hash (xxhash64 is 64 bits = 16 hex chars). |
| (non-zero) | `crates/soldier_core/tests/test_idempotency.rs` | 198 | `test_hash_nonzero` | Hash is non-zero for typical inputs. |
| (boundary) | `crates/soldier_core/tests/test_idempotency.rs` | 207 | `test_field_boundary_separation` | Shifted field boundaries produce different hashes (prevents concatenation ambiguity). |

**Additional tests** (in `adversarial_gi_enforcement.rs`): Lines 375-497 contain adversarial tests that also exercise `compute_intent_hash` for determinism, repeated calls, and field sensitivity. These provide extra coverage beyond the primary test file.

**Test execution result**: All 14 tests in `test_idempotency.rs` pass (verified during this R1 audit).

---

## 4. Causal Proof Validation

### AT-218: Deterministic hash across codepaths

**Type**: Property test (pure function determinism). NOT a trip/non-trip test.

**Proof structure**:
- `test_at218_deterministic_hash`: Calls `compute_intent_hash` twice with the same input, asserts equality. Proves idempotence of the function.
- `test_at218_two_codepaths_same_hash`: Constructs two independent `IntentHashInput` values with the same fields, asserts equal hash. Proves no hidden state.
- Field sensitivity tests (`test_different_*`, `test_uses_integer_*`): Change each field individually, assert hash changes. These block the "constant hash" wrong implementation.
- `test_field_boundary_separation`: Proves the 0xFF separator prevents concatenation ambiguity.

**Assessment**: Causal proof is STRONG for a pure function. The combination of equality tests + field sensitivity tests + boundary separation test blocks all obvious wrong implementations.

### AT-343: Hash excludes wall-clock timestamps

**Type**: Structural proof (compile-time) + runtime check.

**Proof structure**:
- `test_at343_no_timestamp_field`: Compile-time proof via struct literal exhaustiveness. If anyone adds a timestamp field to `IntentHashInput`, this test fails to compile because it constructs the struct with only the 6 current fields.
- `test_at343_no_timestamp_in_hash`: Runtime proof that the same input hashed at different "times" (sequential calls) produces the same output.

**Assessment**: Causal proof is STRONG. The compile-time proof is the strongest possible: the type system prevents timestamps from entering the hash input.

### AT-928: WAL dedup (NOOP on duplicate intent_hash)

**Type**: Integration test required -- NOT testable by S2-001.

**Proof structure**: NONE in S2-001. The hash function provides the prerequisite (computing the hash), but AT-928 requires WAL lookup logic that does not exist in `hash.rs`.

**Assessment**: CLAIMED_NOT_PROVEN. Correctly identified in premortem S6 as requiring WAL integration.

### AT-201: Fail-closed intent classification

**Type**: Intent classification gate -- NOT related to hashing.

**Proof structure**: NONE in S2-001. AT-201 is about classifying unknown intent actions as OPEN, which is tested in `test_reject_reason.rs:262` (separate story/module).

**Assessment**: CLAIMED_NOT_PROVEN. Misattributed to this story. AT-201 is tested elsewhere (`test_reject_reason.rs`) under a different story's scope. The premortem correctly identifies this as a PRD traceability error.

---

## 5. Fail-Closed Behavior Validation

S2-001 implements a **pure function** (`compute_intent_hash`). It has no side effects, no state mutation, no conditional gates, and no safety decisions. The standard 6-category fail-closed analysis applies differently here than for a gate/guard:

| Category | Applicable? | Analysis |
|----------|-------------|----------|
| **Missing/None** | NO | `IntentHashInput` is a struct with all required fields; Rust's type system prevents construction with missing fields. No `Option` types in the struct. |
| **NaN/Inf** | NO | All numeric fields are `i64` and `u32` (integers). NaN/Inf do not exist for integer types. |
| **Negative** | PARTIAL | `qty_steps` and `price_ticks` are `i64`, so negative values are representable. However, negative values hash deterministically (this is correct behavior -- the hash function should not reject inputs; upstream quantization validates value ranges). |
| **Out-of-domain** | NO | The hash function is defined for all possible input values. There is no "invalid" input. Empty strings, zero values, max i64 -- all produce valid deterministic hashes. |
| **Corrupt** | NO | Rust's `&str` type guarantees valid UTF-8. `i64`/`u32` cannot be corrupt. The function operates on well-typed inputs by construction. |
| **Narrowing casts** | NO | No casts in `compute_intent_hash()`. `leg_idx.to_le_bytes()` converts `u32` to `[u8; 4]` (not narrowing). `qty_steps.to_le_bytes()` converts `i64` to `[u8; 8]` (not narrowing). |

**Summary**: 0 of 6 categories produce actionable fail-closed findings for this pure function. The type system handles the safety that gates/guards handle with runtime checks.

---

## 6. Premortem Alignment Validation

### S2 Assumptions

| # | Assumption | Premortem status | Actual status |
|---|-----------|-----------------|---------------|
| 1 | xxhash64 determinism across restarts | Partial (same-process proven) | CONFIRMED partial -- same-process tests pass; cross-restart deferred to S6-001 |
| 2 | 0xFF separator safety | Validated by type system | CONFIRMED -- Rust `&str` guarantees valid UTF-8; 0xFF cannot appear |
| 3 | `to_le_bytes()` platform-independence | Validated by language spec | CONFIRMED -- Rust spec guarantees little-endian output |
| 4 | Callers pass quantized inputs | NOT validated | CONFIRMED gap -- no caller-side validation in S2-001 (structural gap, out of scope) |
| 5 | group_id format irrelevant to determinism | Validated | CONFIRMED -- hash is deterministic regardless of input format |

### S4 Decisions

| Decision | Chosen | Implemented? |
|----------|--------|-------------|
| Hash algorithm: xxhash64 | A (CONTRACT mandated) | YES -- `xxh64(&buf, 0)` at hash.rs:56 |
| Seed value: 0 | A (simplest) | YES -- seed=0 at hash.rs:56 |

### S5 Wrong-Impl Traps

| Wrong impl | Blocked? | Blocking test |
|------------|----------|---------------|
| Constant hash (return 42) | YES | 6 field-sensitivity tests each assert hash CHANGES when one field changes |
| Timestamp normalization to epoch | YES | `test_at343_no_timestamp_field` -- struct has no timestamp field at all |
| WAL dedup with partial hex comparison | OUT OF SCOPE | S2-001 provides `format_intent_hash` which is 16 chars; `test_format_intent_hash_length` confirms |
| AT-201 not implemented | OUT OF SCOPE | AT-201 is misattributed |

### S6 Proof Plan

| AT | Premortem prediction | Actual |
|----|---------------------|--------|
| AT-218 | Pure function property test | MATCHES -- determinism + field sensitivity tests |
| AT-343 | Compile-time structural proof | MATCHES -- struct exhaustiveness test |
| AT-928 | CLAIMED-NOT-PROVEN | MATCHES -- no WAL tests in S2-001 |
| AT-201 | CLAIMED-NOT-PROVEN | MATCHES -- no intent classification in hash.rs |

**Premortem alignment: STRONG.** The premortem accurately predicted the proof structure, identified the two misattributed ATs, and correctly classified the story as LOW risk pure function work.

---

## 7. Gap List

| Gap ID | Priority | AT | Description | Recommended action | Status |
|--------|----------|-----|-------------|-------------------|--------|
| GAP-S2-001-1 | P2 | AT-201 | AT-201 is misattributed to S2-001. S2-001 implements hashing, not intent classification. AT-201 is tested in `test_reject_reason.rs` under a different story. | Remove AT-201 from S2-001's `enforcing_contract_ats` in `plans/prd.json`. PRD metadata fix only, no code change. | **FIXED (R5)** -- AT-201 removed from `enforcing_contract_ats` and `primary_owner_for` in prd.json. |
| GAP-S2-001-2 | P1 | AT-928 | AT-928 requires WAL dedup behavior (look up hash, return NOOP). S2-001 only provides the hash function prerequisite. No end-to-end dedup test exists in S2-001. | Verify AT-928 is tested in the WAL story (S2-003 or equivalent). If no WAL story owns AT-928 integration testing, create a debt entry. | **DEFERRED** -- debt entry in DEBT_REGISTER.json. |
| GAP-S2-001-3 | P2 | -- | `compute_intent_hash` has ZERO production callers in `src/`. It is defined and tested but not called from any production code path. This is a wiring gap (PROVEN-UNIT, not PROVEN-INTEGRATED). | This is expected at S2-001 scope -- the function is a building block. Verify that a downstream story (label generation, WAL integration) calls `compute_intent_hash`. | **DEFERRED** -- debt entry in DEBT_REGISTER.json. |
| GAP-S2-001-4 | P2 | AT-218 | `implementation_tests` in PRD lists only `test_at218_deterministic_hash`, but 13 additional tests exist. The PRD understates the test coverage. | Update `implementation_tests` to include the full test list, or document that `test_idempotency.rs` (all tests) is the proving suite. | **FIXED (R5)** -- `implementation_tests` updated to list all 16 tests (14 original + 2 new). |
| GAP-S2-001-5 | P2 | -- | PRD `reason_codes` lists `LabelTooLong` but hash.rs produces no reject reasons. LabelTooLong belongs to S2-002. | Remove LabelTooLong from S2-001 reason_codes in prd.json. | **FIXED (R5)** -- `reason_codes.values` set to empty array. |
| GAP-S2-001-6 | P2 | AT-343 | No golden vector test pins the hash algorithm to xxhash64 with seed=0. | Add `test_golden_vector_xxhash64` to test_idempotency.rs. | **FIXED (R5)** -- Test added: asserts `compute_intent_hash(sample_input()) == 7179042994956709649` and hex `63a1159155a6af11`. |
| GAP-S2-001-7 | P2 | AT-343 | No explicit test verifies the hash ignores non-canonical fields. | Add `test_hash_uses_only_canonical_fields` to test_idempotency.rs. | **FIXED (R5)** -- Test added: struct literal exhaustiveness + `size_of` assertion (72 bytes = exactly 6 canonical fields). |

---

## 8. Per-AT Verdict Table

| AT | Verdict | Rationale |
|----|---------|-----------|
| AT-218 | **PROVEN** | Enforcement exists (`compute_intent_hash` at hash.rs:38), tests prove determinism (`test_at218_*`) and block wrong impls (field sensitivity tests). Pure function property test -- TRIP/NON-TRIP not applicable. |
| AT-343 | **PROVEN** | Enforcement exists (struct definition excludes timestamps at hash.rs:16-29), compile-time proof via struct exhaustiveness (`test_at343_no_timestamp_field`), runtime confirmation (`test_at343_no_timestamp_in_hash`). |
| AT-928 | **CLAIMED_NOT_PROVEN** | S2-001 provides the hash function but does not implement WAL dedup logic. No test in S2-001 proves the "NOOP on duplicate" behavior. Requires WAL integration story. |
| AT-201 | **CLAIMED_NOT_PROVEN** | Misattributed to S2-001. AT-201 is about intent classification (unknown action -> OPEN), not hashing. Tested in `test_reject_reason.rs` under a different story's ownership. |

---

## 9. Story Verdict

**PARTIAL** (R1 interim)

**Rationale**: AT-218 and AT-343 are PROVEN with strong causal evidence. AT-928 and AT-201 are CLAIMED_NOT_PROVEN -- one is a prerequisite gap (AT-928, downstream WAL story needed), one is a misattribution (AT-201, PRD metadata error). The code itself is clean, well-tested, and correctly implements the CONTRACT.md specification.

---

## 10. Premortem Gate Status

- `plans/premortem_ready.sh S2-001` exits 1: FAIL
  - STOPLIGHT is YELLOW with 5 unresolved gaps not marked DEFERRED or FIX IN STEP 5
  - 1 AT ownership conflict found
- This is expected for a retroactive recon where the premortem was written fresh in Mode A and the gaps identified in the premortem (AT-201 misattribution, AT-928 out-of-scope) need to be formally resolved.
