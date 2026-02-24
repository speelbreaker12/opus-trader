# SKILL: /reconcil (Premortem + Reconciliation Orchestrator)

## Purpose
Orchestrate the premortem authoring (Mode A) and/or reconciliation audit (Mode B) workflow for PRD stories.
Routes the agent to the correct phase, enforces gates, and ensures all 5 governing documents are consulted.

## When to use
- Retroactive audit of already-implemented stories against premortems
- Writing premortems for stories before or after implementation
- Running any reconciliation phase (R1-R7)
- When the step supervisor says the next step is `preflight`, `implement`, `self_review`, `cycle1`, `fix`, `cycle2`, `resolution`, `verify_full`, or `pass`

## Governing Documents (read on demand, not all at once)

| Document | Path | When to read |
|----------|------|-------------|
| **Process Index + R1 Prompt** | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | Always read first (quick links + mode selection). Read Appendix A for R1 audit prompt. |
| **Runbook** | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | When executing any phase (operator instructions, step-by-step). |
| **Policy** | `reviews/premortems/PREMORTEM_RECON_POLICY.md` | When assigning verdicts, checking gates, validating schemas. |
| **Anti-Patterns** | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | During reviews (Cycle 1/2). Top 5: #20 paper enforcement, #6 skip R7c, #12 fake citation, #25 single-prompt, #26 blanket --theirs. |
| **Metrics & Reference** | `reviews/premortems/PREMORTEM_RECON_METRICS.md` | For worked examples, agent grouping, gap format, lessons learned. |

## Inputs

**Required:**
- `STORY_ID` — the story to reconcile (e.g., `S1-007`). Pass as argument: `/reconcil S1-007`
- `plans/prd.json` — story entry
- `specs/CONTRACT.md` — relevant AT clauses

**Conditionally required:**
- `reviews/premortems/<STORY_ID>_premortem.md` — required for Mode B (write in Mode A if missing)
- `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` — required for Mode A

## Task

### 0) Mode Selection

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §0 (Mode Selection).

Determine mode based on current state:

| Situation | Mode |
|-----------|------|
| Code not implemented yet | **Mode A** (Premortem Authoring) |
| Code exists, premortems exist | **Mode B** (Reconciliation) |
| Code exists, no premortems | **Mode A** then **Mode B** |
| Single story, MED/HIGH risk | Mode A (abbreviated: 1 writer + 2 cross-reviewers) then Mode B |
| Single story, LOW risk | Mode A (1 writer + lead eval) then Mode B |

**Ask the user** which mode to execute if ambiguous. Present the current state (does premortem exist? does code exist?) and recommend.

### 1) Hard Gates

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §1 (Hard Gates).

Check:
1. Required artifacts exist (`plans/prd.json`, `specs/CONTRACT.md`, template if Mode A, premortem if Mode B)
2. If Mode B: run `plans/premortem_ready.sh ${STORY_ID}` — exit 0 = proceed, exit 1 = fix premortem first
3. If Mode B: check STOPLIGHT in premortem §10 — RED = STOP, YELLOW = proceed with debt, GREEN = proceed

**If any gate fails → STOP. Report the failure. Do not proceed.**

### 2) Execute Phase

Based on mode and current progress, execute the appropriate phase.

#### Mode A — Premortem Authoring (7 Phases)

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §2 for full phase instructions.

| Phase | Goal | Key output |
|-------|------|------------|
| 1 — Parallel Write | One premortem per story (§0-§10) | `<STORY_ID>_premortem.md` |
| 2 — Lead Evaluation | Score + patch list | `phase2_lead_eval.json` |
| 3 — Targeted Patch | Surgical fixes only (>30% = escalate) | Updated premortems |
| 4 — Cross-Review | All batches reviewed by non-authors | `CROSS_REVIEW_by_<REVIEWER>.md` |
| 5 — Synthesis | Merge findings, prioritize fixes | `phase5_synthesis.json` |
| 6 — Final Patch | Apply synthesized fixes | Updated premortems |
| 7 — Verify | Confirm implementation-ready | `phase7_verify_report.json` + PREMORTEM_READY |

#### Mode B — Reconciliation (R1-R7)

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 for full phase instructions.

**Step Supervisor Mapping:**

| `wf_step.sh` step | Recon phase(s) | What happens |
|--------------------|---------------|-------------|
| `preflight` | R1 | READ-ONLY audit: locate enforcement, verify fail-closed, build evidence ledger |
| `implement` | R5 | Fix gaps from R4 gap list (only phase that writes code) |
| `self_review` | R5b | 5-skill stack, fix blockers, produce gate artifact + 5 skill receipts |
| `cycle1` | R2 + R3 + R4 + R4b | External story-scope audit, cross-review, gap synthesis |
| `fix` | R7a-R7c | Contract review, strategic review, wiring audit fixes |
| `cycle2` | R7d + R7e + R7f | Post-remediation audit on fix diff + AT regression |
| `resolution` | R6 | Lead confirms gaps closed, assigns final verdicts |
| `verify_full` | `verify.sh full` | Mechanical verification |
| `pass` | `prd_set_pass.sh` | 15-check pass-flip gate |

**For R1 (preflight):** Read Appendix A in `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` — it contains the full R1 agent prompt (source of truth).

**For verdicts:** Read `reviews/premortems/PREMORTEM_RECON_POLICY.md` §2 (Verdict Systems).

**For reviews:** Read `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` — especially the Top 5 Most Dangerous and the Reviewer Checklist Extract at the bottom.

### 3) Verdict Assignment

Read `reviews/premortems/PREMORTEM_RECON_POLICY.md` §2-3 for verdict definitions and gate rules.

**Per-AT verdicts:** PROVEN | WEAK_PROOF | CLAIMED_NOT_PROVEN | UNTESTED_ENFORCEMENT | WRONG_IMPL_UNBLOCKED | DEFERRED

**Story verdicts:** RECONCILED | RECONCILED-WITH-DEBT | RECONCILED_UNIT_ONLY | NOT RECONCILED

**Key escalation rules:**
- WEAK_PROOF on MED/HIGH loss_mode AT → treated as CLAIMED_NOT_PROVEN (blocks RECONCILED)
- PROVEN requires cause-specific assertions (reject_reason, dispatch_count, latch_reason, or mode_transition)
- RECONCILED_UNIT_ONLY → passes proof gate but blocked by runtime-enforcement gate (needs integration story)

### 4) Pass-Flip Gate (15 checks)

Read `reviews/premortems/PREMORTEM_RECON_POLICY.md` §3.9 for the full 15-check gate.

Only run when ALL prior phases complete successfully:
```bash
plans/prd_set_pass.sh ${STORY_ID} true
```

## Anti-Gaming Rules (Non-Negotiable)

From `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §5:

1. No diff-only review in Cycle 1 — story-scope required
2. No self-review of own batch in cross-review
3. No DEFERRED without debt register entry (schema-validated)
4. No "code is better" divergence without evidence + lead approval
5. No blanket `--theirs` without per-file merge-base diff
6. No single-prompt reviews — always both generic + enriched per tool
7. No RECON-CLEAN without lead sign-off on BLOCKING=0
8. No fake citations — file:line must contain enforcement/test code
9. No Cycle 2 without R5b gate — `R5B_SELF_REVIEW_PROVEN` required
10. No gap-list-complete without coverage proof

## Artifact Layout

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §6 for canonical directory layout.

All artifacts go under `reviews/reconciliations/<SLICE_ID>/` with deterministic, phase-prefixed names.

## Output

Depends on the phase executed. At minimum:
- **Gate result**: GO / NO-GO with reason
- **Phase artifacts**: As specified by the phase in the Runbook
- **Next step**: What comes next in the workflow
- **Receipt**: `plans/wf_step.sh ${STORY_ID} <step>` (when applicable)

## Hard Constraints

- Follow the Runbook phase-by-phase — do not skip phases
- Consult Policy for any verdict or gate decision
- Check Anti-Patterns before and during reviews
- Every file:line citation must be verified (no fake citations — Anti-Pattern #12)
- R1 is READ-ONLY — no file modifications
- R5 fixes only listed gaps — no unrelated refactors
- Cycle 1 scope is STORY_SCOPE, Cycle 2 scope is FIX_DIFF + AT_REGRESSION
- Every review artifact must include the Review Basis line
