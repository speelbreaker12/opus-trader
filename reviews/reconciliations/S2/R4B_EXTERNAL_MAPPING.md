---
provenance:
  tool: internal
  model: claude-opus-4-6
  prompt_style: none
  cycle: NONE
  phase_equivalent: R4b
  review_basis: "LEAD_SYNTHESIS"
  story_id: S2-001
  slice_id: S2
  head_commit: "1db9c5afaf4da3cfc5d766d94e9004b71a493d75"
  generated_at: "2026-02-27T00:30:00Z"
  artifact_provenance: manual
  schema_version: "phase_mapping.v1"
---

# R4b External Finding Mapping: S2-001

**Purpose**: Map every external review finding to a gap_id or false_positive_justification.
**Gate requirement**: No unmapped P0/P1 findings.

---

## 1. External Source Summary

| Tool | Style | Artifact | Findings |
|------|-------|----------|----------|
| codex | enriched | `codex.enriched.md.digest.md` | 0 (evidence citations only) |
| codex | generic | `codex.generic.md.digest.md` | 0 (evidence citations only) |
| kimi | enriched | `kimi.enriched.md` | 10 findings (2 P2, 1 P2-AT-by-AT, 3 P3, 4 AT assessment notes) |
| kimi | generic | `kimi.generic.md` | 8 findings (1 P1, 4 P2, 3 P3) |
| **Total** | | | **18 findings** |

---

## 2. Mapping Table

### Codex Reviews (0 findings)

Both codex enriched and codex generic produced zero actionable findings. They provided comprehensive evidence citation lists (enforcement points and test locations) but no severity-rated findings. Nothing to map.

### Kimi Enriched Findings (10)

| ID | Severity | Finding | Disposition | Gap / Justification |
|----|----------|---------|-------------|---------------------|
| KIMI-E-1 | P2 | Missing golden vector test | **NEW_GAP** | GAP-S2-001-6 |
| KIMI-E-2 | P2 | Missing non-canonical field exclusion test | **NEW_GAP** | GAP-S2-001-7 |
| KIMI-E-3 | P3 | `intent_hash_ih16` semantics mismatch | FALSE_POSITIVE | xxhash64 = 64 bits = 16 hex chars. ih16 IS the full hash. Naming is accurate. |
| KIMI-E-4 | P3 | Doc mismatch qty_q vs qty_steps | FALSE_POSITIVE | Doc comment explains divergence. Premortem S4 Decision 1 chose integer steps. Correct and documented. |
| KIMI-E-5 | P3 | No observability on hash computation | FALSE_POSITIVE | Pure function, no failure modes. No AT requires hash observability. Nice-to-have only. |
| KIMI-E-6 | P2 | AT-201 should be contextual | DUPLICATE | -> GAP-S2-001-1 (from R1) |
| KIMI-E-7 | P2 | AT-343 partial (cross-restart + non-canonical) | SPLIT | -> GAP-S2-001-6 + GAP-S2-001-7. Cross-restart deferred per premortem. |
| KIMI-E-8 | P2 | AT-218 partial (codepath test weak) | FALSE_POSITIVE | Test directly implements AT-218 spec. Two independent struct constructions with same fields. R1 PROVEN verdict stands. |
| KIMI-E-9 | N/A | AT-928 no WAL implementation | DUPLICATE | -> GAP-S2-001-2 (from R1) |
| KIMI-E-10 | P2 | Wrong-impl gates: multiple S5 gaps | DUPLICATE | -> GAP-S2-001-6 (golden vector catches all listed wrong impls) |

### Kimi Generic Findings (8)

| ID | Severity | Finding | Disposition | Gap / Justification |
|----|----------|---------|-------------|---------------------|
| KIMI-G-1 | **P1** | Missing input validation for negative qty/prices | FALSE_POSITIVE | Hash is pure computation for all i64 values. Negative validation is upstream (S2-000 quantization). Hash should not reject inputs. R1 Section 5 correctly classified as N/A. |
| KIMI-G-2 | P2 | test_at343_no_timestamp_field is fragile | FALSE_POSITIVE | Struct literal exhaustiveness is a standard Rust pattern. Adding Option<Instant> with default still fails compilation (Rust requires all fields in struct literals). Not fragile. |
| KIMI-G-3 | P2 | Missing hash collision resistance test | FALSE_POSITIVE | Collision resistance is intrinsic to xxhash64. test_field_boundary_separation proves concatenation strategy is sound. Unbounded requirement not in any AT. |
| KIMI-G-4 | P2 | Buffer pre-allocation wasteful | FALSE_POSITIVE | Code quality, not contract. 128 vs 96 bytes has zero safety impact. |
| KIMI-G-5 | P2 | No validation of side field values | FALSE_POSITIVE | Hash accepts any &str. Input validation is caller responsibility. API design improvement, not contract gap. |
| KIMI-G-6 | P3 | ih16 naming misleading | DUPLICATE | -> KIMI-E-3 (same finding, already false positive) |
| KIMI-G-7 | P3 | Missing separator documentation | FALSE_POSITIVE | 0xFF separator documented inline at hash.rs:40. Test exists. Minor doc improvement only. |
| KIMI-G-8 | P3 | crate_bootstrapped() placeholder | FALSE_POSITIVE | Out of scope for S2-001. Predates idempotency module. |

---

## 3. Disposition Summary

| Disposition | Count |
|-------------|-------|
| **NEW_GAP** | 2 (GAP-S2-001-6, GAP-S2-001-7) |
| **DUPLICATE_OF_INTERNAL** | 4 (mapped to GAP-S2-001-1, -2, -6) |
| **FALSE_POSITIVE** | 12 |
| **Total** | 18 |

**Unmapped P0 findings**: 0
**Unmapped P1 findings**: 0 (KIMI-G-1 was the only P1 -- dispositioned as false positive with justification)

---

## 4. Lead Decision on KIMI-G-1 (P1 Downgrade)

**Finding**: Kimi generic rated "missing input validation for negative quantities/prices" as P1.

**Lead decision**: FALSE_POSITIVE.

**Rationale**: The hash function's contract is to deterministically hash any valid `IntentHashInput`. The struct fields (`i64`) are the correct type -- they represent the full range of quantized values. Negative validation is the responsibility of the upstream quantization layer (S2-000, specifically `quantize.rs`). Rejecting negative values in the hash function would violate the principle that a pure hash function should be total (defined for all inputs). The R1 evidence ledger Section 5 (Fail-Closed) explicitly analyzed negative values and correctly classified them as N/A for this pure function.

This is a responsibility-boundary disagreement, not a missed finding.

---

## 5. Gate Check Status

| Gate ID | Status | Notes |
|---------|--------|-------|
| `R4B_ALL_FINDINGS_MAPPED` | **PASS** | All 18 findings have gap_id or false_positive_justification |
| `R4B_NO_UNMAPPED_P0_P1` | **PASS** | 0 unmapped P0/P1 findings |
