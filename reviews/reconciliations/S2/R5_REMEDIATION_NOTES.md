# R5 Remediation Notes: S2-001

**Story**: S2-001 -- Compute intent_hash from quantized fields only and exclude timestamps
**Phase**: R5 (Remediation)
**Date**: 2026-02-27
**Author**: claude-opus-4-6 (recon dry-run)

---

## Summary

5 of 7 gaps remediated. 2 deferred to debt register (AT-928 WAL dedup, zero production callers).

| Gap ID | Action | Status |
|--------|--------|--------|
| GAP-S2-001-1 | Removed AT-201 from `enforcing_contract_ats` and `primary_owner_for` in prd.json | FIXED |
| GAP-S2-001-2 | Debt entry (AT-928 WAL dedup is downstream) | DEFERRED |
| GAP-S2-001-3 | Debt entry (zero production callers is a wiring gap for downstream) | DEFERRED |
| GAP-S2-001-4 | Updated `implementation_tests` from 1 to 16 entries in prd.json | FIXED |
| GAP-S2-001-5 | Removed `LabelTooLong` from `reason_codes.values` in prd.json | FIXED |
| GAP-S2-001-6 | Added `test_golden_vector_xxhash64` to test_idempotency.rs | FIXED |
| GAP-S2-001-7 | Added `test_hash_uses_only_canonical_fields` to test_idempotency.rs | FIXED |

---

## Per-Gap Details

### GAP-S2-001-1: AT-201 Misattributed (FIXED)

**What changed**: Removed `"AT-201"` from two arrays in the S2-001 entry of `plans/prd.json`:
- `enforcing_contract_ats`: was `[AT-201, AT-343, AT-928, AT-218]`, now `[AT-343, AT-928, AT-218]`
- `primary_owner_for`: was `[AT-201, AT-218, AT-343]`, now `[AT-218, AT-343]`

**Rationale**: AT-201 is about fail-closed intent classification (unknown action -> OPEN). S2-001 implements hashing, not classification. AT-201 is correctly tested in `test_reject_reason.rs` under a different story.

### GAP-S2-001-4: Implementation Tests Understated (FIXED)

**What changed**: `implementation_tests` in prd.json updated from 1 entry to 16 entries. The full list includes all 14 original tests plus the 2 new tests added in this R5.

**Rationale**: The PRD understated coverage. All 16 tests in `test_idempotency.rs` prove aspects of S2-001's contract implementation.

### GAP-S2-001-5: LabelTooLong Misattributed (FIXED)

**What changed**: `reason_codes.values` set to `[]` in prd.json for S2-001.

**Rationale**: `hash.rs` produces no reject reasons. `LabelTooLong` is defined in `label.rs` and belongs to S2-002.

### GAP-S2-001-6: Golden Vector Test (FIXED)

**What changed**: Added `test_golden_vector_xxhash64` to `crates/soldier_core/tests/test_idempotency.rs`.

**Test details**:
- Uses `sample_input()` (BTC-PERPETUAL, buy, qty_steps=3000, price_ticks=100000, group_id=550e8400-..., leg_idx=0)
- Asserts `compute_intent_hash(&input) == 7_179_042_994_956_709_649_u64`
- Asserts `format_intent_hash(hash) == "63a1159155a6af11"`

**What this catches**: If someone swaps xxhash64 for `DefaultHasher`, xxhash32, or any other hash algorithm, this test fails even though all field-sensitivity and determinism tests would still pass.

**Probe method**: Golden value captured by temporarily adding a panic-printing test, running it, and hardcoding the output.

### GAP-S2-001-7: Non-Canonical Field Exclusion Test (FIXED)

**What changed**: Added `test_hash_uses_only_canonical_fields` to `crates/soldier_core/tests/test_idempotency.rs`.

**Test details**:
- Constructs an `IntentHashInput` struct literal naming all 6 fields (compile-time exhaustiveness proof -- identical mechanism to `test_at343_no_timestamp_field`)
- Asserts `size_of::<IntentHashInput>() == 72` (3 &str x 16 bytes + 2 i64 x 8 bytes + 1 u32 x 4 bytes + 4 padding = 72 bytes on 64-bit)

**Overlap with existing tests**: `test_at343_no_timestamp_field` already proves struct literal exhaustiveness (adding a field breaks compile). The new test adds a second orthogonal check via `size_of` -- if someone adds a field but also updates all struct literals, the size changes and this test catches it. The combination is stronger than either alone.

---

## Test Results

```
running 16 tests
test test_at218_deterministic_hash ... ok
test test_at218_two_codepaths_same_hash ... ok
test test_at343_no_timestamp_field ... ok
test test_at343_no_timestamp_in_hash ... ok
test test_different_group_id_different_hash ... ok
test test_different_instrument_different_hash ... ok
test test_different_leg_idx_different_hash ... ok
test test_different_side_different_hash ... ok
test test_field_boundary_separation ... ok
test test_format_intent_hash_length ... ok
test test_golden_vector_xxhash64 ... ok
test test_hash_nonzero ... ok
test test_hash_uses_only_canonical_fields ... ok
test test_ih16_is_full_hash_hex ... ok
test test_uses_integer_price_ticks ... ok
test test_uses_integer_qty_steps ... ok

test result: ok. 16 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out
```

Zero regressions. All 14 original tests continue to pass. Both new tests pass.

---

## Files Changed

| File | Change | Gap ID |
|------|--------|--------|
| `crates/soldier_core/tests/test_idempotency.rs` | +2 tests (~55 lines) | GAP-6, GAP-7 |
| `plans/prd.json` | AT-201 removed, reason_codes cleared, implementation_tests expanded | GAP-1, GAP-4, GAP-5 |
| `reviews/reconciliations/S2/S2-001_reconciliation.md` | Gap list updated with statuses | (evidence update) |
| `reviews/reconciliations/S2/R5_REMEDIATION_PLAN.md` | New file (remediation plan) | (process artifact) |
| `reviews/reconciliations/S2/R5_REMEDIATION_NOTES.md` | New file (this document) | (process artifact) |
