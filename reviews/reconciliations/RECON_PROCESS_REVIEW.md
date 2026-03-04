# Reconciliation Process Review

**Date**: 2026-03-04
**Scope**: Full reconciliation pipeline (Mode A + Mode B), premortems, handoff, tooling, artifacts

**Revalidation Baseline**: Rechecked against `origin/main` commit `4891fb87101a310f76d3f00981be0d3ea03c7645` on 2026-03-04.
**Status tags**: `[CONFIRMED]` `[PARTIAL]` `[CONTRADICTED]` `[STALE]` `[PROPOSAL_REQUIRES_CONTRACT_CHANGE]`

## Regenerate Appendix A

Use the generator script from the repo root:

```bash
./plans/generate_recon_review_appendix.sh \
  --commit origin/main \
  --date 2026-03-04 \
  --update-doc reviews/reconciliations/RECON_PROCESS_REVIEW.md
```

If `--date` is omitted, the script uses current UTC date.

## Execution Authority (Current)

This document is an analysis/review artifact. It is **not** an execution authority.

For live reconciliation execution, use these canonical sources:

1. `reviews/reconciliations/PROTOCOL.md` — execution order, gates, handoff cadence.
2. `reviews/reconciliations/REFERENCE.md` — anti-patterns, escalation, troubleshooting.
3. `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md` — required handoff format.
4. `specs/WORKFLOW_CONTRACT.md` — workflow contract authority.
5. `plans/wf_step.sh` — canonical step order and receipt enforcement.
6. `plans/verify.sh` — canonical verify entrypoint.
7. `plans/prd_set_pass.sh` — canonical pass-flip gate.

Related execution prompts (step-local):
- `plans/step_prompts/recon/*.md`

Legacy-to-current mapping:

| Legacy doc | Current source |
|---|---|
| `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | `reviews/reconciliations/PROTOCOL.md` + `REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECON_POLICY.md` | `reviews/reconciliations/PROTOCOL.md` |
| `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | `reviews/reconciliations/REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECON_METRICS.md` | `reviews/reconciliations/REFERENCE.md` |
| `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | `reviews/reconciliations/PROTOCOL.md` + step prompts |

## Numeric Methodology (Normalized)

All numeric claims in this document use one counting methodology:

1. **Snapshot source**: `origin/main` at `4891fb87101a310f76d3f00981be0d3ea03c7645`.
2. **Documentation line counts**: `wc -l` over the six cited **legacy corpus docs** (RUNBOOK, POLICY, ANTIPATTERNS, METRICS, PROCESS, HANDOFF).
3. **Corpus file counts**:
   - Reconciliation files: `git ls-tree -r --name-only origin/main reviews/reconciliations | wc -l`
   - Premortem files: `git ls-tree -r --name-only origin/main reviews/premortems | wc -l`
   - These counts include **all files under those directories**.
4. **Artifact-per-story values with `~`** (for example `~45/story`) are treated as **audit estimates**, not live snapshot counts.
5. **S2 throughput numbers** (`~3.5h`, `27 artifacts`) come from `reviews/reconciliations/S2/SUMMARY.md`.
6. **`40:1` ratio** is treated as a reported value from S2 summary text; it is **not independently recomputed** because denominator definitions are mixed in source text.
7. **Debrief field math**: `99` = `9 step blocks × expandable §§1-§11`; full section heading range remains `§0-§11`.
8. **Gate count claims** are validated against script and docs separately. If script/docs disagree, claim status is `PARTIAL` or `CONTRADICTED`.
9. **Verify command references** are normalized to `./plans/verify.sh` (not root `./verify.sh`).

---

## Executive Summary

Your reconciliation process is doing the right thing — retroactively auditing stories against contract claims with causal proof requirements. The core verification model (TRIP/NON-TRIP tests, wiring audits, mutation testing, fail-closed verdicts) is genuinely strong and has already caught real bugs that would have been invisible to conventional review.

The problem isn't the *what*, it's the *how much*. The process has accreted layers of documentation, gates, artifacts, and ceremony that make it brutally expensive to operate — especially for low-risk stories. Your own S2 dry-run quantified this: **~3.5 hours and 27 artifacts for a LOW-risk story with zero production code changes**. The **40:1** ratio is reported in S2 docs but uses inconsistent ratio definitions. `[PARTIAL]`

You've already diagnosed most of the problems in your two process audits (2026-02-26 and Round 2). The proposals there are good. What follows is my independent assessment of what matters most, what's missing from the existing proposals, and a concrete plan to simplify.

---

## What's Working Well (Keep These)

These are the high-signal components that justify the entire process:

1. **Causal proof requirement (TRIP/NON-TRIP)** — Forcing reviewers to prove *which guard* caused a rejection, not just that *something* failed. This remains high-signal, but the `dispatch_consistency_passed` bare-bool bypass was attributed to strategic review (R7b H2), not directly to TRIP/NON-TRIP. `[PARTIAL]`

2. **Wiring audit (R7c)** — Discovered that 58% of Slice 1 enforcement functions had zero production callers ("island of guards"). This was also tied to strategic review findings, not R7c alone. `[PARTIAL]`

3. **Mutation testing (R7e)** — S2 summary calls it "the highest-signal check in the entire pipeline." 100% mutation kill rate on S2-001 is supported. The "5 test gaps" figure appears in slice-level material and should not be attributed to S2-001 alone. `[PARTIAL]`

4. **Fail-closed verdicts** — `WRONG_IMPL_UNBLOCKED` and `CLAIMED_NOT_PROVEN` as first-class outcomes means the process doesn't silently approve things it can't verify.

5. **`wf_step.sh` receipt chain** — Receipts are HEAD-anchored and ordered. This is useful audit evidence, but not a cryptographic tamper-evident chain by itself. `[PARTIAL]`

6. **`prd_set_pass.sh` pass-flip gate** — The gate is strict, but check-count references are drifted across sources (script/docs disagree), so "12-check gate" is stale. `[CONTRADICTED]`

---

## The Core Problems

### Problem 1: One Pipeline For All Risk Levels

Every story — from scaffolding (`S1-001`) to safety-critical dispatch logic (`S1-007`) — goes through the same 9-step pipeline. The "16-R-phase" framing is inexact across docs, but the core point stands: S2 friction identified R2 (lead eval), R3A (cross-review), R7b (strategic review), and R7d (external C2) as ceremony for a low-risk pure-function story. `[PARTIAL]`

Decision for this iteration: keep the full 9-step pipeline for all stories, and reduce friction inside that path before introducing any risk-tier branching.

### Problem 2: Documentation Sprawl

To execute one reconciliation step, an agent needs to potentially consult:

| Document | Lines |
|----------|-------|
| RUNBOOK_PREMORTEM_RECON.md | 1,592 |
| PREMORTEM_RECON_POLICY.md | 555 |
| PREMORTEM_RECON_ANTIPATTERNS.md | 387 |
| PREMORTEM_RECON_METRICS.md | 624 |
| PREMORTEM_RECONCILIATION_PROCESS.md | 424 |
| RECON_HANDOFF_TEMPLATE.md | 380 |
| **Total** | **~3,960 lines** |

Plus 9 step prompt cards, the reconcil skill, the operator skill, the executor skill, and the workflow contract. An agent can't hold all this in context. The result can be rule drift and stale references — exactly the failure mode Round 2 documented (P0-A, P0-B, P1-D), though some items appear partially resolved on current main and should be treated as point-in-time findings. `[PARTIAL]`

### Problem 3: Artifact Explosion

Your audit estimated ~45 artifacts per story. Current `origin/main` snapshot count is **167 reconciliation files + 42 premortem files = 209 files** (counting all files under both directories). The prior `162 + 41 = 203` figure appears to come from an older or differently filtered snapshot. The S2 summary noted 27 artifacts for a single story. `[PARTIAL]`

The high-signal artifacts (keep) are: evidence ledger, proof graph, GAP_LIST, DEBT_REGISTER, external review manifests, receipts, and the final review resolution. That's about 10-12 files. The other 15-30 per story are intermediate documents that should be sections within those files, not standalone artifacts.

### Problem 4: The Debrief Tax

The debrief structure (§0-§11) per step was designed for learning, but in practice almost every entry is "§0: CLEAN." The current "99 fields per story" framing comes from 9 steps × expandable §§1-§11; wording should be explicit because §0-§11 is 12 sections total. Even with the shortcut, agents still have to *think about* whether to expand each section, which burns context and time. `[PARTIAL]`

### Problem 5: Dual-Layer Naming Creates Cognitive Load

The mapping between `wf_step.sh` steps (preflight, implement, self_review, cycle1, fix, cycle2, resolution, verify_full, pass) and R-phases (R1, R2, R3A, R3B, R4, R4b, R5, R5b, R6, R7a-R7f) requires a decoder ring. "Step 4 (cycle1)" maps to R2 + R3A + R3B + R4 + R4b — five sub-phases. Your audit identified this (S-1), and your Round 2 found the mapping table appears in 4 different files, each slightly different.

---

## Recommendations

### 1. Keep A Single Full Pipeline (For Now)

Do not introduce tier routing in this phase. Keep all stories on the current full `wf_step.sh` sequence:

`preflight` → `implement` → `self_review` → `cycle1` → `fix` → `cycle2` → `resolution` → `verify_full` → `pass`

Reduce cost *inside* the existing path instead of creating alternate paths:

| Focus | Change |
|------|--------|
| Documentation load | Consolidate operator docs and remove duplicate mapping tables |
| Artifact count | Merge low-signal intermediates into a smaller set of primary artifacts |
| Manual overhead | Replace debrief blocks with minimal notes/friction logging |
| Mechanical checks | Script validations currently performed manually |

This keeps current contract/gate behavior stable while improving throughput. Tier routing remains a future option only after full-path ergonomics are stable and measured.

### 2. Consolidate Documentation to 2 Files

Replace the current 5-document, ~4,000-line corpus with:

**File 1: `PROTOCOL.md`** (~600 lines)
Contains everything an agent needs to execute: step definitions (with R-phase sub-bullets inline, not as a separate naming layer), gate checks, verdict definitions, schemas, and step-order/gate mapping. One file, one source of truth.

**File 2: `REFERENCE.md`** (~400 lines)
Contains everything an agent reads only when something goes wrong: anti-patterns (top 10 only — the long tail of 26 is not being read), worked examples, escalation procedures, and lessons learned.

Retire: RUNBOOK, POLICY, ANTIPATTERNS, METRICS, and PROCESS as separate files. Convert to redirects pointing to PROTOCOL.md. The step prompt cards (`plans/step_prompts/recon/*.md`) can remain as focused execution prompts, but they should reference PROTOCOL.md, not 5 different documents.

### 3. Merge Artifacts Aggressively

Target: **1 primary artifact per story** (`evidence_ledger.json`) that accumulates data across steps, plus external review manifests and receipts.

| Current (separate files) | Proposed (merge into) |
|----|-----|
| R2_LEAD_EVAL.md/json | Section in `evidence_ledger.json` |
| R3 cross-review findings | Flow into `GAP_LIST.json` |
| R4B external mapping | Field in `GAP_LIST.json` |
| R5 plan + notes | Single `remediation.md` |
| R5B fix plan + fix log | Section in self-review gate |
| R7A/B/C reviews | Single `audit_cycle2.md` |
| Separate .md + .json for same artifact | JSON only (render markdown from JSON) |
| Postmortem | Section in `review_resolution.md` |

This aligns with your own audit proposal (S-4: reduce ~45 to ~12). The additional step I'd suggest: make `evidence_ledger.json` the single accumulating document. Each step appends to it rather than creating a new file. The receipt chain in `wf_step.sh` already tracks step completion — you don't need duplicate tracking in separate artifact files.

### 4. Kill the Debrief Structure

Replace the §0-§11 debrief blocks entirely with:

```
Notes: <one line, or empty>
Friction: <what broke · root cause · fix needed — only if something actually broke>
```

That's it. Two optional lines per step. If there's a structural/recurring issue, it goes directly in the Process Backlog (which already exists and is the right place for it). The 11-section debrief was a postmortem template being applied at step granularity — that's the wrong level.

### 5. Flatten the Naming to One Layer

Drop the R-phase numbering entirely. Use only the `wf_step.sh` step names. Where a step has meaningful sub-parts, list them as numbered bullets within the step, not as a separate naming scheme.

Before: "Step 4 (cycle1) = R2 + R3A + R3B + R4 + R4b"
After: "cycle1: (1) lead eval, (2) cross-review, (3) external review, (4) gap synthesis"

This eliminates the decoder-ring lookup and the 4-file drift problem your Round 2 audit found.

### 6. Fix the P0s From Your Own Audits

Your two process audits identified multiple P0/P1 issues. Some were marked "Backlog — not yet implemented" at the time of those audits, but current main appears to have resolved part of this set. Re-validate status before planning execution:

- **P0-A**: Premortem fallback conflict (RUNBOOK says "never use surrogate"; prompt says "use surrogate") — agents are choosing the easier path
- **P0-B**: "implement" label collision between R1 (read-only) and R5 (write) — agents are writing code during read-only audit
- **P0 (Round 1, I-3)**: Evidence ledger path lookup silently fails for all S1 stories
- **P0 (Round 1, I-5)**: S1 manifests missing `schema_version`, validator fails all of them

Fix these before adding any new process features. They're undermining the gates you've already built.

### 7. Automate the Mechanical Steps

Several steps are pure mechanical validation that agents shouldn't be doing manually:

- **Phantom test detection**: `implementation_tests[]` entries vs actual `#[test]` functions — a 20-line script
- **Debt register schema validation**: Already have `validate_recon_artifact.sh` — wire it into `wf_step.sh` automatically
- **Evidence ledger completeness**: Check that every AT has a verdict — scriptable
- **Wiring audit**: `grep -r` for callers of enforcement functions — the LSP check you did for slice1 could be a script
- **`prd_set_pass.sh --dry-run`**: Your audit proposed this (O-2) — implement it so agents can pre-check gates

Each of these saves 5-15 minutes of agent time per story and eliminates human error in mechanical checks.

### 8. Make the Handoff Template Path-Conditional

The current HANDOFF template is 380 lines with placeholders for every possible field. On clean/full-path stories with minimal findings, much of it is irrelevant. Create path-conditional handoff sections:

- **Base (always)**: status matrix + "Stopped at" + "Next steps" (~30 lines)
- **Findings path**: add hard evidence summary table when gaps/findings exist (~60 lines)
- **Escalation path**: include full section set only when external review/fix loops are active

### 9. Increase External Review Parallelism Where Still Sequential

The current process is hybrid (parallel across tools/stories, sequential prompt styles per tool). For stories that require multi-tool Cycle 2 coverage, increase parallel dispatch where there is no dependency. This can still reduce wall-clock time meaningfully.

### 10. Establish a "Process Debt" Budget

You have a `DEBT_REGISTER.json` for code debt. Create an equivalent for process debt. Set a hard rule: the reconciliation process documentation cannot exceed N lines total (I'd suggest 1,200 — roughly PROTOCOL.md + REFERENCE.md + step cards). Any addition requires removing equivalent material. This prevents the re-accumulation that got you to 4,000 lines.

---

## Implementation Priority

| Priority | Action | Effort | Impact |
|----------|--------|--------|--------|
| **P0** | Re-validate and close remaining silent-failure bugs from your audits | 3 hours | Stops active gate bypass |
| **P1** | Keep single full pipeline; reduce friction inside existing steps (no tier split yet) | 1 day | Immediate throughput gain with low contract risk |
| **P1** | Consolidate docs to PROTOCOL.md + REFERENCE.md | 1 day | Eliminates drift, fits in agent context |
| **P1** | Kill §0-§11 debriefs, replace with 2-line format | 2 hours | Removes 90% of paperwork |
| **P2** | Merge artifacts (~45 → ~12 per story) | 1 day | Reduces file sprawl by 70% |
| **P2** | Flatten R-phase naming | 3 hours | Eliminates decoder-ring confusion |
| **P2** | Automate 5 mechanical checks | 1 day | Saves ~30 min/story, removes human error |
| **P2** | Implement `prd_set_pass.sh --dry-run` | 2 hours | Eliminates gate-flip surprises |
| **P3** | Path-conditional handoff templates | 3 hours | Cleaner handoffs with less irrelevant template noise |
| **P3** | Parallel external review dispatch | 4 hours | Faster wall-clock for stories needing multi-tool C2 |

---

## What This Gets You

**Before** (historical audit snapshot):
- 1 pipeline for all stories
- ~4,000 lines of process docs across 5+ files
- ~45 artifacts per story (audit estimate)
- 99 debrief fields per story
- ~3.5 hours per low-risk story
- Multiple known P0 bugs silently undermining gates at audit time (re-validate on current main)

**After** (all recommendations implemented):
- 1 full pipeline for all stories (contract behavior unchanged)
- ~1,000 lines of process docs in 2 files + step cards
- ~10-15 artifacts per story (full-path optimized)
- 2 optional lines per step for notes/friction
- ~2-4 hours per story depending on findings depth
- Zero known silent failures

The process keeps everything that makes it strong (causal proof, wiring audits, mutation testing, fail-closed verdicts, receipt chains) while removing the ceremony that doesn't catch bugs.

---


## Appendix A — Claim-by-Claim Evidence (origin/main @ 4891fb87101a)

> Generated by plans/generate_recon_review_appendix.sh --commit origin/main --date 2026-03-04

| ID | Claim (short) | Status | As-of Date | As-of Commit | Evidence |
|----|---------------|--------|------------|--------------|----------|
| C-01 | S2 took ~3.5h and 27 artifacts | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/S2/SUMMARY.md:55; reviews/reconciliations/S2/SUMMARY.md:69 |
| C-02 | S2 40:1 process-to-code ratio | PARTIAL | 2026-03-04 | 4891fb87101a | reviews/reconciliations/S2/SUMMARY.md:68 |
| C-03 | TRIP/NON-TRIP directly caught dispatch_consistency_passed bypass | CONTRADICTED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/slice1/STRATEGIC_REVIEW_R5.md:35; reviews/reconciliations/slice1/SUMMARY.md:81 |
| C-04 | R7c found 58% island-of-guards | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/slice1/LSP_CALL_CHAIN_CHECK.md:26 |
| C-05 | No other layer caught island-of-guards | CONTRADICTED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/slice1/LSP_CALL_CHAIN_CHECK.md:28; reviews/premortems/PREMORTEM_RECON_METRICS.md:69 |
| C-06 | Mutation is highest-signal in S2 | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/S2/SUMMARY.md:89 |
| C-07 | 100% mutation kill on S2-001 | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/S2/SUMMARY.md:15; reviews/reconciliations/S2/R7_POST_RECON_VALIDATION.md:119 |
| C-08 | 5 test gaps applies to S2-001 | PARTIAL | 2026-03-04 | 4891fb87101a | reviews/reconciliations/S2/SUMMARY.md:26 |
| C-09 | CLAIMED_NOT_PROVEN and WRONG_IMPL_UNBLOCKED are first-class fail-closed outcomes | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/premortems/PREMORTEM_RECON_POLICY.md:39; reviews/premortems/PREMORTEM_RECON_POLICY.md:41 |
| C-10 | wf_step receipt chain is tamper-evident | PARTIAL | 2026-03-04 | 4891fb87101a | plans/wf_step.sh:192; plans/prd_set_pass.sh:313 |
| C-11 | prd_set_pass.sh is a 12-check gate | CONTRADICTED | 2026-03-04 | 4891fb87101a | plans/prd_set_pass.sh:6; reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:1197; reviews/premortems/PREMORTEM_RECON_POLICY.md:207 |
| C-12 | Same 9-step pipeline for stories | CONFIRMED | 2026-03-04 | 4891fb87101a | plans/wf_step.sh:41; reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:185 |
| C-13 | 16-R-phase framing is canonical | PARTIAL | 2026-03-04 | 4891fb87101a | reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:1412; reviews/premortems/PREMORTEM_RECON_METRICS.md:63 |
| C-14 | cycle1 maps to R2+R3A+R3B+R4+R4b | PARTIAL | 2026-03-04 | 4891fb87101a | reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:185; reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:321; reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:349 |
| C-15 | Doc corpus is ~3960 lines | CONFIRMED | 2026-03-04 | 4891fb87101a | docs_total=3962 (RUNBOOK=1592 POLICY=555 ANTIPATTERNS=387 METRICS=624 PROCESS=424 HANDOFF=380) |
| C-16 | 9 step prompt cards exist | CONFIRMED | 2026-03-04 | 4891fb87101a | plans/step_prompts/recon/* (excluding INDEX) count=9 |
| C-17 | 162 + 41 = 203 current file counts | CONTRADICTED | 2026-03-04 | 4891fb87101a | reconciliations=167 premortems=42 total=209 |
| C-18 | 99 fields/story debrief tax | PARTIAL | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md:57; reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md:69 |
| C-19 | Round2 includes P0-A, P0-B, P1-D | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md:10; reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md:32; reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md:97 |
| C-20 | Round1 includes I-3/I-5 as P0 | CONFIRMED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md:19; reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md:30 |
| C-21 | Still backlog/not implemented applies uniformly now | STALE | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md:4; plans/prompts/slice_reconcile_r1_audit.md:1 |
| C-22 | Aggregate 2 P0 and 6 P1 from two audits | CONTRADICTED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md:126; reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26_ROUND2.md:54 |
| C-23 | External reviews run sequential only | CONTRADICTED | 2026-03-04 | 4891fb87101a | reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:315; plans/step_prompts/recon/cycle1.md:10 |
| C-24 | Tier routing can use risk, scope.touch, loss_mode.worst_case | CONFIRMED | 2026-03-04 | 4891fb87101a | plans/prd.json:73; plans/prd.json:38; plans/prd.json:93 |
| C-25 | Tier-1 no-premortem is contract-compliant today | PROPOSAL_REQUIRES_CONTRACT_CHANGE | 2026-03-04 | 4891fb87101a | reviews/premortems/RUNBOOK_PREMORTEM_RECON.md:81; reviews/premortems/PREMORTEM_RECON_POLICY.md:116 |
| C-26 | prd_set_pass.sh --dry-run exists today | CONTRADICTED | 2026-03-04 | 4891fb87101a | reviews/reconciliations/RECON_PROCESS_AUDIT_2026-02-26.md:77; plans/prd_set_pass.sh:6 |
