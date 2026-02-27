---
provenance:
  tool: internal
  model: claude-opus-4-6
  phase_equivalent: R2
  review_basis: "LEAD_REVIEW"
  story_id: S2-001
  slice_id: S2
  head_commit: "a106eb983ee2d744e3a3f94eddf2b3f39de1a43d"
  generated_at: "2026-02-26T23:15:00Z"
  schema_version: "lead_eval_sidecar.v1"
---

# R2 Lead Evaluation: S2-001

**Review basis**: LEAD_REVIEW (Evidence Ledger QA)
**Scope**: S2-001 evidence ledger (`S2-001_reconciliation.md` + `S2-001_reconciliation.json`)

---

## 1. Citation Spot-Checks (3 performed)

### Check 1: `IntentHashInput` struct at hash.rs:16-29

**Ledger claim** (Section 2, row 1): "Type system enforces: fields are `i64` and `u32`, not `f64`."

**Verified**: hash.rs lines 16-29 define `IntentHashInput<'a>` with fields:
- `instrument: &'a str`
- `side: &'a str`
- `qty_steps: i64`
- `price_ticks: i64`
- `group_id: &'a str`
- `leg_idx: u32`

**Result**: CORRECT. No `f64` fields. No timestamp fields. Line numbers accurate.

### Check 2: `test_at218_deterministic_hash` at test_idempotency.rs:26

**Ledger claim** (Section 3, row 1): "Same input -> same hash (determinism)."

**Verified**: test_idempotency.rs line 26 defines `test_at218_deterministic_hash`. Lines 27-30: constructs `sample_input()`, calls `compute_intent_hash` twice, asserts `h1 == h2`.

**Result**: CORRECT. Line number, test name, and proof description are all accurate.

### Check 3: `xxh64(&buf, 0)` at hash.rs:56

**Ledger claim** (Section 6, S4 Decisions table): "xxh64(&buf, 0) at hash.rs:56"

**Verified**: hash.rs line 56 contains `xxh64(&buf, 0)`. Seed is 0. Algorithm is xxhash64 via `xxhash_rust::xxh64::xxh64`.

**Result**: CORRECT.

### Check 4: `pub mod idempotency` at lib.rs:4

**Ledger claim** (Section 2, row 7): "Module declared at crate root."

**Verified**: lib.rs line 4 is `pub mod idempotency;`.

**Result**: CORRECT.

**Citation accuracy summary**: 4/4 citations verified as accurate and relevant. No inaccurate or stale line references found.

---

## 2. Verdict Re-Calibration

| AT | R1 Verdict | R2 Verdict | Changed? | Rationale |
|----|-----------|-----------|----------|-----------|
| AT-218 | PROVEN | PROVEN | NO | Strong property tests + 6 field-sensitivity tightening tests. Pure function with no hidden state. The combination of determinism tests and field-sensitivity tests blocks all plausible wrong implementations. |
| AT-343 | PROVEN | PROVEN | NO | Compile-time structural proof (struct exhaustiveness) is the strongest possible proof for "no timestamp field." Runtime test is supplementary. |
| AT-928 | CLAIMED_NOT_PROVEN | CLAIMED_NOT_PROVEN | NO | Correctly identified as out of scope. S2-001 provides a prerequisite (hash function) but does not implement WAL dedup. |
| AT-201 | CLAIMED_NOT_PROVEN | CLAIMED_NOT_PROVEN | NO | Correctly identified as misattributed. AT-201 is about intent classification, confirmed at CONTRACT.md line 106-109 and tested in `test_reject_reason.rs:262`. |

**No verdict changes required.**

---

## 3. Escalation Rule Validation

**Rule**: WEAK_PROOF on MED/HIGH ATs should escalate to CLAIMED_NOT_PROVEN.

**Check**: No ATs have WEAK_PROOF verdict. The two non-proven ATs (AT-928, AT-201) are already CLAIMED_NOT_PROVEN. Risk is LOW for this story. No escalation needed.

**Result**: PASS -- no escalation rules triggered.

---

## 4. Gap Re-Classification

| Gap ID | R1 Priority | R2 Priority | Changed? | Rationale |
|--------|------------|------------|----------|-----------|
| GAP-S2-001-1 | P2 | P2 | NO | AT-201 misattribution is PRD metadata only. No safety impact. |
| GAP-S2-001-2 | P1 | P1 | NO | AT-928 WAL dedup is genuinely important but correctly deferred to downstream story. P1 is appropriate -- it requires tracking and a debt owner. |
| GAP-S2-001-3 | P2 | P2 | NO | Zero production callers is expected for a building-block story. The function is tested and exported. Integration is downstream. |
| GAP-S2-001-4 | P2 | P2 | NO | PRD understating test count is cosmetic. No safety impact. |

**No re-classifications needed.**

### New Gap Identified

| Gap ID | Priority | AT | Description | Recommended action |
|--------|----------|-----|-------------|-------------------|
| GAP-S2-001-5 | P2 | -- | PRD `reason_codes` for S2-001 lists `LabelTooLong`, but `LabelTooLong` is defined in `label.rs` (S2-002's domain). S2-001's `hash.rs` does not produce any reject reasons. This is a PRD metadata error. | Remove `LabelTooLong` from S2-001's `reason_codes` or leave empty. |

---

## 5. Cross-Story Inconsistency

N/A -- single-story recon.

---

## 6. Red Flag Scan

| # | Check | Result |
|---|-------|--------|
| 1 | PROVEN with no file:line? | NO -- both PROVEN ATs (AT-218, AT-343) have file:line citations in the ledger Section 2 and the JSON sidecar `enforcement_file`/`enforcement_line` fields. |
| 2 | PROVEN on S5 wrong-impl without tightening test? | NO -- AT-218's "constant hash" wrong impl is blocked by 6 field-sensitivity tests. AT-343's "timestamp normalization" wrong impl is blocked by `test_at343_no_timestamp_field` (struct exhaustiveness). Both have tightening tests. |
| 3 | WEAK_PROOF treated as PROVEN? | NO -- no WEAK_PROOF verdicts in the ledger. |
| 4 | PROVEN verdict with only 1 test? | MARGINAL -- AT-343 has 2 proving tests and 0 tightening tests, but the compile-time proof (`test_at343_no_timestamp_field`) is strong enough alone. Not a red flag. |

**No red flags found.**

---

## 7. Correction Requests

**None required.** The R1 evidence ledger is accurate, well-cited, and correctly calibrated.

One minor improvement suggestion (not blocking): Add GAP-S2-001-5 (LabelTooLong reason_codes misattribution) to the gap list. This is a P2 cosmetic finding discovered during R2.

---

## 8. Overall Rating

| Story | Rating | Rationale |
|-------|--------|-----------|
| S2-001 | **PASS_WITH_ISSUES** | Ledger is thorough and accurate. 2/4 ATs are PROVEN with strong evidence. 2/4 ATs are correctly identified as CLAIMED_NOT_PROVEN with clear debt tracking. One new P2 gap found (PRD reason_codes). No blocking issues. |

**Lead decision**: ACCEPTED -- proceed to R3 without returning to R1.
