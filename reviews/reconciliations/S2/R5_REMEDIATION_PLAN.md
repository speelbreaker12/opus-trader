# R5 Remediation Plan: S2-001

**Story**: S2-001 -- Compute intent_hash from quantized fields only and exclude timestamps
**Phase**: R5 (Remediation)
**Date**: 2026-02-27
**Source**: `reviews/reconciliations/S2/GAP_LIST.json` (7 gaps total)

---

## Scope Summary

| Category | Count | Gaps |
|----------|-------|------|
| Test additions | 2 | GAP-6, GAP-7 |
| PRD metadata fixes | 3 | GAP-1, GAP-4, GAP-5 |
| Deferred (debt) | 2 | GAP-2, GAP-3 |
| **Total actionable** | **5** | |

---

## GAP-S2-001-1: AT-201 Misattributed (PRD Metadata)

- **Priority**: P2
- **Description**: AT-201 (fail-closed intent classification) is about classifying unknown actions as OPEN, not about hashing. It does not belong in S2-001's `enforcing_contract_ats`.
- **Planned change**: Remove `"AT-201"` from `enforcing_contract_ats` array and `primary_owner_for` array in `plans/prd.json` for the S2-001 entry.
- **Target file**: `plans/prd.json` lines 1968-1973 (enforcing_contract_ats), lines 1990-1994 (primary_owner_for)
- **Expected assertion**: `jq '.items[] | select(.id == "S2-001") | .enforcing_contract_ats' plans/prd.json` should NOT contain `AT-201`.

## GAP-S2-001-4: Implementation Tests Understated (PRD Metadata)

- **Priority**: P2
- **Description**: PRD `implementation_tests` lists only 1 test (`test_at218_deterministic_hash`) but 14 tests exist in `test_idempotency.rs`. After this R5, there will be 16 total (14 existing + 2 new).
- **Planned change**: Replace the single-entry `implementation_tests` with the full list of all tests in `test_idempotency.rs`.
- **Target file**: `plans/prd.json` lines 1987-1989
- **Expected assertion**: `jq '.items[] | select(.id == "S2-001") | .implementation_tests | length' plans/prd.json` should be >= 16.

## GAP-S2-001-5: LabelTooLong Reason Code Misattributed (PRD Metadata)

- **Priority**: P2
- **Description**: `reason_codes` lists `LabelTooLong`, but `hash.rs` produces no reject reasons. `LabelTooLong` belongs to S2-002 (label.rs domain).
- **Planned change**: Set `reason_codes.values` to empty array `[]` for S2-001 in `plans/prd.json`.
- **Target file**: `plans/prd.json` lines 1974-1979
- **Expected assertion**: `jq '.items[] | select(.id == "S2-001") | .reason_codes.values | length' plans/prd.json` should be 0.

## GAP-S2-001-6: Golden Vector Test (Test Addition)

- **Priority**: P2
- **Description**: No test pins the hash output to a known xxhash64 reference value. A wrong algorithm (e.g., `DefaultHasher`, xxhash32) would pass all existing tests because they only check determinism and field sensitivity, not absolute output.
- **Planned change**: Add `test_golden_vector_xxhash64` to `test_idempotency.rs`. Uses `sample_input()` (the standard test fixture), asserts `compute_intent_hash(&sample_input()) == 7179042994956709649_u64` and `format_intent_hash(hash) == "63a1159155a6af11"`.
- **Target file**: `crates/soldier_core/tests/test_idempotency.rs` (append after existing tests)
- **Expected assertion**: `assert_eq!(hash, 7179042994956709649_u64)` and `assert_eq!(hex, "63a1159155a6af11")`.
- **Probe result**: Ran `compute_intent_hash(&sample_input())` and captured: `u64=7179042994956709649`, `hex=63a1159155a6af11`.

## GAP-S2-001-7: Non-Canonical Field Exclusion Test (Test Addition)

- **Priority**: P2
- **Description**: No explicit test documents that only the 6 canonical fields (`instrument`, `side`, `qty_steps`, `price_ticks`, `group_id`, `leg_idx`) participate in the hash. The existing `test_at343_no_timestamp_field` partially covers this (struct exhaustiveness), but it only proves there is no *timestamp* field. A dedicated test should prove the struct has exactly 6 fields.
- **Overlap assessment**: `test_at343_no_timestamp_field` proves that adding ANY new field to `IntentHashInput` would break compilation (struct literal without the new field won't compile). This is already a strong exclusion gate. However, it does not explicitly enumerate the 6 canonical fields. The new test adds documentation value and a `std::mem::size_of` or field-count assertion.
- **Planned change**: Add `test_hash_uses_only_canonical_fields` to `test_idempotency.rs`. This test:
  1. Constructs an `IntentHashInput` with all 6 fields (compile-time proof of field set).
  2. Asserts `std::mem::size_of::<IntentHashInput>()` equals the expected size (proving no hidden fields exist beyond the 6 declared ones).
  3. Documents the 6 canonical fields by name in the test docstring.
- **Target file**: `crates/soldier_core/tests/test_idempotency.rs` (append after golden vector test)
- **Expected assertion**: `assert_eq!(std::mem::size_of::<IntentHashInput>(), EXPECTED_SIZE)` where EXPECTED_SIZE is computed from the actual struct layout.

## GAP-S2-001-2: AT-928 WAL Dedup (DEFERRED)

- **Priority**: P1
- **Action**: Debt entry. AT-928 enforcement is downstream (WAL integration story). No change in this R5.

## GAP-S2-001-3: Zero Production Callers (DEFERRED)

- **Priority**: P2
- **Action**: Debt entry. Wiring to production callers is a downstream story. No change in this R5.

---

## Execution Order

1. Add golden vector test (GAP-6) -- capture value first, then pin
2. Add non-canonical field test (GAP-7) -- compute expected size, then assert
3. Run tests to verify both new tests pass alongside all 14 existing tests
4. Apply PRD metadata fixes (GAP-1, GAP-4, GAP-5) in prd.json
5. Update evidence ledger with FIXED citations
6. Write R5_REMEDIATION_NOTES.md
