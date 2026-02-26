# Reconcil Process Audit — Round 2 — 2026-02-26

**Source**: Operator analysis reviewed and confirmed against codebase.
**Status**: Backlog — not yet implemented.

---

## P0 — Fix Immediately (Silent Failure Risk)

### P0-A: Premortem fallback rule conflict (I-2b)

**Files**:
- `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 preflight gate row 1:
  `NO-GO: PREMORTEM_MISSING — Stop — write premortem first. No surrogate path.`
- `plans/prompts/slice_reconcile_implement.md` lines 53–57:
  Full surrogate path: `PREMORTEM_ABSENT → use recon preflight artifact as surrogate premortem`

**Risk**: Agent reads slice_reconcile_implement.md, finds no premortem, proceeds with a narrower
audit instead of halting. Silent under-audit. RUNBOOK says "never"; prompt says "sometimes".

**Fix**: Pick one rule and enforce it everywhere:
- Recommended: keep RUNBOOK hard-NO-GO (no surrogate). Remove surrogate path from
  slice_reconcile_implement.md. Add one-liner: "If premortem missing → stop, emit
  PREMORTEM_MISSING, do not continue."
- Alternative: document the surrogate path explicitly in RUNBOOK as a Mode A-Lite variant
  with its own gate checks — not as an implicit fallback inside an R1 prompt.
- Update: plans/prompts/reconcil.md, RUNBOOK §3 preflight gate, any step_prompts/recon/
  file that touches R1.

---

### P0-B: "implement" label collision between R1 and R5 (I-1b)

**Files**:
- `plans/prompts/slice_reconcile_implement.md` — titled `STEP: IMPLEMENT (RECONCILIATION
  AUDIT MODE)`, describes a **read-only** R1 audit. Line 6 says so, but only in a disclaimer.
- `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 (now replaced inline text):
  step `implement` maps to R5 (real remediation / write).

**Risk**: Agent sees "implement", skips the disclaimer, writes production code during what
should be a read-only R1 step. Or attaches the wrong prompt to the wrong step.

**Fix**:
1. Rename `plans/prompts/slice_reconcile_implement.md` to `plans/prompts/slice_reconcile_r1_audit.md`
   (or update the title to `STEP: R1-PREFLIGHT (READ-ONLY AUDIT)`).
2. Update `plans/step_prompts/recon/preflight.md` to reference the renamed file.
3. Reserve "implement" exclusively for the R5 remediation prompt (`recon/implement.md`).
4. Update any cross-references in reconcil.md, RUNBOOK, skill.

---

## P1 — Fix Soon (Structural Integrity)

### P1-A: Single authoritative step-mapping table

**Problem**: The wf_step ↔ R-phase ↔ meaning mapping appears in:
- `SKILLS/reconcil.md`
- `plans/prompts/reconcil.md`
- `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 (step table — we replaced with inline text)
- `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md`

Each is slightly different. Our I-4 fix removed the RUNBOOK decoder table but didn't consolidate.

**Fix**: Pick RUNBOOK §3 as the single source. All other files get: "Step mapping: see
RUNBOOK §3." One-time fix; keeps drift surface at one file going forward.

---

### P1-B: review_basis enum mismatch

**Problem**:
- Human-facing docs / artifact headers: `STORY_SCOPE (Cycle 1)` / `FIX_DIFF + AT_REGRESSION (Cycle 2)`
- `plans/validate_recon_artifact.sh` JSON enum: `STORY_SCOPE` / `FIX_DIFF_AT_REGRESSION`
- Our I-6 fix greps for `FIX_DIFF` which matches both — but any future tooling checking the
  enum exactly will break, and manual artifact authors will produce mis-formatted sidecars.

**Fix**: Decide on canonical form:
- Option A: rename JSON enum to match human string (breaking change to existing JSON artifacts)
- Option B: add enum alias in validator + add note to review_logged.sh output header
- Option C (cheap): add a comment in validate_recon_artifact.sh mapping the two forms, and add
  a note to RUNBOOK §6 artifact provenance section.

---

### P1-C: Canonical R1 prompt source not on main branch

**Problem**: `slice_reconcile_implement.md` header says Appendix A of
`PREMORTEM_RECONCILIATION_PROCESS.md` is the canonical R1 source — but that file only exists
in worktrees, not in main. The "canonical source" claim is broken.

**Fix**: Either move `PREMORTEM_RECONCILIATION_PROCESS.md` to main
(`reviews/premortems/`), or remove the "Appendix A is canonical" claim and designate
`plans/step_prompts/recon/preflight.md` as the single source.

---

### P1-D: plans/prompts/reconcil.md as second orchestration spec

**Problem**: After our I-4 fix, the surface is: `/reconcil skill` + `plans/prompts/reconcil.md`
+ `wf_step.sh`. The prompts file is a full orchestration spec that agents can reach
independently of the skill, creating a second entry point with potentially stale content.

**Fix**: Convert `plans/prompts/reconcil.md` to a thin redirect:
> "Orchestration: use `/reconcil` skill. Receipt tracking: `plans/wf_step.sh`. This file
> is kept for historical reference only — do not follow step instructions from here."

---

## P2 — Quality-of-Life Improvements

### P2-A: Risk-tier external review intensity

**Current**: 3 tools × 2 prompt styles × 2 cycles = up to 12 review artifacts per story.
**68 review artifacts for 9 stories** in practice.

**Proposed tiers**:
| Story risk | C1 reviews | C2 reviews |
|------------|-----------|-----------|
| HIGH (safety-critical AT, TradingMode, WAL) | 3 tools × dual-prompt | Full dual-combo |
| LOW (docs, config, non-gate code) | 1 tool × dual-prompt | recon_clean_single |

**Gate**: Derive tier from `loss_mode.worst_case` and `scope.touch` in prd.json.
Add `review_tier: high|low` field to prd.json items, validated by prd_set_pass.sh.

---

### P2-B: Lightweight debrief defaults in HANDOFF template

**Current**: 9 steps × §0–§11 debrief block = 99 structured fields per story.

**Fix**: Update RECON_HANDOFF_TEMPLATE.md header with bold rule:
> **Clean step = one line**: `Status: COMPLETE · §0: CLEAN · Artifacts: <paths>`
> **Only expand §§1–11 when**: gate blocked, or friction worth promoting to process backlog.

This makes the happy path a 1–2 line update per step instead of a mini-postmortem.

---

### P2-C: Wave-2 schema tagging

**Problem**: Schema table in PREMORTEM_RECONCILIATION_PROCESS.md (worktree) references
schemas that are `Wave 2 / not yet created` but are referenced as mandatory.

**Fix**: Add a `Status` column to the schema table:
| Artifact | Schema | Status |
|----------|--------|--------|
| R3_EXTERNAL_MANIFEST.json | r3_external_manifest.schema.json | **Active** |
| evidence_ledger.json | evidence_ledger.schema.json | **Wave 2 — not yet enforced** |

---

## Implementation Order

```
P0-A (premortem fallback)   ← most dangerous silent failure
P0-B (implement rename)     ← active trap every recon run
P1-A (single mapping table) ← mechanical, reduces drift surface
P1-B (enum mismatch)        ← tooling correctness
P1-C (canonical source)     ← removes broken claim
P1-D (prompts/reconcil.md)  ← completes orchestration consolidation
P2-A (review tiering)       ← biggest throughput win
P2-B (lightweight debriefs) ← paperwork reduction
P2-C (wave-2 tagging)       ← reader clarity
```

---

## What We Confirmed Is NOT a Problem

- RECON_HANDOFF_TEMPLATE.md: no remaining `step_supervisor` references found (cleaned by prior
  work or the claim was based on a worktree version).
- Our I-6 FIX_DIFF grep works correctly for both `FIX_DIFF_AT_REGRESSION` and
  `FIX_DIFF + AT_REGRESSION` since both contain the substring `FIX_DIFF`.
