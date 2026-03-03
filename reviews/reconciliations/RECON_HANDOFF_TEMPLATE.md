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
| **INDEX** — step cards + debrief policy | `plans/step_prompts/recon/INDEX.md` | Read first. Links to all 8 step cards. Defines debrief policy (GREEN = one line; YELLOW/RED = full ToC). |
| **RUNBOOK** — step-by-step operator instructions | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` | Reference only. Consult for escalation policy, debt register rules, verdict enum. Not required for normal execution. |
| **POLICY** — verdicts, gates, schemas | `reviews/premortems/PREMORTEM_RECON_POLICY.md` | When you need to know what a verdict means, what a gate checks, or what a schema requires. |
| **INDEX + R1 PROMPT** — Appendix A is the canonical R1 audit prompt | `reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md` | When running Step 1 (preflight/R1). Appendix A is the exact prompt to follow. |
| **ANTI-PATTERNS** — 26 failure modes to avoid | `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md` | When reviewing code or writing verdicts. Top 5 are: paper enforcement, skip R7c, fake citation, single-prompt review, blanket --theirs. |
| **STEP MAPPING** — wf_step ↔ R-phase canonical table | `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md` §3 | If step headers below conflict with RUNBOOK §3, RUNBOOK wins. |
| **METRICS + EXAMPLES** — worked examples, lessons learned | `reviews/premortems/PREMORTEM_RECON_METRICS.md` | When you need a worked example (e.g. S1-007 evidence ledger) or want to understand why a rule exists. |

### Quick Orientation

- Stories live in `plans/prd.json` under `.stories["{{STORY_ID}}"]`
- Premortems are at `reviews/premortems/{{STORY_ID}}_premortem.md`
- Reconciliation artifacts go under `reviews/reconciliations/{{SLICE_ID}}/`
- Story artifacts (proof graph, postmortem) go under `artifacts/story/{{STORY_ID}}/`
- Receipts track step completion: `.wf/receipts/{{STORY_ID}}/`
- For cross-worktree portability of slice artifacts, use `plans/recon_bundle.sh` commands documented in `RUNBOOK_PREMORTEM_RECON.md` §6.1.1
- **Never modify production code outside of Step 2 (implement/R5) and Step 5 (fix/R7c-fix)**

### Operator / Executor Mode (when enabled)

- Operator:
  - orchestrates steps, validates receipts/artifacts, updates handoff + scoreboard, decides GO/NO-GO
  - runs external reviewers (C1/C2) independently from executor
- Executor:
  - performs current step work
  - provides mandatory step report with forced admissions

Mandatory step report fields (fail-closed if missing/hand-wavy):
1. exact commands run
2. files created/modified
3. strongest evidence produced (one item)
4. what was not done that step required (forced admission)

---

> **How to use this file**
> 1. Copy to `reviews/reconciliations/{{SLICE_ID}}/HANDOFF.md` at slice start.
> 2. Fill placeholders as you complete each step. Replace `{{...}}` with real values.
> 3. When context is running low, jump to the **HANDOFF** section at the bottom, fill it, and stop.
> 4. Next agent: read **HANDOFF** first, then only the artifacts listed under "Must read".

---

> **Step update discipline (fast, mandatory)**
> 1. After every step attempt (pass or fail): update the step header lines (Status / Receipt / Gate / key artifact paths).
> 2. Update the Story Status Matrix row for the story you touched.
> 3. If the step is a **hard-evidence gate** (Preflight, Self-review, External C1/C2, Verify), fill the Evidence/Proof lines with **PASS/FAIL + paths**.
>
> **Clean step = one line**: `Status: COMPLETE · §0: CLEAN · Artifacts: <paths>`
> **Only expand §§1–11 when** the gate is blocked or you hit friction worth promoting to the Process Backlog.
> **Skipping when friction exists = the next agent hits the same wall you just hit.**
>
> Debrief sections are HANDOFF-specific and not part of RUNBOOK gate checks. They help the next agent; they do not block pass-flip.
>
> **Debrief sections at a glance**
> - §0  One-line outcome + workstream/contract area
> - §1  Constraint triad — Exploit · Subordinate · Elevate
> - §2  Evidence & Proof — CR-IDs, test output lines, artifact paths
> - §3  Guesses & Assumptions — what you assumed that might be wrong
> - §4  Friction Log — top 3 time/token sinks
> - §5  Failure modes hit
> - §6  Conflict & Change Zoning — story/contract conflicts, scope changes
> - §7  Reuse — patterns, skills applied
> - §8  Proposal — `rule / trigger / prevents / enforce`
> - §9  Concrete Elevation Plan — elevate + 2 subordinate wins (owner · effort · gain · proof)
> - §10 Enforcement Path — how the elevation gets locked in
> - §11 Apply or it didn't happen — YES with what / NO with debt register entry

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
Refresh this matrix from `plans/recon_scoreboard.sh <SLICE_ID>` each time you update handoff.

PATH signal notes (for scoreboard consistency):
- Prefer JSON-first evidence ledgers (`evidence_ledger.json` / `<STORY_ID>_reconciliation.json`).
- If JSON is invalid/unusable, scoreboard falls back to markdown `PATH:` scanning.
- Keep markdown ledgers with `PATH: GREEN|YELLOW` as the first line for prompt compatibility.

| Story | preflight | implement | self_review | cycle1 | fix | cycle2 | resolution | verify_full | pass |
|-------|-----------|-----------|-------------|--------|-----|--------|------------|-------------|------|
| {{S1}} | · | · | · | · | · | · | · | · | · |
| {{S2}} | · | · | · | · | · | · | · | · | · |
| {{S3}} | · | · | · | · | · | · | · | · | · |

---

## Per-Story Work Log

<!-- One section per story. Copy the block below for each story. -->

---

### {{STORY_ID}}

**Premortem**: `reviews/premortems/{{STORY_ID}}_premortem.md` — STOPLIGHT: {{GREEN/YELLOW/RED}}
**Risk routing**: `risk_tier={{low/med/high}}` · `routing={{full/low-risk-heuristic}}` · `escalated_to_full={{true/false}}` {{trigger if true}}

#### Hard Evidence Summary (fail-closed gates only)

| Gate | Artifact | Validation command | Status |
|------|----------|--------------------|--------|
| A Preflight | `reviews/reconciliations/{{SLICE_ID}}/{{STORY_ID}}_reconciliation.md` | (n/a) | {{PASS/FAIL}} |
| B Self-review | `reviews/reconciliations/{{SLICE_ID}}/R5B_SELF_REVIEW_GATE.json` + `reviews/reconciliations/{{SLICE_ID}}/receipts/r5b_*.json` (count={{N}}) | (n/a) | {{PASS/FAIL}} |
| C External C1 | `reviews/reconciliations/{{SLICE_ID}}/external/cycle1/{{STORY_ID}}/R3_EXTERNAL_MANIFEST.json` + sidecar | `./plans/validators/validate_external_manifest.py <manifest>` | {{PASS/FAIL}} |
| C2 External C2 | `reviews/reconciliations/{{SLICE_ID}}/external/cycle2/{{STORY_ID}}/R7_EXTERNAL_MANIFEST.json` + sidecar | `./plans/validators/validate_external_manifest.py <manifest>` | {{PASS/FAIL/NA}} |
| D Verify | `reviews/reconciliations/{{SLICE_ID}}/verify_full/{{STORY_ID}}/verify_tail.txt` + `verify.meta.json` | (n/a) | {{PASS/FAIL}} |

#### Step 1 · preflight (R1 — read-only audit)

- Reference: RUNBOOK §3 → R1 · R1 prompt: `plans/step_prompts/recon/r1_audit.md` (derived from Appendix A; if absent, fall back to `PREMORTEM_RECONCILIATION_PROCESS.md` Appendix A)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/00_preflight.json`
- Evidence ledger: `reviews/reconciliations/{{SLICE_ID}}/{{STORY_ID}}_reconciliation.md`
- Evidence check: ledger exists + non-empty: {{PASS/FAIL}}
- Gate: {{GO / NO-GO}}
- AT verdicts (one line each):
  - `{{AT-ID}}`: {{PROVEN / WEAK_PROOF / CLAIMED_NOT_PROVEN}} — {{one-line note}}
- Gaps found: {{none / list GAP-IDs}}
- Notes: {{anything the next agent needs to know}}

> **Step 1 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 2 · implement (R5 — code fixes)

- Reference: RUNBOOK §3 → R5 (steps 0–2: context build → remediation plan → implement)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED / SKIPPED-GREEN}}
- Receipt: `.wf/receipts/{{STORY_ID}}/01_implement.json`
- Remediation plan: `reviews/reconciliations/{{SLICE_ID}}/R5_REMEDIATION_PLAN.md`
- Remediation notes: `reviews/reconciliations/{{SLICE_ID}}/R5_REMEDIATION_NOTES.md`
- Recon relaxation: {{implement_diff_check_skipped / n/a}}
- Fixes applied: {{none / list GAP-IDs or findings}}
- Files changed: {{list paths}}
- Notes: {{anything the next agent needs to know}}

> **Step 2 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 3 · self_review (R5b — 6-skill stack)

- Reference: RUNBOOK §3 → R5b (4 phases: R5b.1 parallel reviews → R5b.2 planner → R5b.3 fixer → R5b.4 re-run)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/02_self_review.json`
- Gate artifact: `reviews/reconciliations/{{SLICE_ID}}/R5B_SELF_REVIEW_GATE.json`
- Skill receipts: `reviews/reconciliations/{{SLICE_ID}}/receipts/r5b_*.json`
- Evidence check: >=6 `r5b_*.json` receipts present (count={{N}}): {{PASS/FAIL}}
- Path taken: {{A — fixes needed / B — no fixes needed}}
- Fix plan: `reviews/reconciliations/{{SLICE_ID}}/R5B_FIX_PLAN.md` {{exists / n/a}}
- Fix log: `reviews/reconciliations/{{SLICE_ID}}/R5B_FIX_LOG.md` {{exists / n/a}}
- Finding counts: P0={{N}} P1={{N}} P2={{N}}
- Notes: {{anything the next agent needs to know}}

> **Step 3 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 4 · cycle1 (R2+R3+R4+R4b — external review)

- Reference: RUNBOOK §3 → R2 (lead eval) · R3 (cross-review + external dual-prompt) · R4 (gap synthesis) · R4b (finding mapping)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/03_cycle1.json`
- External manifest: `reviews/reconciliations/{{SLICE_ID}}/external/cycle1/{{STORY_ID}}/R3_EXTERNAL_MANIFEST.json`
- Manifest validation: `./plans/validators/validate_external_manifest.py reviews/reconciliations/{{SLICE_ID}}/external/cycle1/{{STORY_ID}}/R3_EXTERNAL_MANIFEST.json` — {{PASS/FAIL}}
- Tools run: {{e.g. codex,kimi / codex,opus,kimi}}
- Tool omissions + reason: {{none / opus unavailable / quota / intentional tradeoff}}
- Per-tool run evidence (required): {{for each tool include command, exit code, timed_out true/false, artifact path, sidecar present/absent}}
- Rerun rule (if fixes applied after C1): new run_id + new manifest sha required: {{YES/NO/NA}}
- Gap list: `reviews/reconciliations/{{SLICE_ID}}/GAP_LIST.json`
- External mapping: `reviews/reconciliations/{{SLICE_ID}}/R4B_EXTERNAL_MAPPING.json`
- Escalation path: {{GREEN — 0 findings / YELLOW — findings exist}}
- Top gaps (P0/P1 only): {{none / list with IDs}}
- Notes: {{anything the next agent needs to know}}

> **Step 4 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 5 · fix (R7a + risk-gate R7b + R7c reviews → R7c-fix)

- Reference: RUNBOOK §3 → R7a (contract review) · risk-gate R7b (strategic review; conditional for HIGH/shared-primitive stories) · R7c (wiring audit) · R7c-fix (apply findings)
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED / SKIPPED-GREEN}}
- Receipt: `.wf/receipts/{{STORY_ID}}/04_fix.json`
- Contract review: `reviews/reconciliations/{{SLICE_ID}}/R7A_CONTRACT_REVIEW.json` — decision: {{PASS/FAIL}}
- Strategic review: `reviews/reconciliations/{{SLICE_ID}}/R7B_STRATEGIC_REVIEW.md` {{exists / n/a (risk < HIGH)}}
- Wiring audit: `reviews/reconciliations/{{SLICE_ID}}/R7C_WIRING_AUDIT.json`
- Fix plan: `reviews/reconciliations/{{SLICE_ID}}/R7C_FIX_PLAN.md` {{exists / n/a}}
- Fix notes: `reviews/reconciliations/{{SLICE_ID}}/R7C_FIX_NOTES.md` {{exists / n/a}}
- Fixes applied: {{none / list GAP-IDs or findings}}
- Files changed: {{list paths}}
- Notes: {{anything the next agent needs to know}}

> **Step 5 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 6 · cycle2 (R7d+R7e+R7f — post-fix audit)

- Reference: RUNBOOK §3 → R7d (external C2 + code-review-expert) · R7e (devils advocate + cargo mutants) · R7f (debt register validation) · POLICY §4.4 for GREEN/YELLOW path rules
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/05_cycle2.json`
- Recon relaxation: {{min_reviews_relaxed_to_1 / n/a}}
- External manifest C2: `reviews/reconciliations/{{SLICE_ID}}/external/cycle2/{{STORY_ID}}/R7_EXTERNAL_MANIFEST.json`
- Manifest validation C2: `./plans/validators/validate_external_manifest.py <manifest>` — {{PASS/FAIL/NA}}
- C2 review basis evidence: {{artifact path containing `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`}}
- Tools run: {{e.g. codex / codex,kimi / codex,opus,kimi}}
- Tool omissions + reason: {{none / opus unavailable / quota / intentional tradeoff}}
- Per-tool run evidence (required): {{for each tool include command, exit code, timed_out true/false, artifact path, sidecar present/absent}}
- Scope: {{FIX_DIFF / FULL_STORY}} (must match proof)
- Devils advocate: `reviews/reconciliations/{{SLICE_ID}}/R7E_DEVILS_ADVOCATE.md`
- Debt register: `reviews/reconciliations/{{SLICE_ID}}/DEBT_REGISTER.json` {{valid / invalid / pending}} — R7f failures block pass-flip (Step 9), not this receipt
- Notes: {{anything the next agent needs to know}}

> **Step 6 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 7 · resolution (R6 — final verdict)

- Reference: RUNBOOK §3 → R6 · resolution template: `plans/review_resolution_template.md` · postmortem template: `plans/postmortem_template.md`
- Status: {{NOT_STARTED / IN_PROGRESS / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/06_resolution.json`
- Verify summary: `reviews/reconciliations/{{SLICE_ID}}/R6_VERIFY_SUMMARY.json`
- Review resolution: `artifacts/story/{{STORY_ID}}/review_resolution.md` — `Blocking addressed: {{YES/NO}}`
- Story verdict: {{RECONCILED / RECONCILED-WITH-DEBT / RECONCILED_UNIT_ONLY / NOT RECONCILED}}
- Postmortem: `artifacts/story/{{STORY_ID}}/postmortem.md` {{required+done / exempt (GREEN path = exempt)}}
- Proof graph: `artifacts/story/{{STORY_ID}}/proof_graph.json` {{valid / invalid / pending}}
- Decision file: `reviews/reconciliations/{{SLICE_ID}}/DECISION.json` {{exists / n/a}}
- Notes: {{anything the next agent needs to know}}

> **Step 7 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 8 · verify_full

- Reference: RUNBOOK §3 → verify_full · run: `PREFLIGHT_TIMEOUT=1200 ./plans/verify.sh full`
- Status: {{NOT_STARTED / COMPLETE / BLOCKED}}
- Receipt: `.wf/receipts/{{STORY_ID}}/07_verify_full.json`
- verify.meta.json HEAD: {{sha}}
- Latest verify artifact dir: `artifacts/verify/{{run_id}}/`
- verify output tail: `reviews/reconciliations/{{SLICE_ID}}/verify_full/{{STORY_ID}}/verify_tail.txt` {{exists/missing}}
- FAILED_GATE: {{none / <gate_name>}}
- Result: {{PASS / FAIL}}

> **Step 8 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

#### Step 9 · pass

- Reference: RUNBOOK §4 (Pass-Flip Gate — 14 checks) · POLICY §3.9 · run: `./plans/prd_set_pass.sh {{STORY_ID}} true`
- Status: {{NOT_STARTED / COMPLETE / SKIPPED-GREEN}}
- Receipt: `.wf/receipts/{{STORY_ID}}/08_pass.json`
- Path: {{GREEN — no re-flip / YELLOW — prd_set_pass.sh re-run}}
- Decision file: `reviews/reconciliations/{{SLICE_ID}}/DECISION.json` {{exists / n/a}}
- Result: {{passes=true confirmed / blocked by: {{reason}}}}

> **Step 9 debrief** · Write `§0: CLEAN` if no findings/friction. Only expand §1–§11 when blocked or friction worth promoting. See debrief sections guide above.

---

<!-- Repeat the above block for each story -->

---

## Process Backlog

> Promote here when a §8/§9 entry from any step debrief reveals a **recurring or structural** issue.
> P0 = blocks progress · P1 = causes repeated rework · P2 = friction/confusion only.
> The next slice's lead agent reads this first and must file patches/tickets for all P0/P1 entries
> before starting Step 1 on the first story. If it's not here, it didn't happen.

| # | Step | §8 rule (condensed) | Severity | Fix target | Owner | §11 status |
|---|------|---------------------|----------|-----------|-------|-----------|
| 1 | {{step}} | `rule: … · trigger: … · prevents: … · enforce: …` | {{P0/P1/P2}} | {{RUNBOOK / POLICY / tooling / template}} | {{owner}} | {{open / applied}} |

---

## HANDOFF

> **Next agent: start here.** Read this section before opening any other file.

### Stopped at

- Story: `{{STORY_ID}}`
- Step: `{{step name}}`
- Status: `{{what was done / what is mid-flight}}`
- HEAD at stop: `{{git sha}}`

### Hard-evidence status at stop

| Gate | Status | Missing artifact (if FAIL/NA) |
|------|--------|-------------------------------|
| A Preflight | {{PASS/FAIL/NA}} | {{path or none}} |
| B Self-review | {{PASS/FAIL/NA}} | {{path or none}} |
| C External C1 | {{PASS/FAIL/NA}} | {{path or none}} |
| C2 External C2 | {{PASS/FAIL/NA}} | {{path or none}} |
| D Verify | {{PASS/FAIL/NA}} | {{path or none}} |

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
/reconcil
# Optional mechanical status check:
plans/wf_step.sh {{STORY_ID}} --status
```

---

### §1 Constraint (ONE)

> The single biggest constraint that slowed this session. If the session was clean, write "None."

- **How it manifested** (2–3 concrete symptoms):
  -
  -
- **Time/token drain it caused**:
- **Workaround I used (exploit)**:
- **Next-agent default behavior (subordinate)**:
- **Permanent fix proposal (elevate)**:
- **Smallest increment**:
- **Validation** (metric, fewer reruns, faster command, fewer flakes):

### §2 Follow-up

> Given what I built, what's the single best follow-up and what 1–3 upgrades are worth considering next?

- Best follow-up:
- Upgrades worth considering:
  1.
  2.

### §3 Enforceable rules

> Given the pain I hit (top sinks + failure modes), what 1–3 rules should we add so the next agent doesn't repeat it?

1.
2.
