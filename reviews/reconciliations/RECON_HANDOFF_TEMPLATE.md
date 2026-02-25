# Reconciliation Handoff — {{SLICE_ID}}

---

## Your Role (read this first)

You are a **Reconciliation Agent** working on `{{SLICE_ID}}`.

Your job is to retroactively audit already-passing PRD stories through a 9-step workflow —
verifying that each story's contract claims are actually proven in code, fixing any gaps you
find, and producing machine-verifiable proof artifacts. You are NOT re-implementing anything.
You are auditing what shipped and forcing corrections where needed.

**Operating principle**: If a story can't survive the same workflow it would face today, it
doesn't deserve `passes=true`.

### Source-of-Truth Documents (read before starting any step you're unfamiliar with)

| Document | Path | When to read |
|----------|------|-------------|
| **RUNBOOK** — step-by-step operator instructions | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | Your primary reference. Read the section for any step you're about to run. |
| **POLICY** — verdicts, gates, schemas | `reviews/premortems/PREMORTEM_RECON_POLICY.md` | When you need to know what a verdict means, what a gate checks, or what a schema requires. |
| **INDEX + R1 PROMPT** — Appendix A is the canonical R1 audit prompt | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | When running Step 1 (preflight/R1). Appendix A is the exact prompt to follow. |
| **ANTI-PATTERNS** — 26 failure modes to avoid | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | When reviewing code or writing verdicts. Top 5 are: paper enforcement, skip R7c, fake citation, single-prompt review, blanket --theirs. |
| **METRICS + EXAMPLES** — worked examples, lessons learned | `reviews/premortems/PREMORTEM_RECON_METRICS.md` | When you need a worked example (e.g. S1-007 evidence ledger) or want to understand why a rule exists. |

### Quick Orientation

- Stories live in `plans/prd.json` under `.stories["{{STORY_ID}}"]`
- Premortems are at `reviews/premortems/{{STORY_ID}}_premortem.md`
- Reconciliation artifacts go under `reviews/reconciliations/{{SLICE_ID}}/`
- Story artifacts (proof graph, postmortem) go under `artifacts/story/{{STORY_ID}}/`
- Receipts track step completion: `.wf/receipts/{{STORY_ID}}/`
- **Never modify production code outside of Step 2 (implement/R5) and Step 5 (fix/R7c-fix)**

---

> **How to use this file**
> 1. Copy to `reviews/reconciliations/{{SLICE_ID}}/HANDOFF.md` at slice start.
> 2. Fill placeholders as you complete each step. Replace `{{...}}` with real values.
> 3. When context is running low, jump to the **HANDOFF** section at the bottom, fill it, and stop.
> 4. Next agent: read **HANDOFF** first, then only the artifacts listed under "Must read".

---

## Slice Context

| Field | Value |
|-------|-------|
| Slice ID | {{SLICE_ID}} |
| Integration branch | {{BASE_BRANCH}} |
| Stories in scope | {{STORY_LIST e.g. S1-001, S1-002, S1-003}} |
| Started | {{YYYY-MM-DD}} |
| Last updated | {{YYYY-MM-DD}} |

---

## Story Status Matrix

Fill as you go. Symbols: `·` not started · `→` in progress · `✓` done · `✗` blocked

| Story | preflight | implement | self_review | cycle1 | fix | cycle2 | resolution | verify | pass |
|-------|-----------|-----------|-------------|--------|-----|--------|------------|--------|------|
| {{S1}} | · | · | · | · | · | · | · | · | · |
| {{S2}} | · | · | · | · | · | · | · | · | · |
| {{S3}} | · | · | · | · | · | · | · | · | · |

---

## Per-Story Work Log

<!-- One section per story. Copy the block below for each story. -->

---

### {{STORY_ID}}

**Premortem**: `reviews/premortems/{{STORY_ID}}_premortem.md` — STOPLIGHT: {{GREEN/YELLOW/RED}}

#### Step 1 · preflight (R1 — read-only audit)

- Reference: RUNBOOK §3 → R1 · R1 prompt (canonical): `PREMORTEM_RECONCILIATION_PROCESS.md` Appendix A
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/00_preflight.json`
- Evidence ledger: `reviews/reconciliations/{{SLICE_ID}}/{{STORY_ID}}_reconciliation.md`
- Gate: {{GO / NO-GO}}
- AT verdicts (one line each):
  - `{{AT-ID}}`: {{PROVEN / WEAK_PROOF / CLAIMED_NOT_PROVEN}} — {{one-line note}}
- Gaps found: {{none / list GAP-IDs}}
- Notes: {{anything the next agent needs to know}}

#### Step 2 · implement (R5 — code fixes)

- Reference: RUNBOOK §3 → R5 (steps 0–2: context build → remediation plan → implement)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED / SKIPPED-GREEN}}
- Receipt: `.wf/receipts/{{STORY_ID}}/01_implement.json`
- Remediation plan: `reviews/reconciliations/{{SLICE_ID}}/R5_REMEDIATION_PLAN.md`
- Remediation notes: `reviews/reconciliations/{{SLICE_ID}}/R5_REMEDIATION_NOTES.md`
- Recon relaxation: {{implement_diff_check_skipped / n/a}}
- Changes made: {{none / brief description}}
- Notes: {{anything the next agent needs to know}}

#### Step 3 · self_review (R5b — 6-skill stack)

- Reference: RUNBOOK §3 → R5b (4 phases: R5b.1 parallel reviews → R5b.2 planner → R5b.3 fixer → R5b.4 re-run)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/02_self_review.json`
- Gate artifact: `reviews/reconciliations/{{SLICE_ID}}/R5B_SELF_REVIEW_GATE.json`
- Skill receipts: `reviews/reconciliations/{{SLICE_ID}}/receipts/r5b_*.json`
- Path taken: {{A — fixes needed / B — no fixes needed}}
- Fix plan: `reviews/reconciliations/{{SLICE_ID}}/R5B_FIX_PLAN.md` {{exists / n/a}}
- Fix log: `reviews/reconciliations/{{SLICE_ID}}/R5B_FIX_LOG.md` {{exists / n/a}}
- Finding counts: P0={{N}} P1={{N}} P2={{N}}
- Notes: {{anything the next agent needs to know}}

#### Step 4 · cycle1 (R2+R3+R4+R4b — external review)

- Reference: RUNBOOK §3 → R2 (lead eval) · R3 (cross-review + external dual-prompt) · R4 (gap synthesis) · R4b (finding mapping)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/03_cycle1.json`
- External manifest: `reviews/reconciliations/{{SLICE_ID}}/external/cycle1/{{STORY_ID}}/R3_EXTERNAL_MANIFEST.json`
- Gap list: `reviews/reconciliations/{{SLICE_ID}}/GAP_LIST.json`
- External mapping: `reviews/reconciliations/{{SLICE_ID}}/R4B_EXTERNAL_MAPPING.json`
- Escalation path: {{GREEN — 0 findings / YELLOW — findings exist}}
- Top gaps (P0/P1 only): {{none / list with IDs}}
- Notes: {{anything the next agent needs to know}}

#### Step 5 · fix (R7a+R7b+R7c reviews → R7c-fix)

- Reference: RUNBOOK §3 → R7a (contract review) · R7b (strategic review) · R7c (wiring audit) · R7c-fix (apply findings)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED / SKIPPED-GREEN}}
- Receipt: `.wf/receipts/{{STORY_ID}}/04_fix.json`
- Contract review: `reviews/reconciliations/{{SLICE_ID}}/R7A_CONTRACT_REVIEW.json` — decision: {{PASS/FAIL}}
- Strategic review: `reviews/reconciliations/{{SLICE_ID}}/R7B_STRATEGIC_REVIEW.md`
- Wiring audit: `reviews/reconciliations/{{SLICE_ID}}/R7C_WIRING_AUDIT.json`
- Fix plan: `reviews/reconciliations/{{SLICE_ID}}/R7C_FIX_PLAN.md` {{exists / n/a}}
- Changes made: {{none / brief description}}
- Notes: {{anything the next agent needs to know}}

#### Step 6 · cycle2 (R7d+R7e+R7f — post-fix audit)

- Reference: RUNBOOK §3 → R7d (external C2 + code-review-expert) · R7e (devils advocate + cargo mutants) · R7f (debt register validation) · POLICY §4.4 for GREEN/YELLOW path rules
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/05_cycle2.json`
- Recon relaxation: {{min_reviews_relaxed_to_1 / n/a}}
- External manifest C2: `reviews/reconciliations/{{SLICE_ID}}/external/cycle2/{{STORY_ID}}/R7_EXTERNAL_MANIFEST.json`
- Devils advocate: `reviews/reconciliations/{{SLICE_ID}}/R7E_DEVILS_ADVOCATE.md`
- Debt register: `reviews/reconciliations/{{SLICE_ID}}/DEBT_REGISTER.json` {{valid / invalid / pending}}
- Notes: {{anything the next agent needs to know}}

#### Step 7 · resolution (R6 — final verdict)

- Reference: RUNBOOK §3 → R6 · resolution template: `plans/review_resolution_template.md` · postmortem template: `plans/postmortem_template.md`
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/06_resolution.json`
- Verify summary: `reviews/reconciliations/{{SLICE_ID}}/R6_VERIFY_SUMMARY.json`
- Review resolution: `artifacts/story/{{STORY_ID}}/review_resolution.md` — `Blocking addressed: {{YES/NO}}`
- Story verdict: {{RECONCILED / RECONCILED-WITH-DEBT / RECONCILED_UNIT_ONLY / NOT RECONCILED}}
- Postmortem: `artifacts/story/{{STORY_ID}}/postmortem.md` {{required+done / exempt}}
- Proof graph: `artifacts/story/{{STORY_ID}}/proof_graph.json` {{valid / invalid / pending}}
- Notes: {{anything the next agent needs to know}}

#### Step 8 · verify_full

- Reference: RUNBOOK §3 → verify_full · run: `./plans/verify.sh full`
- Status: {{NOT_STARTED / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/07_verify_full.json`
- verify.meta.json HEAD: {{sha}}
- Result: {{PASS / FAIL}}

#### Step 9 · pass

- Reference: RUNBOOK §4 (Pass-Flip Gate — 15 checks) · POLICY §3.9 · run: `./plans/prd_set_pass.sh {{STORY_ID}} true`
- Status: {{NOT_STARTED / COMPLETE / SKIPPED-GREEN}}
- Path: {{GREEN — no re-flip / YELLOW — prd_set_pass.sh re-run}}
- Result: {{passes=true confirmed / blocked by: {{reason}}}}

---

<!-- Repeat the above block for each story -->

---

## HANDOFF

> **Next agent: start here.** Read this section before opening any other file.

### Stopped at

- Story: `{{STORY_ID}}`
- Step: `{{step name}}`
- Status: `{{what was done / what is mid-flight}}`
- HEAD at stop: `{{git sha}}`

### What happened (2–5 bullets)

- {{key finding or decision made}}
- {{key finding or decision made}}
- {{any blocker or question left open}}

### Must read first (in order)

1. `{{path}}` — {{why: one line}}
2. `{{path}}` — {{why: one line}}
3. `{{path}}` — {{why: one line}}

### Next steps (exact actions)

1. {{concrete action — e.g. "Run `review_logged.sh S1-003 --tool codex --prompt enriched --base feature/slice4-cherry-pick`"}}
2. {{concrete action}}
3. {{concrete action}}

### Open decisions / blockers

- {{decision or blocker — none if clean handoff}}

### Resume command

```bash
STEP_SUPERVISOR_BASE_BRANCH={{BASE_BRANCH}} \
  plans/step_supervisor.sh {{STORY_ID}} prompt --recon
```
