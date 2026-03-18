---
story_id: S2
slice_id: S2
generated_at: 2026-02-24T23:55:55Z
head_commit: 9ac021f1f0b0cb6f5f9c1575d91e1bde0c25b48e
prompt_style: none
tool: script
model: n/a
cycle: C1
phase_equivalent: R3
review_basis: STORY_SCOPE (Cycle 1)
artifact_provenance: manual
schema_version: review_markdown_header.v1
---

**Review basis**: STORY_SCOPE (Cycle 1)

# Premortem Cross-Review: Agent C
**Reviewing**: S2-000, S2-001, S2-004
**Date**: 2026-02-24

---

## Scoring Summary

| Story | Template | Clause Trace | Assumptions | Failure Modes | Wrong-Impl Gate | Proof Plan | Risk/Cross-story |
|-------|----------|-------------|-------------|---------------|-----------|-------------|
| S2-000 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS-WITH-ISSUES | PASS |
| S2-001 | PASS | PASS | PASS | PASS | PASS | PASS |
| S2-004 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS-WITH-ISSUES | PASS-WITH-ISSUES |

## S2-000 Review
**Story**: S2-000 — Quantization rounding

### Strengths
- Assumption table is unusually complete for a math-heavy story and catches integer/floating-point boundary hazards that can silently destabilize dedup flows.
- Wrong-impl gate includes the capital-superiority class of failures (CLOSE vs OPEN), which is essential for this AT set.
- Proof plan test naming is now concrete and useful for implementation owners.

### Weaknesses
1. **AT-280 causality still depends on inferred function boundaries.** The proof says “separate function in quantize.rs” is chosen, but actual enforcement still needs one explicit contract-point proof path in this story.
2. **Some “debt register items” are broad and could hide implementation risk for close-open semantics.** The close-specific behavior is critical and deserves narrower test definitions in this story if S2-000 remains the gating point.

### Actionable suggestion
- Add one direct causality assertion for AT-280 that proves `reject_reason == ContractsAmountMismatch` and `dispatch_count == 0` in a single test.

---

## S2-001 Review
**Story**: S2-001 — Intent hash from quantized fields

### Strengths
- Good correction of hash-separator framing assumptions and explicit fallback handling for non-ASCII instrument naming.
- Risk upgrade rationale in `§0` is transparent and includes why PRD mismatch is accepted.
- Wrong-impl gate and additional required tests are strong, especially for seed/algorithm and non-canonical field noise.

### Weaknesses
1. **The framing fallback strategy is still partially speculative.** The null-byte choice is justified, but the fallback for non-ASCII naming should include a hard test fixture, not just a “must have” assumption.
2. **Formatting change is partial by design but still leaves old `SS*` tokens in non-target sections.** This is cosmetic but may create reviewer friction and should be linted if consistency is a policy.

### Actionable suggestion
- Add a single fixture-based non-ASCII separator collision test and keep it adjacent to the “separator strategy” decision block to avoid future drift from design intent.

---

## S2-004 Review
**Story**: S2-004 — S2.5 RejectReasonCode registry

### Strengths
- Registry completeness and serialization consistency are the right focus for this foundational contract surface.
- AT-201 scope is appropriately contextualized as both classification and gate wiring.
- The decision not to add catch-all variants is a strong hardening choice.

### Weaknesses
1. **`S2-004-I1` now documents PRD/contract sequencing but proof plan still depends on pipeline presence.** If the pipeline is absent, this story remains partly unproven and could slip into PASS-WITH-ISSUES without explicit blocked follow-up.
2. **Potential ownership conflict in §8: if S2-000 touches some RejectReason variants first, S2-004’s enum authority should be made explicit as the source-of-truth contract registry.** Right now this cross-story coupling can invert if implementation order changes.

### Actionable suggestion
- Add a follow-up assertion in this story’s debt register that any pre-existing variant usage is reconciled to S2-004 as the canonical registry entry point.

## Systemic patterns observed
- Stories that involve shared enums (`IntentHash`, labels, reject reasons) need a stronger “canonical owner + compatibility contract” section to prevent inversion in implementation order.
- Contract-vs-PRD terminology mismatches are the dominant source of ambiguity; explicit “source of truth” lines in each story should be standardized.
- The current cross-review signal is good, but automation for textual consistency (`SSx/§x`) and interface ownership would reduce human-only review load.
