---
provenance:
  tool: internal
  model: claude-opus-4-6
  prompt_style: none
  cycle: NONE
  phase_equivalent: R4
  review_basis: "LEAD_SYNTHESIS"
  story_id: S2-001
  slice_id: S2
  head_commit: "1db9c5afaf4da3cfc5d766d94e9004b71a493d75"
  generated_at: "2026-02-27T00:30:00Z"
  artifact_provenance: manual
  schema_version: "gap_list.v1"
---

# R4 Synthesis + Gap List: S2-001

**Review basis**: LEAD_SYNTHESIS (Deterministic Aggregation)
**Story**: S2-001 -- Compute intent_hash from quantized fields only and exclude timestamps
**Sources**: R1 evidence ledger, R2 lead eval, R3A cross-review, R3B external (codex enriched + generic, kimi enriched + generic)

---

## 1. Source Inventory

| Phase | Artifact | Gaps Contributed | Notes |
|-------|----------|-----------------|-------|
| R1 | `S2-001_reconciliation.json` | GAP-S2-001-1, -2, -3, -4 | 4 gaps from initial read-only audit |
| R2 | `R2_LEAD_EVAL.json` | GAP-S2-001-5 | 1 new gap (LabelTooLong reason_codes) |
| R3A | `R3_RECONCILE_REVIEW_by_AGENT.json` | (none new) | Confirmed all R1/R2 gaps |
| R3B-codex-enriched | `codex.enriched.md.digest.md` | (none) | No P0/P1/P2 findings. Evidence citations only. |
| R3B-codex-generic | `codex.generic.md.digest.md` | (none) | No P0/P1/P2 findings. Evidence citations only. |
| R3B-kimi-enriched | `kimi.enriched.md` | GAP-S2-001-6, -7 | 2 NEW P2 gaps (golden vector, non-canonical field test). Also confirmed AT-201/AT-928 gaps from R1. |
| R3B-kimi-generic | `kimi.generic.md` | (none) | P1 input validation downgraded (upstream responsibility). P2s either duplicates or code-quality (not contract). |

---

## 2. Deduplication Log

**Duplicates found**: 6
**Merges performed**: 5

| External Finding | Action | Rationale |
|-----------------|--------|-----------|
| kimi-enriched: AT-201 should be contextual | Merged into GAP-S2-001-1 | Identical to R1 finding. Added R3B-kimi-enriched to `confirmed_by`. |
| kimi-enriched: AT-928 no WAL implementation | Merged into GAP-S2-001-2 | Identical to R1 finding. Added R3B-kimi-enriched to `confirmed_by`. |
| kimi-enriched: AT-343 partial (golden vector + non-canonical) | Split into GAP-S2-001-6 and GAP-S2-001-7 | Golden vector and non-canonical exclusion are distinct test gaps. Cross-restart deferred per premortem (S6-001). |
| kimi-enriched: AT-218 partial (not truly different codepaths) | False positive | test_at218_two_codepaths_same_hash directly implements AT-218 spec. R1 verdict PROVEN stands. |
| kimi-generic: P1 negative qty/prices validation | False positive | Hash function is pure computation. Negative validation is upstream quantization layer (S2-000). |
| kimi-generic: P2 ih16 naming misleading | Duplicate of kimi-enriched P3 | Same finding at lower severity. Not a contract gap. |

---

## 3. Gap List (Final)

### P1 Gaps (1)

#### GAP-S2-001-2 | P1 | AT-928 | MISSING_ENFORCEMENT

**Description**: AT-928 WAL dedup not enforceable by S2-001. S2-001 provides the hash function prerequisite but does not implement WAL lookup/NOOP logic. No end-to-end dedup test exists within S2-001 scope.

**Source**: R1 | **Confirmed by**: R2, R3A, R3B-kimi-enriched

**Action**: Verify AT-928 is owned and tested in the WAL integration story. If no story owns AT-928, create debt entry with owner assignment.

**Code change required**: No
**Debt entry**: YES (see DEBT_REGISTER.json, DEBT-S2-001)

---

### P2 Gaps (6)

#### GAP-S2-001-1 | P2 | AT-201 | PRD_METADATA_ERROR

**Description**: AT-201 misattributed to S2-001. AT-201 is about intent classification (unknown action -> OPEN), not hashing. AT-201 is tested in `test_reject_reason.rs` under a different story.

**Source**: R1 | **Confirmed by**: R2, R3A, R3B-kimi-enriched

**Action**: Remove AT-201 from S2-001 `enforcing_contract_ats` in `plans/prd.json`.

**Code change required**: No (PRD metadata fix only)

---

#### GAP-S2-001-3 | P2 | N/A | WIRING_GAP

**Description**: `compute_intent_hash` has zero production callers in `src/`. The function is defined, exported, and thoroughly tested, but not called from any production code path. PROVEN-UNIT, not PROVEN-INTEGRATED.

**Source**: R1 | **Confirmed by**: R2, R3A

**Action**: Verify a downstream story (label generation, WAL integration) calls `compute_intent_hash` from production code. Document the expected integration point.

**Code change required**: No (downstream integration story responsibility)
**Debt entry**: YES (see DEBT_REGISTER.json, DEBT-S2-002)

---

#### GAP-S2-001-4 | P2 | AT-218 | PRD_METADATA_ERROR

**Description**: PRD `implementation_tests` lists only 1 test (`test_at218_deterministic_hash`) but 14 tests exist in `test_idempotency.rs` plus adversarial tests. The PRD understates coverage.

**Source**: R1 | **Confirmed by**: R2

**Action**: Update PRD `implementation_tests` to list all proving tests, or document that `test_idempotency.rs` is the proving suite.

**Code change required**: No (PRD metadata fix only)

---

#### GAP-S2-001-5 | P2 | N/A | PRD_METADATA_ERROR

**Description**: PRD `reason_codes` for S2-001 lists `LabelTooLong`, but `LabelTooLong` is defined in `label.rs` (S2-002 domain). S2-001's `hash.rs` does not produce any reject reasons.

**Source**: R2 | **Confirmed by**: R3A

**Action**: Remove `LabelTooLong` from S2-001 `reason_codes` in `plans/prd.json` (or set to empty).

**Code change required**: No (PRD metadata fix only)

---

#### GAP-S2-001-6 | P2 | AT-343 | MISSING_TEST (NEW from R3B)

**Description**: No golden vector test exists to anchor the hash algorithm as xxhash64 with seed=0. A wrong implementation using `std::collections::hash_map::DefaultHasher`, xxhash32, or any other deterministic hash would pass all current tests. Premortem S5 (FM-6, FM-7) identified this gap and S6 proof plan calls for a golden vector test.

**Source**: R3B-kimi-enriched

**Action**: Add `test_golden_vector_xxhash64`: compute hash of known input, assert it matches a pre-computed xxhash64 reference value. This anchors the algorithm choice.

**Code change required**: No
**Test change required**: Yes (`crates/soldier_core/tests/test_idempotency.rs`)

---

#### GAP-S2-001-7 | P2 | AT-343 | MISSING_TEST (NEW from R3B)

**Description**: No explicit test verifies the hash ignores non-canonical fields. While the struct type system provides compile-time enforcement (`IntentHashInput` has exactly 6 fields), no test documents that `strat_id`, `reduce_only`, `exchange_name`, etc. are excluded. Adding such fields to the struct would silently change hash behavior without failing any existing test except the struct exhaustiveness test.

**Source**: R3B-kimi-enriched

**Action**: Add `test_hash_ignores_non_canonical_fields`: compile-time assertion that `IntentHashInput` has exactly the 6 canonical fields. Alternatively, document the existing `test_at343_no_timestamp_field` as the canonical-field gate (it already uses struct literal exhaustiveness).

**Code change required**: No
**Test change required**: Yes (`crates/soldier_core/tests/test_idempotency.rs`)

---

## 4. Priority Summary

| Priority | Count | Code Changes | Test Changes | PRD Fixes | Debt Entries |
|----------|-------|-------------|-------------|-----------|-------------|
| P0 | 0 | 0 | 0 | 0 | 0 |
| P1 | 1 | 0 | 0 | 0 | 1 |
| P2 | 6 | 0 | 2 | 3 | 1 |
| **Total** | **7** | **0** | **2** | **3** | **2** |

**Key observation**: The 2 new gaps from external reviews (GAP-S2-001-6 and GAP-S2-001-7) are the only findings that require test changes. Both are test-tightening gaps identified by the premortem S5/S6 proof plan but not yet implemented. All other gaps are metadata corrections or debt tracking.

---

## 5. Systemic Patterns

1. **PRD metadata drift**: 3 of 7 gaps are PRD metadata errors (misattributed ATs, understated test lists, wrong reason_codes). This suggests PRD entries for Slice 2 passing stories were not reconciled against implementation after the code was written.

2. **Building-block wiring gap**: GAP-S2-001-3 (zero production callers) is expected for a building-block story. The function is correctly tested in isolation. Wiring is a downstream story's responsibility. This pattern should be formally recognized so future building-block stories can preemptively declare PROVEN-UNIT with a debt entry pointing at the integration story.

3. **Premortem S5/S6 proof plan debt**: GAP-S2-001-6 and GAP-S2-001-7 are test gaps that were predicted by the premortem (S5 wrong-impl traps, S6 proof plan) but not implemented. This is a pattern where the premortem correctly identifies needed tests, the tests are not written during implementation, and external review independently rediscovers the same gaps. The premortem S6 proof plan should be treated as a checklist during implementation.

---

## 6. Gate Check Status

| Gate ID | Status | Notes |
|---------|--------|-------|
| `R4_GAP_LIST_COMPLETE` | PASS | GAP_LIST.md and GAP_LIST.json both exist; S2-001 has gap entries; all R3B external findings accounted for |
| `R4_NO_UNCHECKED_CLEAN_REVIEW` | PASS | Story has gaps; no coverage_proof needed |
| `R4_DEBT_DRAFT_COMPLETE` | PASS | Debt entries for GAP-S2-001-2 and GAP-S2-001-3 exist in DEBT_REGISTER.json |
