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

# Premortem Cross-Review: Agent A
**Reviewing**: S2-001, S2-002, S2-003
**Date**: 2026-02-24

---

## Scoring Summary

| Story | Template | Clause Trace | Assumptions | Failure Modes | Wrong-Impl Gate | Proof Plan | Risk/Cross-story |
|-------|----------|-------------|-------------|---------------|-----------|-------------|
| S2-001 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS-WITH-ISSUES | PASS |
| S2-002 | PASS | PASS | PASS | PASS | PASS | PASS |
| S2-003 | PASS-WITH-ISSUES | PASS | PASS | PASS | PASS | PASS |

## S2-001 Review
**Story**: S2-001 — Intent hash from quantized fields

### Strengths
- Great correction of `SS→§` notation consistency for the requested sections, and the risk-note in `§0` is now explicit about PRD vs premortem divergence.
- `§2` assumption 3 is correctly split into a concrete separator assumption and an escape hatch for non-ASCII symbols, which improves falsifiability.
- Wrong-implementation coverage in `§5` is strong and includes implementation-shape attacks (hidden timestamp via derive hash, wrong byte order, non-canonical fields).

### Weaknesses
1. **Potential internal contradiction in `§2` assumption 3 framing.** The assumption treats null-byte separation as safe by default and then adds a non-ASCII fallback. In the same row, the fallback path is described as a design option but not tied to a forced test in `§5`. Consider promoting this to a dedicated required test in this story to avoid optional behavior becoming unimplemented later.
2. **Section references drift**: `§10` still uses `SS2`, `SS3` etc from legacy labels. It is low risk but lowers consistency versus the requested formatting standard.

### Actionable suggestion
- Add one explicit directed wrong-impl tightening case in `§5` for “non-ASCII instrument + fixed separator” to force the fallback behavior to be proven if separator choice changes in implementation.

---

## S2-002 Review
**Story**: S2-002 — S2.3 Compact label schema

### Strengths
- The `s4:{sid8}:{gid12}:{li}:{ih16}` format is enforced with concrete round-trip and golden-vector tests, and the tie-breaker consequence for `AT-217` is correctly recognized as shared with S2-003.
- Decision 3 (leg_idx validation) avoids the latent contract leak that would otherwise allow invalid leg indexes to pass as length-only failures.
- The debt register is clean with no deferred items, and all high-risk modes are directly mitigated.

### Weaknesses
1. **Assumption #6 is only partially operationalized.** The “only code path produces labels” assumption is deferred to review but is a high-value invariant for preventing parser drift. Recommend moving it from pure review assumption to a lint/grep-based test requirement.
2. **AT-216 parser/encoder coupling.** Wrong-impl row about encode/decode parity is good, but there is no explicit mention of enforcing parser round-trip against a contract-derived reference label (not only against the same encode/decode function).

### Actionable suggestion
- Add a compile-time/CI grep check that flags any additional `s4:` construction outside `execution/label.rs` so S2-003 cannot silently parse a different label schema.

---

## S2-003 Review
**Story**: S2-003 — S2.4 Label match disambiguation

### Strengths
- Corrected tie-breaker provenance note for `qty_q` clarifies that this step is PRD-driven and not purely contract-specified (`§2`, `§4`, `§5`).
- `§5` row for wrong tie-breaker order now encodes an outcome-difference check (not merely path difference), which materially reduces the “confidently wrong” gap.
- The isolation and policy-guard consequences in `§6` are explicit and keep `AT-217` causality testable via dispatch_count and mode_reason.

### Weaknesses
1. **Remaining ambiguity around zero-match tie-breaker behavior.** `§4 Decision 3` documents a fallback interpretation, but this may conflict with the strict reading of §1.1.2 stepwise filtering. Consider marking this as a formal contested design decision with acceptance criteria.
2. **Cross-story dependency signal could be sharper.** The risk that S2-003 returns `NoMatch` for empty candidates but sweeper behavior is external is noted, but the contract consequence of that handoff is not fully spelled out.

### Actionable suggestion
- Add one wrong-impl tightening in `§5` that validates behavior under mixed ambiguous + no-match sets in a single combined fixture, to ensure the 3-way outcome distinction is stable across implementations.

## Systemic patterns observed
- Story ownership boundaries are well-explained, but decisions that rely on “ambiguous” contract language still need explicit acceptance criteria to avoid implementation drift.
- Several stories still carry legacy tokens (`SSx`, `§`) in mixed places; consistency linting would help keep review artifacts uniform.
- Cross-story handoff assumptions (especially around shared parser/enums) are mostly well documented and should be a recurring automated check in this slice.
