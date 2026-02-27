---
provenance:
  tool: internal
  model: claude-opus-4-6
  phase_equivalent: R3
  review_basis: "STORY_SCOPE (Cycle 1)"
  story_id: S2-001
  slice_id: S2
  head_commit: "a106eb983ee2d744e3a3f94eddf2b3f39de1a43d"
  generated_at: "2026-02-26T23:30:00Z"
  schema_version: "review_artifact_sidecar.v1"
---

# R3A Cross-Review: S2-001

**Review basis**: STORY_SCOPE (Cycle 1)
**Reviewer**: AGENT (cross-reviewer, did NOT author R1 ledger)
**Story**: S2-001 -- Compute intent_hash from quantized fields only and exclude timestamps

---

## R3A Checklist

### 1. AT Causal Proof

**Note on proof type**: S2-001 implements a pure function (`compute_intent_hash`). There is no dispatch, no gate, no state mutation. Standard trip/non-trip (dispatch_count, reject_reason, latch_reason) is NOT applicable. The appropriate proof type is property testing.

#### AT-218 (Deterministic hash across codepaths)

**Evidence ledger claim**: PROVEN via property tests.

**Cross-review verification**:
- `test_at218_deterministic_hash` (test_idempotency.rs:26): Calls `compute_intent_hash` twice with identical input, asserts `h1 == h2`. VERIFIED -- line 26-30 of test file.
- `test_at218_two_codepaths_same_hash` (test_idempotency.rs:35): Constructs two independent `IntentHashInput` structs with same field values, asserts equal hashes. VERIFIED -- lines 35-57.
- Field sensitivity tests (6 tests): Each changes exactly one field and asserts the hash changes. VERIFIED -- lines 98-168. These are essential tightening tests that block the "constant hash" wrong implementation.
- Adversarial tests in `adversarial_gi_enforcement.rs:375-500`: Provide independent confirmation of determinism, repeated-call stability, field sensitivity, and boundary separation. VERIFIED -- lines 375-500.

**Causal proof assessment**: STRONG. The property test combination (equality on same inputs + inequality on different inputs) is the correct proof pattern for a pure function. The 6 field-sensitivity tests are individually necessary -- removing any one of them would allow a wrong implementation that ignores that field.

**Agreement with R1 verdict**: AGREE -- PROVEN.

#### AT-343 (Hash excludes wall-clock timestamps)

**Evidence ledger claim**: PROVEN via structural compile-time proof + runtime check.

**Cross-review verification**:
- `test_at343_no_timestamp_field` (test_idempotency.rs:81): Constructs `IntentHashInput` with only the 6 known fields using struct literal syntax. If anyone adds a field (e.g., `timestamp`), this test fails to compile because the struct literal is incomplete. VERIFIED -- lines 81-92.
- `test_at343_no_timestamp_in_hash` (test_idempotency.rs:65): Sequential calls produce same hash. VERIFIED but WEAK as a standalone proof -- this only proves the hash function has no internal time dependency; it does not prove timestamps cannot enter via inputs.
- However, `test_at343_no_timestamp_field` is the real proof: the struct definition at hash.rs:16-29 has no timestamp field. VERIFIED by reading hash.rs.

**Causal proof assessment**: STRONG. The compile-time proof (struct exhaustiveness) is the strongest possible evidence. The struct cannot carry timestamps. The function does not access `SystemTime` or any clock (verified by reading hash.rs lines 38-57 -- no imports of time-related crates, no `std::time` usage).

**Agreement with R1 verdict**: AGREE -- PROVEN.

#### AT-928 (WAL dedup NOOP on duplicate hash)

**Evidence ledger claim**: CLAIMED_NOT_PROVEN.

**Cross-review verification**:
- CONTRACT.md line 1007-1010: AT-928 requires "WAL already contains intent_hash -> new intent with same hash is NOOP."
- `hash.rs` contains only `compute_intent_hash`, `format_intent_hash`, `intent_hash_ih16`. No WAL lookup. No NOOP behavior.
- No test in `test_idempotency.rs` exercises WAL dedup.
- Searched `crates/soldier_core/src/` for `compute_intent_hash` callers: only `hash.rs` definition and `mod.rs` re-export. Zero production callers.

**Causal proof assessment**: Correctly identified as not enforceable within S2-001.

**Agreement with R1 verdict**: AGREE -- CLAIMED_NOT_PROVEN.

#### AT-201 (Fail-closed intent classification)

**Evidence ledger claim**: CLAIMED_NOT_PROVEN (misattributed).

**Cross-review verification**:
- CONTRACT.md line 106-109: AT-201 is about "unknown `action` value -> classification MUST be OPEN."
- `hash.rs` contains no intent classification logic, no `action` field, no OPEN/CLOSE distinction.
- AT-201 IS tested at `test_reject_reason.rs:262` (`test_reject_reason.rs` -- AT-201 comment confirmed).
- The PRD `enforcing_contract_ats` for S2-001 lists AT-201, which is a metadata error.

**Causal proof assessment**: Correctly identified as misattributed.

**Agreement with R1 verdict**: AGREE -- CLAIMED_NOT_PROVEN.

**Checklist item**: [x] AT causal proof -- all 4 ATs reviewed against code/tests, not just ledger text.

---

### 2. AT Semantic Match (CONTRACT.md re-read)

**Selected AT**: AT-218

**CONTRACT.md clause** (line 979-981):
> AT-218
> - Given: two codepaths compute the same intent fields.
> - When: `intent_hash` is generated.
> - Then: both hashes are identical.

**Implementation match**: `compute_intent_hash` is a pure function that takes `IntentHashInput` and returns `u64`. Same inputs always produce same output (no hidden state, no randomness). `test_at218_two_codepaths_same_hash` directly tests the Given/When/Then of AT-218 by constructing two independent `IntentHashInput` values with identical fields and asserting hash equality.

**Semantic match**: EXACT. The test directly implements the AT's specification.

**Checklist item**: [x] AT semantic match -- AT-218 re-read in CONTRACT.md, matched to implementation.

---

### 3. Premortem S4 Decisions Implemented As Chosen

| Decision | Chosen option | Implemented? | Verification |
|----------|--------------|-------------|--------------|
| Hash algorithm: xxhash64 | A (CONTRACT mandated) | YES | hash.rs:9 imports `xxhash_rust::xxh64::xxh64`; line 56 calls `xxh64(&buf, 0)` |
| Seed value: 0 | A (simplest) | YES | hash.rs:56: `xxh64(&buf, 0)` -- seed is the second argument, set to 0 |

**Checklist item**: [x] Premortem S4 decisions implemented as chosen.

---

### 4. Premortem S5 Wrong Impls Blocked by Tightening Tests

| Wrong impl | Premortem claim | Actually blocked? | Verification |
|------------|----------------|-------------------|--------------|
| Constant hash (return 42) | Blocked by field-sensitivity tests | YES | 6 field-sensitivity tests (`test_different_*`, `test_uses_integer_*`) each assert hash CHANGES when one field changes. A constant function fails all 6. |
| Timestamp normalization to epoch | Blocked by `test_at343_no_timestamp_field` | YES | Struct literal exhaustiveness prevents adding a timestamp field without breaking compilation. |
| WAL dedup with partial hex comparison | Out of scope | CORRECT | `format_intent_hash` produces 16 chars, `test_format_intent_hash_length` confirms. But WAL dedup is S2-003/downstream. |
| AT-201 not implemented | Out of scope | CORRECT | Misattributed AT. |

**Checklist item**: [x] Premortem S5 wrong impls blocked by tightening tests.

---

### 5. Premortem S2 Assumptions Turned Into Tests or Killed

| # | Assumption | Status | Test/Kill |
|---|-----------|--------|-----------|
| 1 | xxhash64 determinism across restarts | Partial -- same-process proven | `test_at218_deterministic_hash` proves same-process. Cross-restart deferred to S6-001. ACCEPTABLE for S2-001 scope. |
| 2 | 0xFF separator safety (UTF-8 guarantee) | Killed by type system | Rust `&str` guarantees valid UTF-8. 0xFF (0b11111111) is not valid UTF-8. Type system prevents this. `test_field_boundary_separation` tests shifted boundaries. |
| 3 | `to_le_bytes()` platform-independence | Killed by language spec | Rust `to_le_bytes()` always produces little-endian. Language guarantee. |
| 4 | Callers pass quantized inputs | NOT validated | Structural gap, out of scope. Type system (`i64` fields) prevents f64 confusion at the function boundary but cannot verify the caller computed the value via quantization. |
| 5 | group_id format irrelevant | Killed by analysis | Hash is deterministic for any string. Format does not matter. |

**Checklist item**: [x] Premortem S2 assumptions turned into tests or killed (except S2-A4 which is correctly deferred as out of scope).

---

### 6. Fail-Closed on All 6 Categories

S2-001 implements a pure function. The R1 ledger assessed 0/6 categories as applicable. Cross-review:

| Category | R1 Assessment | Cross-Review Assessment | Agree? |
|----------|--------------|------------------------|--------|
| Missing/None | N/A -- struct prevents missing fields | AGREE -- all fields are required by Rust struct construction. No `Option` fields. | YES |
| NaN/Inf | N/A -- integer types only | AGREE -- `i64` and `u32` have no NaN/Inf. `&str` has no NaN/Inf. | YES |
| Negative | N/A -- negative values hash correctly | AGREE -- negative `i64` values produce deterministic hashes via `to_le_bytes()`. The hash function should not reject inputs; upstream validates ranges. | YES |
| Out-of-domain | N/A -- hash defined for all inputs | AGREE -- empty strings, zero, max i64 all produce valid hashes. | YES |
| Corrupt | N/A -- Rust type system prevents corruption | AGREE -- `&str` is valid UTF-8 by invariant. Integers cannot be "corrupt." | YES |
| Narrowing casts | N/A -- no casts | AGREE -- `to_le_bytes()` is widening (i64 -> [u8; 8]), not narrowing. | YES |

**Checklist item**: [x] Fail-closed on all 6 categories (N/A for pure function -- confirmed).

---

### 7. Combinatorial Coverage

For `compute_intent_hash` with 6 input fields:
- Each field is tested individually for sensitivity (6 tests).
- Boundary separation is tested (1 test).
- This is adequate for a hash function -- the hash processes fields sequentially in a buffer, so field interactions are implicitly covered by the 0xFF separator.

**Missing**: No test varies two fields simultaneously to detect interaction effects. However, for a streaming hash with byte-level separation, field interactions do not exist -- each field contributes independently to the hash output. ACCEPTABLE.

**Checklist item**: [x] Combinatorial coverage -- adequate for sequential buffer hash.

---

### 8. Constants Accuracy

| Constant | Comment/Doc | Actual value | Match? |
|----------|------------|-------------|--------|
| 0xFF separator | hash.rs:40: "separator byte (0xFF) that cannot appear in UTF-8" | `buf.push(0xFF)` at lines 45, 47, 49, 51, 53 | YES |
| Seed = 0 | hash.rs:37: "Excludes all wall-clock timestamps (AT-343)" -- (seed mentioned in premortem S4) | `xxh64(&buf, 0)` at line 56 | YES |
| 16-char hex | hash.rs:61: `format!("{hash:016x}")` | Produces 16 hex chars for u64 | YES |

**Checklist item**: [x] Constants accuracy.

---

### 9. Paper Compliance (PRD Claims Match Reality)

| PRD Claim | Reality | Match? |
|-----------|---------|--------|
| "Compute intent_hash from quantized fields only" | `IntentHashInput` uses `qty_steps: i64` and `price_ticks: i64` (quantized integers) | YES |
| "Exclude timestamps" | `IntentHashInput` has no timestamp field. `compute_intent_hash` accesses no clock. | YES |
| `enforcement_point: WAL` | Actual enforcement is the pure function `compute_intent_hash` in `hash.rs`. Not WAL per se. | MISMATCH -- the enforcement point is the hash function itself, not the WAL. WAL uses the hash downstream. PRD metadata is imprecise. |
| `implementation_tests: [test_at218_deterministic_hash]` | 14 tests exist in `test_idempotency.rs`, plus adversarial tests. | UNDERSTATEMENT -- P2 gap (GAP-S2-001-4). |
| `reason_codes: [LabelTooLong]` | `LabelTooLong` is in `label.rs` (S2-002). `hash.rs` produces no reject reasons. | MISMATCH -- GAP-S2-001-5 from R2. |

**Checklist item**: [x] Paper compliance -- 2 mismatches identified (both P2, previously flagged).

---

## Disagreements with R1 Ledger

**None.** All verdicts agree. The R1 ledger is thorough and accurately reflects the implementation.

## Missed Gaps

| Gap ID | Priority | Description | How detected |
|--------|----------|-------------|--------------|
| (none new) | -- | R2 already added GAP-S2-001-5. No additional gaps found during cross-review. | -- |

## Systemic Patterns

For a single-story LOW-risk recon, this section is minimal:

1. **Pure function pattern**: The entire S2-001 story is a pure function. All 6 fail-closed categories are N/A. Trip/non-trip is N/A. The only meaningful proof type is property testing (determinism + sensitivity). This pattern should be formally recognized in the RUNBOOK to reduce ceremony.

2. **PRD metadata drift**: 3 PRD fields for S2-001 have imprecise or incorrect values (`enforcement_point`, `implementation_tests`, `reason_codes`). This suggests PRD metadata for passing stories may not have been updated after implementation.

---

## R3B — External Review Status

**Status**: ATTEMPTED but not executed.

`plans/review_logged.sh` exists on disk. However, running external review tools requires:
1. External tool availability (codex, opus, kimi)
2. Integration branch context for `--base` flag
3. Scope-lock artifact (`.wf/recon_scope_lock/S2-001.scope_lock.json`)

For this dry-run, external tools are not available. This is recorded as friction finding F14.

The R3B gate (`R3_EXTERNAL_C1_COMPLETE`) cannot pass without external review artifacts. For a LOW-risk single-story dry-run, this is not blocking -- the R3A internal cross-review provides sufficient coverage.

---

## Cross-Review Verdict

| AT | R1 Verdict | R3A Verdict | Agreement |
|----|-----------|------------|-----------|
| AT-218 | PROVEN | PROVEN | AGREE |
| AT-343 | PROVEN | PROVEN | AGREE |
| AT-928 | CLAIMED_NOT_PROVEN | CLAIMED_NOT_PROVEN | AGREE |
| AT-201 | CLAIMED_NOT_PROVEN | CLAIMED_NOT_PROVEN | AGREE |

**Story verdict**: PARTIAL (unchanged from R1). Correct assessment given 2/4 ATs are not enforceable within this story's scope.

**Pre-existing citations** (outside recon diff): hash.rs (pre-existing implementation), test_idempotency.rs (pre-existing tests), CONTRACT.md AT-218/AT-343 definitions, adversarial_gi_enforcement.rs (pre-existing adversarial tests). All cited enforcement points and tests predate this recon.
