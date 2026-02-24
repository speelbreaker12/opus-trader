# Premortem + Reconciliation Orchestrator Prompt

> **Tool-agnostic.** This prompt works with any LLM agent (Claude, Codex, Kimi, Opus, etc.).
> For Claude Code users: this is also available as `/reconcil`.

## Purpose

Orchestrate the premortem authoring (Mode A) and/or reconciliation audit (Mode B) workflow for PRD stories. Routes the agent to the correct phase, enforces gates, and ensures all 5 governing documents are consulted.

## When to use

- Retroactive audit of already-implemented stories against premortems
- Writing premortems for stories before or after implementation
- Running any reconciliation phase (R1-R7)
- When the step supervisor says the next step is `preflight`, `implement`, `self_review`, `cycle1`, `fix`, `cycle2`, `resolution`, `verify_full`, or `pass`

---

## Variables (substitute before dispatch)

| Variable | Description | Example |
|----------|-------------|---------|
| `${STORY_ID}` | Story to reconcile | `S1-007` |
| `${BASE_BRANCH}` | Integration branch for diffs | `feature/slice4-cherry-pick` |
| `${HEAD}` | Current git HEAD sha | `abc1234` |
| `${SLICE_ID}` | Slice containing the story | `S1` |

---

## Governing Documents (5 files — read on demand, not all at once)

| Document | Path | When to read |
|----------|------|-------------|
| **Process Index + R1 Prompt** | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | Always read first (quick links + mode selection). Read Appendix A for the full R1 audit prompt (source of truth). |
| **Runbook** | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | When executing any phase — contains operator instructions, step-by-step procedures, gate checks, artifact layout. |
| **Policy** | `reviews/premortems/PREMORTEM_RECON_POLICY.md` | When assigning verdicts, checking gates, validating schemas. Contains all verdict definitions, escalation rules, evidence checklists, debt register schema. |
| **Anti-Patterns** | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | During reviews (Cycle 1/2). Contains 26 cataloged anti-patterns with cross-reference chains and reviewer checklist extract. |
| **Metrics & Reference** | `reviews/premortems/PREMORTEM_RECON_METRICS.md` | For worked examples (S1-007 evidence ledger, gap entry format), agent grouping patterns, lessons learned, changelog. |

**Reading strategy**: Read the Process Index first (short). Then read only the document relevant to your current phase. Do not load all 5 into context simultaneously.

---

## Inputs

**Required:**
- `${STORY_ID}` — the story to reconcile
- `plans/prd.json` — story entry (`jq '.stories["${STORY_ID}"]' plans/prd.json`)
- `specs/CONTRACT.md` — relevant AT clauses

**Conditionally required:**
- `reviews/premortems/${STORY_ID}_premortem.md` — required for Mode B (write in Mode A if missing)
- `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` — required for Mode A

---

## Task

### 0) Mode Selection

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §0 (Mode Selection).

Determine mode based on current state:

| Situation | Mode |
|-----------|------|
| Code not implemented yet | **Mode A** (Premortem Authoring) |
| Code exists, premortems exist | **Mode B** (Reconciliation) |
| Code exists, no premortems | **Mode A** then **Mode B** |
| Retroactive audit of entire slice | Mode A (batch) then Mode B (batch) |
| Single story, MED/HIGH risk | Mode A (abbreviated: 1 writer + 2 cross-reviewers) then Mode B |
| Single story, LOW risk | Mode A (1 writer + lead eval) then Mode B |

If ambiguous, present the current state to the operator (does premortem exist? does code exist?) and ask which mode to execute.

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

**Step Supervisor Mapping (wf_step.sh → recon phases):**

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

**Phase-specific reading:**
- **R1 (preflight):** Read Appendix A in `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` — it contains the full R1 agent prompt (source of truth for the read-only audit).
- **R5 (remediation):** Read `plans/prompts/slice_reconcile_implement.md` or `plans/step_prompts/recon/implement.md`.
- **R5b (self-review):** Read `plans/step_prompts/recon/self_review.md`. Run the 5-skill stack: `/pr-review` → `/failure-mode-review` → `/strategic-failure-review` → `/contract-review` → `/devils-advocate`.
- **Verdicts:** Read `reviews/premortems/PREMORTEM_RECON_POLICY.md` §2 (Verdict Systems).
- **Reviews:** Read `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` — especially the Top 5 Most Dangerous and the Reviewer Checklist Extract at the bottom.

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

---

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

---

## Artifact Layout

Read `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §6 for the canonical directory layout.

All reconciliation artifacts go under `reviews/reconciliations/${SLICE_ID}/` with deterministic, phase-prefixed names. Key locations:

```
reviews/reconciliations/${SLICE_ID}/
  ${STORY_ID}_reconciliation.md          # R1 evidence ledger
  GAP_LIST.json / GAP_LIST.md            # R4 gap synthesis
  SELF_REVIEW_R5b.md                     # R5b self-review
  R6_VERIFY_SUMMARY.json                 # R6 final verdict
  DEBT_REGISTER.json                     # R7f debt tracking
  external/cycle1/${STORY_ID}/           # R3B external reviews
  external/cycle2/${STORY_ID}/           # R7d.1 external reviews
  receipts/                              # R5b skill receipts

artifacts/story/${STORY_ID}/
  proof_graph.json                       # Machine-verifiable proof graph
```

---

## Output

Depends on the phase executed. At minimum every phase must produce:
- **Gate result**: GO / NO-GO with reason
- **Phase artifacts**: As specified by the Runbook for the executed phase
- **Next step**: What comes next in the workflow
- **Receipt**: `plans/wf_step.sh ${STORY_ID} <step>` (when applicable)

---

## Hard Constraints

- Follow the Runbook phase-by-phase — do not skip phases
- Consult Policy for any verdict or gate decision
- Check Anti-Patterns before and during reviews
- Every file:line citation must be verified (no fake citations — Anti-Pattern #12)
- R1 is READ-ONLY — no file modifications allowed
- R5 fixes only listed gaps — no unrelated refactors
- Cycle 1 scope is STORY_SCOPE, Cycle 2 scope is FIX_DIFF + AT_REGRESSION
- Every review artifact must include the Review Basis line
- Provenance headers required on all review artifacts (5 mandatory fields — see Runbook §6.2)

---

## Dispatch Examples

### Claude Code
```
/reconcil S1-007
```

### Codex / other agents
```bash
# Substitute variables and feed as system prompt
STORY_ID=S1-007 BASE_BRANCH=feature/slice4-cherry-pick HEAD=$(git rev-parse HEAD) \
  envsubst < plans/prompts/reconcil.md | agent-run --prompt -
```

### Step supervisor integration
```bash
# The step supervisor dispatches per-step prompts from plans/step_prompts/recon/
# This orchestrator prompt is for standalone or manual use
plans/step_supervisor.sh S1-007 next
```
