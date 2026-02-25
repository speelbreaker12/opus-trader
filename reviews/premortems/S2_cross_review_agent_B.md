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

# Premortem Cross-Review: Agent B
**Reviewing**: S2-000, S2-002, S2-003, S2-004
**Date**: 2026-02-24

---

## Scoring Summary

| Story | Template | Clause Trace | Assumptions | Failure Modes | Wrong-Impl Gate | Proof Plan | Risk/Cross-story |
|-------|----------|-------------|-------------|---------------|-----------|-------------|
| S2-000 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS-WITH-ISSUES | PASS |
| S2-002 | PASS | PASS | PASS | PASS | PASS | PASS |
| S2-003 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS | PASS-WITH-ISSUES |
| S2-004 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS-WITH-ISSUES | PASS |

## S2-000 Review
**Story**: S2-000 — Quantization rounding

### Strengths
- `§5` correctly catches precision and edge-case numeric errors that are easy to miss in quantization logic.
- Added AT-280 proof plan row in `§6` with explicit TRIP/NON-TRIP names, addressing the phase-2 flagged gap cleanly.
- STOPLIGHT and debt register are honest about the scope gap around where AT-280 is enforced.

### Weaknesses
1. **AT-280 placement remains ambiguous in implementation context.** The story still lists AT-280 with a “separate validate function” intention but keeps this as a claim debt item. For implementation readiness, the proof should assert a precise enforcement point (or explicitly remove AT-280 from enforcing claims).
2. **Cross-story dependency assumptions are not yet tied to concrete test names.** The assumption that S2-001 consumes `qty_steps`/`price_ticks` is critical and should be reflected as an explicit compile-time/integration constraint in this story.

### Actionable suggestion
- Add a mandatory proof-case that an execution path with valid `contracts+amount` near-zero uses the same function as regular rounding path, so AT-280 behavior cannot drift behind unit test coverage.

---

## S2-002 Review
**Story**: S2-002 — S2.3 Compact label schema

### Strengths
- The `hex` selection for `ih16` is well-justified against `ih16` naming and avoids the base32 length mismatch risk.
- Field-transposition wrong-impl case is a high-value adversarial test and correctly linked to S2-003 parser behavior.
- Constraint and rollback coverage are crisp and conservative.

### Weaknesses
1. **Overlength boundary check mixes contract and implementation thresholds.** The math example states `44 <= len <= 45`; the `<= 45` appears derived from implementation choices and can blur the contract boundary of `<=64`. Ensure this assumption is explicitly scoped to fixed-field validity, not normative contract proof.
2. **Dependency on caller to propagate Degraded remains external and should be tested in-system.** The proof plan has AT-041 but does not include a negative test proving non-degraded path on non-length-related failures.

### Actionable suggestion
- Add one explicit negative test asserting that `LabelTooLong` is the only length-overflow reason on length overflow and cannot be downgraded to a generic reject in the caller path.

---

## S2-003 Review
**Story**: S2-003 — S2.4 Label match disambiguation

### Strengths
- The explicit provenance note for PRD-only `qty_q` tie-breaker reduces contract-overreach risk and should prevent false contract claims.
- Forced-order wrong-impl now encodes different final outcomes (important correctness gain over earlier phase gap).
- Degraded/NoMatch distinction is clear and aligns with intended sweeper behavior.

### Weaknesses
1. **`§5` does not yet test the zero-match-tie-breaker skip policy under live matcher pressure.** The policy is set in `§4`, but there is no explicit scenario proving behavior is stable when ih16 filters all candidates.
2. **Assumption 2’s O(1)/O(log n) performance check is hard to guarantee in unit test context.** Performance assumption is noted but unenforced and may be over-prescriptive for pure correctness review.

### Actionable suggestion
- Include a single matcher property test for an empty-match-at-step-N scenario and assert the intended fallback path deterministically.

---

## S2-004 Review
**Story**: S2-004 — S2.5 RejectReasonCode registry

### Strengths
- Registry completeness (30 values) alignment in `§2` is excellent and now explicit; this directly addresses contract drift risk.
- The dual treatment of PRD reason-code fields as diagnostics is clearly separated from primary registry obligations.
- Wrong-impl coverage for serialization and catch-all variants is strong and guards against silent contract leakage.

### Weaknesses
1. **Decision around PRD-only reason codes remains in the premortem but may under-state implementation risk.** If upstream tooling auto-emits these as primary reasons, this is a compile risk the document only partly fences off.
2. **Risk in `§10` remains unresolved around pipeline wiring (No. of claims not proven).** The proof plan notes gating dependency on pipeline; this is high leverage and should be surfaced as a claimed-not-proven item in debt register rather than just a note.

### Actionable suggestion
- Add a negative compile-time test that asserts no code path emits `UnknownActionClassifiedOpen` as a primary reject reason for AT-201 paths.

## Systemic patterns observed
- Quantization, hashing, label schema, and matching form a tight coupling chain; assumptions on interfaces should be represented as explicit compile-time checks (constructor signatures, return types) before behavioral tests.
- Several stories include cross-cutting concerns that exceed local scope; these are generally well flagged but some should be elevated to explicit “MED debt” if they affect the enforceability of safety gates.
- The same theme recurs: a contract-anchored risk path is often deferred to downstream stories; these must be collected into a concrete dependency checklist before final pass.
