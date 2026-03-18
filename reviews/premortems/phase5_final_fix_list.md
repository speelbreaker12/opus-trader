---
story_id: S2
slice_id: S2
generated_at: 2026-02-24T23:55:55Z
head_commit: 9ac021f1f0b0cb6f5f9c1575d91e1bde0c25b48e
prompt_style: none
tool: script
model: n/a
cycle: C1
phase_equivalent: R5
review_basis: STORY_SCOPE (Cycle 1)
artifact_provenance: manual
schema_version: review_markdown_header.v1
---

**Review basis**: STORY_SCOPE (Cycle 1)

# Phase 5 — Synthesis: Final Fix List

**Slice**: S2 (Stories S2-000 through S2-004)
**Date**: 2026-02-24
**Input**: 3 cross-review agents (A, B, C), 5 revised premortems
**Head commit**: `9ac021f`

---

## Cross-Review Agreement

| Story | Agent A | Agent B | Agent C | Consensus |
|-------|---------|---------|---------|-----------|
| S2-000 | ACCEPT-WITH-MERIT | ACCEPT-WITH-MERIT | ACCEPT-WITH-MERIT | ACCEPT-WITH-MERIT |
| S2-001 | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES |
| S2-002 | PASS | PASS | PASS | PASS |
| S2-003 | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES |
| S2-004 | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES | PASS-WITH-ISSUES |

### Rating Disagreements (>1 level)

No >1-level verdict disagreements after cross-review. Remaining findings are scoped to follow-up clarifications and are actionable in the next phase.

---

## MUST_FIX (Blocking or Safety-Critical)

| # | Finding | Story | Source | Target | Suggested Owner |
|---|---------|-------|--------|--------|----------------|
| M-1 | Resolve AT-280 enforcement provenance and causality in one concrete place (quantize path vs separate validator). | S2-000 | Agent A/B | Lock AT-280 proof to either `validate_units_consistency()` in `quantize.rs` or explicit defer statement with owner. | S2-000 implementer |
| M-2 | Add required contract-vs-PRD separator test for non-ASCII fields in `§2` assumption 3. | S2-001 | Agent A/C | Add fixture that forces non-ASCII instrument through hash framing path and asserts fallback behavior is tested and non-lossy. | S2-001 implementer |
| M-3 | Enforce canonical owner check that parsing label strings occurs only via S2-002 parser API (static check). | S2-002 / S2-003 | Agent A/B | Prevent silent drift where other modules build `s4:` labels differently. | S2-002 owner (+ S2-003 for parser callsite) |
| M-4 | Add explicit test for zero-match tie-breaker handling (`ih16`/`instrument`/`side` chain fallback semantics) under live matcher state. | S2-003 | Agent A/C | Ensure ambiguous-order policy is deterministic and aligns with written `Decision 3` semantics. | S2-003 implementer |

---

## SHOULD_FIX (High-value clarifications)

| # | Finding | Story | Source | Target | Suggested Owner |
|---|---------|-------|--------|--------|----------------|
| S-1 | Remove remaining legacy `SSx`/`§x` mixture in S2-001 exit criteria and references for consistency. | S2-001 | Agent A/C | Documentation consistency only; no runtime impact. | S2-001 |
| S-2 | Add negative test that unknown PRD-internal codes (`UnknownActionClassifiedOpen`, `RejectReasonRegistryMissing`) are not emitted as primary reject reasons. | S2-004 | Agent B | Tighten reject-reason invariants and preserve contract-only primary codes. | S2-004 |
| S-3 | Explicitly test the “only 30 values” registry claim against a hardcoded contract token list in all enum-completeness tests. | S2-004 | Agent B/C | Reduce false pass from overbroad token checks. | S2-004 |
| S-4 | Add NoMatch/empty-candidate fixture in S2-002 + S2-003 interface test to prove caller path semantics for ghost labels. | S2-002/003 | Agent B/C | Shared caller/parser boundary clarity. | S2-003 |

---

## NICE_TO_HAVE

| # | Finding | Story | Source | Target | Suggested Owner |
|---|---------|-------|--------|--------|----------------|
| N-1 | Add an automated grep/regex lint for `s4:` formatting to avoid future parser/schema drift. | S2-002 | Agent B | CI-level maintainability improvement. | S2-002 |
| N-2 | Add a deterministic test that verifies `qty_steps`/`price_ticks` usage in `intent_hash` cannot silently regress to float bytes. | S2-001 | Agent C | Backstop against accidental refactor. | S2-001 |
| N-3 | Add a short interface contract section in S2-000 and S2-004 explicitly documenting cross-story enum/field ownership at compile-time boundaries. | S2-000/004 | Agent A/B | Prevent order-dependent story coupling. | S2-000 + S2-004 |

---

## Open risk count

- **MUST_FIX open**: 4
- **SHOULD_FIX open**: 4
- **NICE_TO_HAVE open**: 3

Next: Phase 6 — Final Patch (Round 2) if these must-fix items are accepted.
