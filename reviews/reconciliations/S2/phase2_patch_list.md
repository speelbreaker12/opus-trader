# Phase 2 Patch List — S2 Premortems

> Generated: 2026-02-24 | Evaluator: Lead | Phase: 2 (Lead Evaluation)

## Summary

| Story | Rating | Issues | Med | Low | Info |
|-------|--------|--------|-----|-----|------|
| S2-000 | PASS-WITH-ISSUES | 1 | 0 | 1 | 0 |
| S2-001 | PASS-WITH-ISSUES | 3 | 0 | 3 | 0 |
| S2-002 | PASS | 0 | 0 | 0 | 1 |
| S2-003 | PASS-WITH-ISSUES | 2 | 1 | 1 | 0 |
| S2-004 | PASS-WITH-ISSUES | 2 | 1 | 1 | 0 |
| **Total** | | **8** | **2** | **6** | **1** |

No NEEDS-PATCH or REJECT ratings. All issues are surgical fixes (<30% section change). Proceed to Phase 3.

---

## Patches Required

### S2-000 (Batch 1)

**S2-000-I1** [DEPTH_GAP, low] — §6 proof plan missing AT-280 row
- Add proof plan row for AT-280 with TRIP/NON-TRIP tests
- Specify concrete NON-TRIP test names for AT-926, AT-219, AT-908

### S2-001 (Batch 2)

**S2-001-I1** [FORMATTING, low] — SS→§ notation
- Replace `SS0`→`§0`, `SS1`→`§1`, `SS4`→`§4`, `SS5`→`§5` throughout

**S2-001-I2** [LOGIC_GAP, low] — Risk rating divergence from PRD
- Add note in §0: "PRD rates this LOW; elevated to MED because idempotency/persistence boundary — hash non-determinism causes silent duplicate dispatch. PRD should be updated if this assessment is accepted."

**S2-001-I3** [FACTUAL_ERROR, low] — Null-byte separator assumption
- Add to §2 assumption table: null-byte safety depends on Deribit ASCII instrument names. Flag fallback to length-prefix framing if non-ASCII instruments appear.

### S2-002 (Batch 3)

No patches required. (Info-level note on sid8 encoding already handled as assumption-to-validate.)

### S2-003 (Batch 3)

**S2-003-I1** [FACTUAL_ERROR, med] — qty_q tie-breaker source
- In §2 Assumption 4 and §4 Decision 4, add explicit note: "qty_q as tie-breaker D is from PRD acceptance criteria, NOT from CONTRACT.md §1.1.2 (which lists only ih16, instrument, side). Consider amending contract or removing qty_q from chain."

**S2-003-I2** [DEPTH_GAP, low] — FM-2 forced-order test clarity
- Revise §5 wrong-impl row 2 test case to show an outcome difference (not just path difference) from wrong ordering.

### S2-004 (Batch 1)

**S2-004-I1** [LOGIC_GAP, low] — S2-003 dependency rationale
- Clarify §2 Assumption 3: dependency on S2-003 is PRD ordering, not technical. Classifier is independent of label matching.

**S2-004-I2** [FACTUAL_ERROR, med] — Registry count "24 values"
- Verify exact count against CONTRACT.md §2.2.6. Update assumption and test assertion to match verified count.

---

## Phase 3 Instructions

All patches are surgical (<30% section change). No escalation needed.

- **Batch 1 (S2-000, S2-004)**: 3 patches
- **Batch 2 (S2-001)**: 3 patches
- **Batch 3 (S2-002, S2-003)**: 2 patches

Phase 3 can be parallelized by batch — each batch's original writer applies their patches.
