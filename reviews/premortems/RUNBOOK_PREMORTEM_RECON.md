# Premortem + Reconciliation Runbook

> **REFERENCE ONLY.** Not required for normal execution.
> For step-by-step execution prompts, use `plans/step_prompts/recon/<step>.md`.
> For the debrief policy and card index, see `plans/step_prompts/recon/INDEX.md`.

> Operator instructions only. For verdict definitions and gate rules, see [POLICY](PREMORTEM_RECON_POLICY.md). For anti-patterns and lessons, see [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md). For metrics and rationale, see [METRICS](PREMORTEM_RECON_METRICS.md).

---

## 0) Mode Selection

| Situation | Mode |
|-----------|------|
| Code not implemented yet | Mode A (Premortem Authoring) |
| Code already exists, premortems exist | Mode B (Reconciliation) |
| Code exists, no premortems | Mode A then Mode B |
| Retroactive audit of entire slice | Mode A (batch) then Mode B (batch) |
| Single story, MED/HIGH risk | Mode A (abbreviated: 1 writer + 2 cross-reviewers) then Mode B |
| Single story, LOW risk | Mode A (1 writer + lead eval) then Mode B |

---

## 0b) LOW-Risk Routing Heuristic (Advisory, No Gate Exemptions)

Use this to reduce operator churn on clearly low-risk stories. This section does **not** weaken required gates, receipts, or pass-flip checks.

### LOW-risk screen (all must be true)

| # | Criterion | Quick check |
|---|-----------|-------------|
| 1 | Story risk is `low` in PRD | `jq -r '.items[] | select(.id=="<STORY_ID>") | .risk' plans/prd.json` |
| 2 | Scope is pure/typed logic (no runtime mutable state or I/O) | inspect `scope.touch` + enforcement callsites |
| 3 | Scope does not include safety-critical subsystems | confirm no TradingMode / RiskState / WAL / replay / dispatcher control paths |
| 4 | R1 found no P0 gaps | check evidence ledger gap table |

If any criterion fails, treat as FULL rigor immediately.

### Escalation triggers (immediate FULL rigor)

Any one trigger flips the story to FULL operating mode for remaining steps:
1. R1 finds a P0 gap.
2. External review finds P0/P1 gap.
3. Fix step touches production code in safety-critical paths.
4. New cross-story/shared-primitive coupling is discovered.

### Required routing note

Record routing decision and escalation events in handoff Step 1 notes:
- `risk_tier: <low|med|high>`
- `routing: <full|low-risk-heuristic>`
- `escalated_to_full: <true|false>` and trigger if true.

---

## 1) Hard Gates (Before Any Work)

### 1.1 Required Inputs

Must exist before any phase starts:

| Artifact | Required for |
|----------|-------------|
| `plans/prd.json` | Both modes |
| `specs/CONTRACT.md` | Both modes |
| `reviews/premortems/STORY_PREMORTEM_TEMPLATE.md` | Mode A |
| `reviews/premortems/<STORY-ID>_premortem.md` | Mode B |
| `scope.touch` files from PRD | Mode B |
| `implementation_tests[]` entries in PRD | Mode B |

If any required artifact is missing: **STOP. Emit `MISSING_ARTIFACT`. Do not continue.**

### 1.2 PREMORTEM_READY Gate (Mode B entry)

**Command**: `plans/premortem_ready.sh ${STORY_ID}`

Six checks, evaluated in order:

| # | Check | Failure | Exit |
|---|-------|---------|------|
| 1 | Premortem file exists | `NO-GO: PREMORTEM_MISSING` | Stop — write premortem first (Mode A). No surrogate path. |
| 2 | All sections §0-§10 present | `NO-GO: SECTIONS_MISSING` (delegates to `premortem_gate.sh`) | Stop |
| 3 | STOPLIGHT != RED | `NO-GO: STOPLIGHT_RED` | Stop |
| 4 | If STOPLIGHT is YELLOW: every gap marked DEFERRED or FIX IN STEP 5 | `NO-GO: UNRESOLVED_YELLOW_GAPS` | Stop |
| 5 | No AT ownership conflicts (no AT claimed as primary by 2+ stories) | `NO-GO: AT_OWNERSHIP_CONFLICT` | Stop |
| 6 | Required context files exist (CONTRACT.md, prd.json entry, scope.touch files) | `NO-GO: MISSING_ARTIFACT` | Stop (also enforced by §1.1) |

**Exit 0** = proceed. **Exit 1** = blocked (fix premortem first).

---

## 2) Mode A — Premortem Authoring (7 Phases)

### Phase 1 — Parallel Write

**Goal**: Produce one premortem per story.

**Steps**:
1. Create worktree on dedicated branch: `git worktree add ../wt_<name> -b premortem/<slice> main`
2. Group stories by shared files/dependencies into balanced batches
3. Assign writer agents by domain batch: `max(2, min(ceil(story_count / 2), 4))` agents, one per batch (min 2 required for cross-review in Phase 4; cap at 4)
4. Each writer creates `<STORY-ID>_premortem.md` filling §0-§10
5. Writers must NOT inspect implementation code

**Output**: `reviews/premortems/<STORY-ID>_premortem.md` for all stories

### Phase 2 — Lead Evaluation

**Goal**: Score batches, create patch list.

**Steps**:
1. Read all premortems
2. Score each batch on 7 criteria: template adherence, clause audit quality, failure-mode depth, wrong-impl gate, economic risk calibration, cross-story awareness, factual accuracy
3. Rate: PASS | PASS-WITH-ISSUES | NEEDS-PATCH | REJECT
4. Record file-level issues with category: `FACTUAL_ERROR` | `LOGIC_GAP` | `DEPTH_GAP` | `FORMATTING`
5. Flag any story where reviewers disagree by >1 level

**Output**: `phase2_lead_eval.json` + `phase2_patch_list.md`

### Phase 3 — Targeted Patch (Round 1)

**Goal**: Apply only flagged fixes.

**Rules**:
- No full rewrites — surgical edits only
- If fix changes >30% of a section → escalate to lead
- Verify after each edit (re-read file)

**Output**: Updated premortems + `phase3_patch_receipts/`

### Phase 4 — Cross-Review

**Goal**: Find systemic issues lead missed.

**Rules**:
- Each reviewer reviews ALL stories they did NOT write
- Reviewers must NOT review their own batch

**Required output per reviewer**:
- Scoring table (7 criteria per story)
- Strengths (2-3 with section refs)
- Weaknesses (2-3 with section refs)
- One actionable suggestion per story
- Systemic patterns summary

**Output**: `CROSS_REVIEW_by_<REVIEWER>.md` per reviewer

### Phase 5 — Synthesis

**Goal**: Merge cross-review findings into final fix list.

**Steps**:
1. Aggregate all cross-review outputs
2. Flag rating disagreements (>1 level)
3. Identify net-new findings (issues cross-reviewers found that lead missed)
4. Prioritize: `MUST_FIX` | `SHOULD_FIX` | `NICE_TO_HAVE`

**Output**: `phase5_synthesis.json` + `phase5_final_fix_list.md`

### Phase 6 — Final Patch (Round 2)

**Goal**: Apply synthesized fixes.

**Rules**: Same batch grouping as Phase 1. Same >30% escalation rule.

**Output**: Updated premortems + `phase6_patch_receipts/`

### Phase 7 — Verify

**Goal**: Confirm premortems are implementation-ready.

**Checklist**:
- [ ] All flagged fixes applied
- [ ] No new contradictions introduced
- [ ] STOPLIGHT honest (no GREEN with unresolved assumptions)
- [ ] AT ownership unambiguous (no AT claimed as primary by 2+ stories)
- [ ] Enforcement points reference true modules

**Output**: `phase7_verify_report.json` + `PREMORTEM_READY=true`

---

## 3) Mode B — Reconciliation (R1–R7)

Run `plans/wf_step.sh ${STORY_ID} <step>` to record step completion. Steps in order: preflight → implement → self_review → cycle1 → fix → cycle2 → resolution → verify_full → pass. Receipts: `.wf/receipts/<ID>/`.

> **Note**: R-phase numbers are a classification scheme, not execution order. The wf_step execution sequence is: preflight(R1) → implement(R5) → self_review(R5b) → cycle1(R2+R3+R4+R4b) → fix(R7a-c) → cycle2(R7d-f) → resolution(R6) → verify_full → pass.

### 3.0.1 Operator Cadence (mandatory)

After **every** wf_step attempt (pass or fail), update handoff before continuing:
1. Update story matrix symbol for the current step (`·` / `→` / `✓` / `✗`).
2. Update step header lines (`Status`, `Receipt`, `Gate`, key artifacts).
3. If blocked, record exact command + exit code + first failing line.
4. Rewrite HANDOFF footer (`Stopped at`, `What happened`, `Must read`, `Next steps`, `Resume command`).

This keeps continuation deterministic and prevents repeated blocker rediscovery.

### 3.0.2 Fast Preconditions (run before expensive gates)

| Target step | Precheck command | Expected |
|-------------|------------------|----------|
| `cycle1` | `plans/recon_evidence_ledger.sh <STORY_ID> --check` | Exit 0; evidence ledger present |
| `cycle2` | `WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> cycle2 --dry-run` | Exit 0; basis/coverage checks pass |
| `verify_full` | `./plans/verify.sh full` | Exit 0; latest verify artifact has no `FAILED_GATE` |

If precheck fails, fix it first; do not record the step receipt.

---

### R1 — Parallel Reconcile (Read-Only)

**Mode**: `READ_ONLY` (no file modifications)

**Inputs (required per story)**:
- `plans/prd.json` (story entry)
- `specs/CONTRACT.md` (relevant AT clauses)
- `reviews/premortems/<STORY_ID>_premortem.md`
- Story `scope.touch` files
- Proving test files from `implementation_tests[]`

**Precondition**: `plans/premortem_ready.sh ${STORY_ID}` exits 0
**Command**: Agent executes `plans/step_prompts/recon/preflight.md`
**Read-only check**: `git status --porcelain` at start and end must match

**Hard rules**:
- Premortem §10 STOPLIGHT must be checked before audit starts
- `git status --porcelain` must be clean at start and end of R1
- If any required artifact is missing → output `MISSING_ARTIFACT` and stop story audit
- If critical fail-open found → emit `EMERGENCY-P0` immediately (do not wait for R5)

**Operator steps (per story)**:
1. Read story proof scope (PRD + ATs + premortem §2/§4/§5 + code + tests)
2. Locate enforcement points (`file:line::fn`)
3. Locate proving tests (`file:line::test_fn`)
4. Validate causal proof (TRIP/NON-TRIP, reject_reason, dispatch_count, latch_reason)
5. Validate fail-closed behavior (all 6 categories incl. narrowing casts)
6. Validate premortem alignment: §2 assumptions, §4 decisions, §5 wrong-impl traps, §6 proof plan
7. Build gap list with priorities (P0/P1/P2/DEFERRED)
8. Assign interim per-AT verdict: PROVEN | WEAK_PROOF | CLAIMED_NOT_PROVEN | UNTESTED_ENFORCEMENT | WRONG_IMPL_UNBLOCKED | DEFERRED (see [POLICY](PREMORTEM_RECON_POLICY.md))
9. Assign story verdict = `PARTIAL` until R6

**Output**:
- `<STORY_ID>_reconciliation.md` (evidence ledger)
- `<STORY_ID>_reconciliation.json` (sidecar — gate fields only) [Wave 2: JSON-primary `evidence_ledger.json`]
- Validate: `plans/validate_recon_artifact.sh evidence_ledger <path>` # Wave 2 — schema not yet registered; skip until evidence_ledger added to validator
- `.wf/recon_scope_lock/<STORY_ID>.scope_lock.json` (R1 scope-lock artifact)
**Receipt**: `plans/wf_step.sh ${STORY_ID} preflight`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R1_READ_ONLY_INTEGRITY_OK` | `git status --porcelain` unchanged (start == end) |
| `R1_EVIDENCE_LEDGER_COMPLETE` | Artifact exists, contains per-AT table, contains citations for enforcement + test, contains gap section, contains story verdict |
| `R1_SCOPE_LOCK_CREATED` | Scope lock exists at `.wf/recon_scope_lock/<STORY_ID>.scope_lock.json` and matches scope in `plans/prd.json` |

**Blocking if**: `gate_result=NO-GO` or `read_only_violation=true`

---

### R2 — Lead Evaluation (Evidence Ledger QA)

**Mode**: `LEAD_REVIEW`

**Inputs**: All `*_reconciliation.md` ledgers from R1

**Operator steps**:
1. Spot-check citation accuracy — file:line is real and relevant (2-3 per story)
2. Re-calibrate verdicts (especially PROVEN vs WEAK_PROOF)
3. Validate safety-critical AT escalation rules (WEAK_PROOF on MED/HIGH → CLAIMED_NOT_PROVEN)
4. Reclassify mis-prioritized gaps (safety-critical gaps cannot be downgraded)
5. Flag cross-story inconsistency (same standard across batches)
6. Flag red flags: PROVEN with no file:line, PROVEN on §5 wrong-impl without tightening test, WEAK_PROOF treated as PROVEN
7. Produce correction requests for R1 ledgers if needed

**Output**:
- `R2_LEAD_EVAL.md` + `R2_LEAD_EVAL.json` (sidecar schema: `specs/schemas/recon/lead_eval_sidecar.schema.json`)
**Format**: Markdown + JSON sidecar

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R2_LEAD_EVAL_COMPLETE` | Artifact exists, lists all stories, each story: ACCEPTED or RETURN_TO_R1 |
| `R2_NO_UNREVIEWED_STORIES` | Story count in R2 artifact matches story count in batch |

---

### R3 — Cross-Review + External Review (Cycle 1: STORY_SCOPE)

**Mode**: `CYCLE1_EXTERNAL_AUDIT`
**Cycle scope (hard)**: `Review basis: STORY_SCOPE (Cycle 1)`

**Hard rules**:
- Cycle 1 review is story-scope, NOT diff-only
- Reviewers must NOT review their own batch
- Every review artifact must include: `Review basis: STORY_SCOPE (Cycle 1)`
- Every Cycle 1 review must cite at least one pre-existing enforcement point AND one pre-existing test (both outside the recon diff)
- If all citations are diff-only → `DIFF_ONLY_REVIEW_REJECTED`
- Cycle 1 commands may only run after preflight scope-lock capture succeeds for that story (`.wf/recon_scope_lock/<STORY_ID>.scope_lock.json`)
- If `plans/review_logged.sh` lacks sidecar-compatible output, fix/revert review logger first and re-run preflight cycle checks (`R3_EXTERNAL_MANIFEST` requires `review_artifact_sidecar`-compatible artifacts)

**Agent parallelism**:

| Sub-phase | Agent count | Parallelism model | Rationale |
|-----------|-------------|-------------------|-----------|
| R3A | min(batch_count, 3); single-story recon = 1 | 1 agent per batch; stories sequential within batch | Sequential-within-batch lets the reviewer detect cross-story patterns ("same gap in 3 of 4 stories"). Parallelizing within a batch loses that signal. |
| R3B | 1 dispatcher agent | Stories × tools in parallel; prompt styles (enriched, generic) sequential per tool | External calls are rate-limit-bound, not coordination-bound. Enriched runs first so generic doesn't duplicate its findings. |

- **Batch assignment**: Reuse R1 batch grouping. Each R3A agent reviews one batch they did NOT author.
- **Single-story recon**: 1 internal reviewer is sufficient (R1 and R3A are inherently different agents).
- **R3B scaling**: Add tools (codex, opus, kimi) for breadth; adding stories per tool is free parallelism.

#### R3A — Internal Cross-Review

**Inputs**: R1 evidence ledgers, full story proof scope

**Operator steps (per story)**:
1. Review evidence ledger against code/tests (not just ledger text)
2. Re-check AT causal proof and fail-closed behavior
3. Spot-check AT semantic match to CONTRACT clause (at least 1 AT per story)
4. Validate premortem §4/§5 alignment and wrong-impl blocking
5. Record disagreements and missed gaps

**Checklist per story**:
- [ ] AT causal proof (dispatch_count, reject_reason, latch_reason — not just `result.is_err()`)
- [ ] AT semantic match (re-read at least 1 AT anchor in CONTRACT.md per story)
- [ ] Premortem §4 decisions implemented as chosen
- [ ] Premortem §5 wrong impls blocked by tightening tests
- [ ] Premortem §2 assumptions turned into tests or killed
- [ ] Fail-closed on all 6 categories (Missing/None, NaN/Inf, Negative, Out-of-domain, Corrupt, Narrowing casts)
- [ ] Combinatorial coverage for multi-input functions
- [ ] Constants accuracy (comment matches literal value)
- [ ] Paper compliance (PRD claims match reality)

**Output**:
- `R3_RECONCILE_REVIEW_by_<REVIEWER>.md` per reviewer
- `R3_RECONCILE_REVIEW_by_<REVIEWER>.json` (sidecar; schema: `specs/schemas/recon/cross_review.schema.json`)

**Required contents**: Review basis line, per-story verdict agreement/disagreement, citation spot-checks, missed gaps, systemic patterns

#### R3B — External Review Cycle 1 (mandatory, dual-prompt)

**Commands (per story, exact)**:
```bash
plans/review_logged.sh <STORY_ID> --tool codex --prompt enriched --base <BASE_BRANCH>
plans/review_logged.sh <STORY_ID> --tool codex --prompt generic  --base <BASE_BRANCH>
```
Repeat with additional tools as available (opus, kimi). Minimum 1 tool, recommended 2+.
When refreshing only missing/failed C1 artifacts, use `plans/review_missing_refresh.sh` (slice-start default) to avoid unnecessary reruns.

**Tool coverage policy (explicit)**:
- Gate minimum: 1 tool.
- Operational default: 2 tools (`codex` + `kimi`).
- `opus` is strongly recommended when available.
- If `opus` is omitted, record the reason in Step 4 notes/handoff (quota, access, outage, or explicit risk tradeoff).

**Artifact recency rule**:
- Use the latest artifact per tool/prompt combination for gating decisions.
- Do not let stale historical artifacts override newer valid artifacts.

**Artifact requirements**:
- `review_logged.sh` outputs are normalized into canonical filenames (see [§6 Canonical Directory Layout](#6-artifact-layout--provenance)):
  - `<tool>.enriched.md` and `<tool>.generic.md` per tool
- Per-story manifest: `R3_EXTERNAL_MANIFEST.json` (source of truth, gate artifact)
- Per-story rendered summary: `R3_EXTERNAL_MANIFEST.md` (human-readable companion)

**JSON-first requirement**:
- `R3_EXTERNAL_MANIFEST.json` is the machine source; render `.md` from JSON via `plans/render_external_manifest.py`.
- Do not hand-edit rendered manifest companions.

**`R3_EXTERNAL_MANIFEST.json` schema (required fields)**:
```json
{
  "schema_version": "r3_external_manifest.v1",
  "head_commit": "<sha>",
  "created_at": "<ISO 8601>",
  "story_id": "<STORY_ID>",
  "cycle": "C1",
  "review_basis": "STORY_SCOPE (Cycle 1)",
  "tools": [
    {
      "tool": "codex",
      "model": "gpt-5.3",
      "artifacts": {
        "enriched": { "path": "codex.enriched.md", "exists": true },
        "generic":  { "path": "codex.generic.md",  "exists": true }
      }
    }
  ],
  "validation": {
    "status": "PASS",
    "review_basis_check": "PASS",
    "preexisting_enforcement_citation_check": "PASS",
    "preexisting_test_citation_check": "PASS",
    "diff_only_review_check": "PASS"
  }
}
```

**Validation contract**:
- **Command**: `./plans/verify_citations.sh --artifact <review_artifact> --mode C1 --json`
- **Input**: Cycle 1 review artifact path (`.md` or `.json`) with provenance metadata
- **Output JSON keys**: `validator`, `status`, `artifact`, `failure_codes`
- **Exit codes**:
  - `0` — pass
  - `1` — citation/validation failure
  - `2` — invalid input or schema/usage
  - `3` — infrastructure / I/O failure

**Blocking if**: missing basis line, pre-existing citation checks, or phase-mapping label checks (`exit 1`); malformed invocation/input (`exit 2`); or I/O/infra failure (`exit 3`)

#### R3 Gate Checks

| Gate ID | Check |
|---------|-------|
| `R3_INTERNAL_CROSS_REVIEW_COMPLETE` | All expected `R3_RECONCILE_REVIEW_by_<REVIEWER>.md` files exist; all contain `Review basis: STORY_SCOPE (Cycle 1)` |
| `R3_EXTERNAL_C1_COMPLETE` | One `R3_EXTERNAL_MANIFEST.json` per story; both prompt styles present per tool; review basis present in all artifacts; pre-existing enforcement + test citation checks pass |
| `R3_DIFF_ONLY_REVIEW_BLOCK` | Any `DIFF_ONLY_REVIEW_REJECTED` → blocks R4 |

---

### R4 — Synthesis + Gap List (Deterministic Aggregation)

**Mode**: `LEAD_SYNTHESIS_WITH_SCRIPTED_AGGREGATION`

**Inputs**: R3A internal cross-review artifacts, R3B external C1 artifacts/manifests, R1 evidence ledgers

**Hard rules**:
- Initial aggregation is scripted (lossless), not LLM-only
- "No gaps found" requires structured `coverage_proof`
- All deferred items must be captured in debt register draft

**Operator steps**:
1. Collect structured gap outputs from all R3 reviewers
2. Merge with deterministic script (dedupe by `story_id` + `at_id` + `gap_description`)
3. Merge R3B external C1 findings into the same unified set
4. Lead resolves conflicts: severity disputes, duplicate wording, systemic grouping
5. Assign final gap IDs: `GAP-<STORY-ID>-<SEQ>` or `GAP-SYSTEMIC-<SEQ>`
6. Assign priority: P0 | P1 | P2 | DEFERRED
7. Draft/update debt register entries for all DEFERRED items

**Output**:
- `GAP_LIST.json` (schema: `specs/schemas/recon/gap_list.schema.json`) — JSON-primary
- `GAP_LIST.md` (human-readable companion)
- `DEBT_REGISTER.json` (draft; final validated in R7f)
**Validate**: `plans/validate_recon_artifact.sh gap_list GAP_LIST.json`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R4_GAP_LIST_COMPLETE` | `GAP_LIST.md` and `GAP_LIST.json` both exist; every story has either gap entries or `coverage_proof` |
| `R4_NO_UNCHECKED_CLEAN_REVIEW` | No story with empty gaps and missing coverage proof |
| `R4_DEBT_DRAFT_COMPLETE` | Every DEFERRED gap has a matching debt entry stub (`gap_id` present) |

---

### R4b — External Review Finding Mapping (Anti-Gaming)

**Goal**: Confirm all external Cycle 1 review findings are represented in the gap list.

**Checklist**:
- [ ] Every external review finding maps to: `gap_id` OR `false_positive_justification`
- [ ] No unmapped P0/P1 findings
- [ ] Disagreements recorded with lead decision

**Output**:
- `R4B_EXTERNAL_MAPPING.json` (schema: `specs/schemas/recon/phase_mapping.schema.json`) — JSON-primary
- `R4B_EXTERNAL_MAPPING.md` (rendered summary)
**Validate**: `plans/validate_recon_artifact.sh phase_mapping R4B_EXTERNAL_MAPPING.json`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R4B_ALL_FINDINGS_MAPPED` | Every external finding has `gap_id` or `false_positive_justification` |
| `R4B_NO_UNMAPPED_P0_P1` | `unmapped_p0_p1_count == 0` |

**Blocking if**: unmapped P0/P1 finding exists

---

### R5 — Remediation (Fix Only the Gap List)

**Mode**: `WRITE_ALLOWED_GAP_REMEDIATION_ONLY`

**Agent**: Any available agent (need not be the R1 author). The R5 agent is assumed to be a cold-start session with no prior context.

**Inputs**: `GAP_LIST.json` / `GAP_LIST.md`, story code + tests, R1 evidence ledgers

**Hard rules**:
- Fix only listed gaps (no unrelated refactors)
- Every change must map to one or more `GAP-*` IDs
- New tests follow premortem §6 proof plan (TRIP/NON-TRIP, causality)
- Golden vector rows must justify themselves ("This row catches [wrong impl from §5]")
- No `unwrap()` introduced in production paths
- Run tests before and after — no regressions

**Operator steps**:

*Step 0 — Context Build (cold-start, mandatory before any code changes):*
1. Read the story entry in `plans/prd.json` (scope, ATs, enforcement points)
2. Read the R1 evidence ledger: `reviews/reconciliations/${SLICE_ID}/${STORY_ID}_reconciliation.md`
3. Read the gap list: `GAP_LIST.json` + `GAP_LIST.md` — understand each gap's AT, severity, and what's missing
4. Read the premortem: `reviews/premortems/${STORY_ID}_premortem.md` (§4 decisions, §5 wrong-impl, §6 proof plan)
5. Read the actual enforcement code and test files cited in the evidence ledger (verify citations are still accurate)

*Step 1 — Remediation Plan (write before coding):*
1. For each gap in `GAP_LIST.json`, draft: what file(s) to change, what test(s) to add/modify, which premortem §6 proof strategy applies
2. Flag any gap where the fix approach is unclear or the evidence ledger citation is stale
3. Write plan to `R5_REMEDIATION_PLAN.md` — one section per `GAP-*` ID with: gap description, planned change, target file:line, expected test assertion
4. Verify plan scope: every planned change maps to a `GAP-*` ID, no unrelated work

*Step 2 — Implement:*
1. Implement code/test/observability fixes for each gap, following the plan
2. Update evidence ledger rows: GAP → FIXED, add new file:line citations
3. Generate proof graph: `python3 python/proof_graph/scaffold.py ${STORY_ID}`, populate from evidence ledger verdicts/citations, validate with `python3 python/proof_graph/validate.py --strict artifacts/story/${STORY_ID}/proof_graph.json`
4. Run verification commands (at least `verify.sh quick` + targeted tests)

**Output**:
- `R5_REMEDIATION_PLAN.md` (written before coding — one section per gap with planned change, target file:line, expected assertion)
- Code changes + updated evidence ledgers
- `artifacts/story/${STORY_ID}/proof_graph.json` (machine-verifiable proof graph)
- `R5_REMEDIATION_NOTES.md` (narrative: what was fixed, per gap)
- `R5_REMEDIATION_NOTES.json` (sidecar: gap_id mappings, touched files)
**Receipt**: `plans/wf_step.sh ${STORY_ID} implement`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R5_ONLY_GAP_FILES_CHANGED` | Diff scope matches declared remediation (no unrelated changes) |
| `R5_GAP_TRACEABILITY_OK` | Every changed block maps to `GAP-*` in commit message or fix receipt |
| `R5_NO_UNWRAP_IN_PROD` | `rg 'unwrap()'` on touched production files returns 0 new hits |

---

### R5b — Self-Review Gate (Pre-External)

**Mode**: `INTERNAL_AUDIT_GATE`

**Hard rule**: Cycle 2 (R7) cannot start unless `R5B_SELF_REVIEW_PROVEN` passes.

**Agent model** (4 phases, 3 agent roles):

| Phase | Agent(s) | Role | Mode | Output |
|-------|----------|------|------|--------|
| R5b.1 — Skill reviews | Agents 1-6 (parallel) | Reviewer | Read-only | 6 skill receipts |
| R5b.2 — Synthesis + plan | Agent 7 (planner) | Planner | Read-only | `R5B_FIX_PLAN.md` |
| R5b.3 — Fix | Agent 8 (fixer) | Fixer | Read-write | Commits |
| R5b.4 — Re-run | Agents 9+ (parallel) | Reviewer | Read-only | Updated receipts |

**Rationale**: Separating review, planning, and fixing into distinct agents prevents scope creep (planner can't accidentally edit code), keeps the fixer's context small (reads the plan, not 6 full review outputs), and gives re-run agents a clean perspective with no carry-over bias.

#### R5b.1 — Skill Reviews (parallel)

Run 6-skill stack on story-scope code (not just diff). All 6 run in parallel (one agent per skill). Each skill is independent and benefits from a fresh perspective. Parallel execution avoids context bleed between skills.

**Orchestrator prep** (before dispatching agents):
```bash
# Extract story context for prompt enrichment
STORY_ID="${STORY_ID}"
PREMORTEM="reviews/premortems/${STORY_ID}_premortem.md"
SCOPE_TOUCH=$(jq -r '.stories["'${STORY_ID}'"].scope.touch[]' plans/prd.json)
ATS=$(jq -r '.stories["'${STORY_ID}'"].enforcing_contract_ats[]' plans/prd.json)
IMPL_TESTS=$(jq -r '.stories["'${STORY_ID}'"].implementation_tests[]' plans/prd.json)
```

**Per-agent enriched prompts**:

Each agent receives: (a) its skill file from `SKILLS/`, (b) the common context block, (c) its skill-specific enrichment.

##### Common context (all 6 agents)

```
STORY: ${STORY_ID}
SCOPE: story-scope (all files in scope.touch, not just diff)
REVIEW_BASIS: STORY_SCOPE (R5b Self-Review)

Files in scope.touch:
${SCOPE_TOUCH}

Enforcing contract ATs:
${ATS}

Read the skill file first, then apply it to this story's code.
Write findings to: reviews/reconciliations/${SLICE_ID}/receipts/r5b_<skill>.json
```

##### Agent 1: `/pr-review`

```
SKILL: Read SKILLS/pr-review.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §0 (scope) and §8 (conflict scan / hot zones).
- §8 identifies files with overlapping concerns or recent churn.
  Pay extra attention to SOLID violations in those hot zones.
- Read ${PREMORTEM} §3 (failure modes) — any failure mode that
  traces to a code quality issue (missing error handling, tight
  coupling) is a P1 finding, not just style.

FOCUS QUESTIONS:
1. Do the scope.touch files follow the codebase's established patterns?
   (Check crates/soldier_core/ conventions: newtypes, structured logging,
   fail-closed defaults.)
2. Are there any unwrap()/expect() calls in production paths?
3. Is error handling consistent — does every ? chain produce a
   meaningful error type, or are errors erased?
4. Any dead code or unreachable branches introduced by this story?
```

##### Agent 2: `/failure-mode-review`

```
SKILL: Read SKILLS/failure-mode-review.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §3 (top 5 failure modes) — these are the author's
  predicted failure paths. Your job is to verify they were mitigated
  AND to find failure modes the author missed.
- Read ${PREMORTEM} §5 (wrong impls) — each wrong impl implies a
  failure mode. If the wrong impl is "skip the check entirely,"
  the failure mode is "guard is bypassed under condition X."
- Read the R1 evidence ledger if it exists:
  reviews/reconciliations/${SLICE_ID}/${STORY_ID}_reconciliation.md

FOCUS QUESTIONS:
1. For each enforcement point in scope.touch: what happens when
   the input is None, NaN, Inf, negative, stale, or empty?
2. Trace the reject path — does it log (structured, with reason code)?
   Does it increment a metric? Or is it silent?
3. Are there any warn-and-continue paths where the contract requires
   reject-and-halt?
4. What happens on partial state (restart mid-operation, cache stale
   but present, WAL half-written)?
5. For each premortem §3 failure mode: is the mitigation real code
   or just a comment/TODO?
```

##### Agent 3: `/strategic-failure-review`

```
SKILL: Read SKILLS/strategic-failure-review.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §4 (open decisions) — these record explicit design
  choices with rejected alternatives. Check whether the chosen option
  was actually implemented, and whether any rejected option was
  silently adopted (auto-escalation to P1 per policy).
- Read ${PREMORTEM} §7 (economic risk / loss_mode) — understand the
  worst-case economic impact. Strategic risks in high-loss stories
  are P0, not P2.
- Read ${PREMORTEM} §9 (constraints) — known constraints may create
  systemic risks (e.g., "we assumed the cache is always warm").

FOCUS QUESTIONS:
1. What assumptions does this code make about its environment that
   could silently break? (e.g., "upstream always sends field X",
   "config is never stale", "this runs single-threaded")
2. If this story's enforcement fails silently, what is the blast
   radius? Single instrument? All instruments? Full system halt?
3. Are there any hidden coupling points — shared state, global
   config, implicit ordering dependencies?
4. Could an operator misconfigure this in production? What's the
   failure mode of wrong config values?
```

##### Agent 4: `/contract-review`

```
SKILL: Read SKILLS/contract-review.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §1 (clause audit) — the AT-to-contract mapping.
  Verify each mapping is still accurate against specs/CONTRACT.md.
- Read ${PREMORTEM} §6 (proof plan) — the predicted enforcement
  points and proving tests. Compare predictions to reality.
- Read specs/CONTRACT.md for these specific ATs: ${ATS}

FOCUS QUESTIONS:
1. For each AT: does the enforcement point actually enforce what
   the contract clause requires? (Not just "code exists" but
   "code enforces the specific invariant.")
2. Are there any fail-open paths where CONTRACT.md requires
   fail-closed? Check: missing input, stale input, NaN.
3. Does the code's behavior match CONTRACT.md exactly, or does
   it implement a superset/subset of the requirement?
4. Any contract clauses in scope that have NO enforcement point?
5. Is loss_mode consistent with what CONTRACT.md implies about
   the severity of this invariant?
```

##### Agent 5: `/validator-audit`

```
SKILL: Read SKILLS/validator-audit.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §2 (assumptions) — each assumption should have
  become a test. Check which ones did and which are still untested.
- Read ${PREMORTEM} §6 (proof plan) — the predicted test structure.
  Compare: are the tests organized as predicted? Any missing?

Implementation tests for this story:
${IMPL_TESTS}

FOCUS QUESTIONS:
1. For each implementation_test: does it actually exist as a #[test]
   function? (No phantom tests.)
2. Does each test prove causality — asserting reject_reason,
   dispatch_count, latch_reason, or mode_transition — or just
   that "something happened" (is_err, is_some)?
3. For safety-critical ATs: do both TRIP and NON-TRIP tests exist?
4. Are there golden vectors / table-driven tests? How many rows?
   Do they cover boundary, NaN/Inf/missing?
5. For each premortem §2 assumption: is there a corresponding test?
```

##### Agent 6: `/devils-advocate`

```
SKILL: Read SKILLS/devils-advocate.md and follow its checklist.

ENRICHMENT — Premortem context:
- Read ${PREMORTEM} §5 (wrong implementation gate) — this is your
  PRIMARY input. The premortem predicted specific wrong impls that
  are simpler than the correct one and would pass naive tests.
- For each wrong impl in §5: can you write it right now and have
  ALL existing tests pass? If yes, that's a P0 gap.

Implementation tests for this story:
${IMPL_TESTS}

FOCUS QUESTIONS:
1. For each wrong impl in §5: does a tightening test exist that
   would catch it? Name the test. If no test exists, mark
   WRONG_IMPL_UNBLOCKED (P0).
2. Beyond §5: can YOU think of a simpler-than-correct implementation
   that passes all tests? (The Simpler-Than-Correct Gate.)
3. Could you delete an enforcement branch and still pass all tests?
   If yes, the test suite has a mutation gap.
4. Are any tests tautological — they pass regardless of
   implementation because they test the wrong thing?
5. For table-driven tests: are the boundary rows actually at the
   boundary, or off-by-one in the safe direction?
```

**Output**: 6 skill receipt JSONs in `reviews/reconciliations/<slice>/receipts/`:
- `r5b_pr_review.json`
- `r5b_failure_mode_review.json`
- `r5b_strategic_review.json`
- `r5b_contract_review.json`
- `r5b_validator_audit.json`
- `r5b_devils_advocate.json`

#### R5b.2 — Synthesis + Fix Plan (single agent, read-only)

**Inputs**: All 6 skill receipts + premortem for `${STORY_ID}`

**Operator steps**:
1. Read all 6 skill outputs
2. Walk premortem: §2 assumptions → §4 decisions → §5 wrong impls → §6 proof plan → §10 STOPLIGHT
3. Cross-reference skill findings against premortem sections — flag conflicts between skills
4. Classify each finding: P0 (blocking) / P1 (must-fix) / P2 (should-fix) / INFO
5. Write fix plan: for each P0/P1/P2, specify file, function, what to change, and why. Only INFO findings are excluded from the plan.
6. Estimate blast radius (how many files touched, any cross-cutting changes)

**Hard constraint**: This agent has **no edit/write tools** — it produces the plan only.

**Output — two paths**:

**Path A (fixes needed)**: If any P0/P1/P2 findings exist → write `R5B_FIX_PLAN.md` with sections:
- Finding summary (counts by priority)
- Conflict resolution (if skills disagree)
- Ordered fix list (P0 first, then P1, then P2; smallest fix first within each priority)
- Blast radius estimate
- INFO findings (noted, no action required)

Then proceed to R5b.3.

**Path B (no fixes)**: If all findings are INFO → write `R5B_NO_FIXES_NEEDED.md` with:
- Finding summary (`P0: 0, P1: 0, P2: 0`)
- INFO findings list
- Explicit statement: "No code changes required. Skipping R5b.3 and R5b.4."

Then skip R5b.3 and R5b.4, proceed directly to R5b Gate.

#### R5b.3 — Fix (single agent, read-write)

**Skipped if** `R5B_NO_FIXES_NEEDED.md` exists (Path B above).

**Inputs**: `R5B_FIX_PLAN.md` only (does NOT read raw skill outputs)

**Operator steps**:
1. Read the fix plan
2. Execute each fix in plan order (P0 → P1 → P2)
3. For each fix, record what was changed in `R5B_FIX_LOG.md` (file:line, before/after summary)
4. Do NOT fix anything not in the plan — if a new issue is discovered, note it in the fix log for re-planning

**Hard constraint**: Only changes listed in the fix plan are permitted. Unplanned changes require a re-plan cycle (back to R5b.2).

**Output**:
- Commits (one per logical fix or grouped by plan section)
- `R5B_FIX_LOG.md` (what was changed and why, traceable to fix plan items)

#### R5b.4 — Re-run Affected Skills (parallel)

**Skipped if** `R5B_NO_FIXES_NEEDED.md` exists (Path B above).

**Inputs**: `R5B_FIX_LOG.md` (to determine which skills are affected)

Re-run only the skill(s) whose domain was touched by the fixes. Each re-run agent gets a clean context (no carry-over from R5b.1). If re-run finds new P0/P1/P2 findings, cycle back to R5b.2 (re-plan).

**Output**: Updated skill receipts (replace originals in `receipts/`)

#### R5b Gate

**Prerequisite**: R5b runs in the existing recon worktree (`recon/${STORY_ID}` branch). All sub-phases (R5b.1–R5b.4) work in this same worktree — no sub-worktree needed since the recon branch already provides isolation.

After all phases complete (or after R5b.2 Path B skip):
1. Verify clean working tree: `git status --porcelain` must be empty (no uncommitted changes)
2. Emit gate artifact with `head_commit` validation
3. Produce final `SELF_REVIEW_R5b.md` (narrative summary of all phases)
4. Produce `R5B_SELF_REVIEW_GATE.json` (sidecar schema: `specs/schemas/recon/self_review_sidecar.schema.json`)

**Receipt**: `plans/wf_step.sh ${STORY_ID} self_review`

**Gate checks (hard)**:

| Gate ID | Check |
|---------|-------|
| `R5B_CLEAN_TREE` | `git status --porcelain` is empty — all R5b.3 changes must be committed, no stray files |
| `R5B_SELF_REVIEW_PROVEN` | All 6 receipt files exist; `head_commit` in each == current HEAD; `started_at`/`ended_at` timestamps plausible; `exit_status == "completed"` for all; all `artifact_paths[]` exist on disk; either `R5B_FIX_PLAN.md` + `R5B_FIX_LOG.md` exist (Path A) or `R5B_NO_FIXES_NEEDED.md` exists (Path B) |

**On failure**: block with `SELF_REVIEW_UNPROVEN:<reason>` — no Cycle 2 start.

---

### R6 — Verify (Lead Final Verdict Assignment)

**Mode**: `LEAD_VERIFY_AND_VERDICT_ASSIGNMENT`

**Inputs**: Updated evidence ledgers, R5b self-review artifact + receipts, verify outputs, proof graph artifacts

**Operator steps**:
1. Confirm all P0 gaps closed
2. Confirm all P1 gaps closed or explicitly deferred (with debt entries)
3. Escalate WEAK_PROOF on MED/HIGH ATs to CLAIMED_NOT_PROVEN
4. Confirm tests compile and pass (`cargo test` / `verify.sh quick`)
5. Confirm no phantom tests (all `implementation_tests[]` exist as `#[test]` functions)
6. Review diff for regressions
7. Re-check STOPLIGHT after remediation (R6 delta check)
8. Verify R5b receipts (hard gate)
9. Confirm evidence ledgers updated with FIXED citations
10. Assign story verdict: RECONCILED | RECONCILED-WITH-DEBT | RECONCILED_UNIT_ONLY | NOT RECONCILED
11. Write postmortem (conditionally required — see below):
    - **Required when**: STOPLIGHT is YELLOW or RED, OR story touches gates, TradingMode, RiskState, WAL, or replay
    - Use template: `plans/postmortem_template.md`
    - Save to: `artifacts/story/${STORY_ID}/postmortem.md`
    - Fill all 9 sections (§1 constraint in one sentence, §5 wrong impl, §6 rule updates, §8 next-story note, §9 checklist)
    - Validate: `plans/postmortem_gate.sh ${STORY_ID}`
    - If postmortem is not required for this story, record: `POSTMORTEM_EXEMPT: <reason>` in R6 summary

**Output**:
- `R6_VERIFY_SUMMARY.md` (narrative)
- `R6_VERIFY_SUMMARY.json` (schema: `specs/schemas/recon/verify_result.schema.json`) — JSON-primary (gate artifact)
- `artifacts/story/${STORY_ID}/postmortem.md` (when required by step 11)
**Receipt**: `plans/wf_step.sh ${STORY_ID} resolution`

**Gate checks (hard, pass-flip relevant)**:

| Gate ID | Check |
|---------|-------|
| `R6_PROOF_GATE` | Story verdict is RECONCILED or RECONCILED-WITH-DEBT |
| `R6_RUNTIME_ENFORCEMENT_GATE` | Every safety-critical AT is PROVEN-INTEGRATED; PROVEN-UNIT on safety-critical AT blocks pass |
| `R6_MECHANICAL_GATES` | Workflow receipts present; `verify.sh` passed; `R7A_CONTRACT_REVIEW.json` decision == "PASS" (note: `prd_set_pass.sh` reads `contract_review.json` via `CONTRACT_REVIEW_FILE` env var — after producing R7A output, copy to `artifacts/story/<ID>/contract_review.json` or set `CONTRACT_REVIEW_FILE`); `loss_mode` populated; R5b receipts verified |
| `R6_PROOF_GRAPH_GATE` | `proof_graph.json` exists; `validate.py --strict` passes; exemptions only via `proof_graph_exempt.txt` |
| `R6_POSTMORTEM_GATE` | If postmortem required: `postmortem_gate.sh` exits 0. If exempt: `POSTMORTEM_EXEMPT` recorded in R6 summary with reason. |

---

### R7 — Post-Reconciliation Validation (Cycle 2: FIX_DIFF + AT_REGRESSION)

**Mode**: `CYCLE2_POST_REMEDIATION_AUDIT`
**Cycle scope (hard)**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`

**Hard rule**: Cycle 2 cannot start unless `R5B_SELF_REVIEW_PROVEN` passed.

**Execution order**: R7a, risk-gate R7b (conditional), R7c may run in parallel → R7c-fix (apply findings) → R7d.1 + R7d.2 + R7e → R7f runs last.

#### R7a — Contract Review (R5/R7 diff)

**Command**: `/contract-review` scoped to R5 diff
**Focus**: Contract-vs-code alignment on remediation changes; fail-open hazards introduced by fixes
**Required contents**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`
**Output**: `R7A_CONTRACT_REVIEW.md` + `R7A_CONTRACT_REVIEW.json` (decision + findings)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7A_CONTRACT_REVIEW_COMPLETE` | Artifact exists; review basis line present |
| `R7A_DECISION_PASS_REQUIRED` | JSON `decision == "PASS"` before phase close |

#### risk-gate R7b — Strategic Failure Review (cross-story/systemic)

**Command**: `/strategic-failure-review` on full reconciliation output
**Focus**: Hidden systemic risk, shared primitive blast radius, capital-risk path regressions
**Escalation**: If HIGH loss_mode guard is NOT-WIRED on live system → `OPERATIONAL_ESCALATION_REQUIRED`
**Output**: `R7B_STRATEGIC_REVIEW.md` + `R7B_STRATEGIC_REVIEW.json` (sidecar)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7B_STRATEGIC_REVIEW_COMPLETE` | For HIGH/shared-primitive stories only: artifact exists; review basis line present; findings disposition recorded (FIXED / STRUCTURAL / DEFERRED) |

#### R7c — Production Wiring Audit (PROVEN-INTEGRATED vs PROVEN-UNIT)

**Command**: Trace call chain from each enforcement function to entry points in `specs/ENTRY_POINTS.md`
**Focus**: Call-graph reachability from production paths; "paper enforcement" detection (tested but not called)

**Per safety-critical AT, classify**:
- **PROVEN-INTEGRATED** — reachable from production entry point
- **PROVEN-UNIT** — zero production callers (island guard)

**Output**: `R7C_WIRING_AUDIT.md` + `R7C_WIRING_AUDIT.json` (per-AT wiring_status + caller evidence)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7C_WIRING_CLASSIFICATION_COMPLETE` | Every safety-critical AT classified |
| `R7C_NO_UNCLASSIFIED_SAFETY_AT` | Missing classification blocks phase close |

#### R7c-fix — Apply R7a-R7c Findings (Code Changes)

**Mode**: `WRITE_ALLOWED_REVIEW_FIX_ONLY`

**Agent**: Any available agent (need not be the R7a-c reviewer). The R7c-fix agent is assumed to be a cold-start session with no prior context.

**Inputs**: R7A/R7B/R7C findings, R5 remediation notes, gap list, evidence ledgers, premortem

**Hard rules**:
- Fix only findings from R7a, risk-gate R7b, R7c — no unrelated refactors
- Every change must trace to a specific R7a/risk-gate R7b/R7c finding
- Run tests before and after — no regressions
- No `unwrap()` introduced in production paths

**Operator steps**:

*Step 0 — Context Build (cold-start, mandatory before any code changes):*
1. Read the story entry in `plans/prd.json` (scope, ATs, enforcement points)
2. Read R7A, R7B, R7C artifacts — understand each finding's severity, AT, and what needs fixing
3. Read the R5 remediation notes — understand what was already fixed
4. Read the premortem: `reviews/premortems/${STORY_ID}_premortem.md` (§4 decisions, §5 wrong-impl)
5. Read the actual enforcement code and test files cited in findings (verify citations are still accurate)

*Step 1 — Fix Plan (write before coding):*
1. For each R7a/risk-gate R7b/R7c finding that requires a code change, draft: what file(s) to change, what test(s) to add/modify
2. Flag any finding where the fix approach is unclear or the citation is stale
3. Write plan to `R7C_FIX_PLAN.md` — one section per finding with: finding ID, planned change, target file:line, expected test assertion
4. Verify plan scope: every planned change maps to an R7a/risk-gate R7b/R7c finding, no unrelated work

*Step 2 — Implement:*
1. Implement code/test fixes for each finding, following the plan
2. Run verification commands (at least `verify.sh quick` + targeted tests)

**Output**:
- `R7C_FIX_PLAN.md` (written before coding)
- Code changes
- `R7C_FIX_NOTES.md` (narrative: what was fixed, per finding)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7C_FIX_ONLY_FINDING_FILES_CHANGED` | Diff scope matches declared fixes (no unrelated changes) |
| `R7C_FIX_NO_UNWRAP_IN_PROD` | `rg 'unwrap()'` on touched production files returns 0 new hits |

---

#### R7d — External Review Cycle 2 + Code Review Expert

##### R7d.1 — External Review Cycle 2 (manifest-driven dual-path)

Cycle 2 review combinations are determined by `R7_EXTERNAL_MANIFEST.json`:

- `cycle2_path.mode == "dual_combo"`: dual-combo path (dual prompt styles), default.
- `cycle2_path.mode == "recon_clean_single"`: one explicit `tool` + `prompt_style` combo.
- In all cases, run at least the combinations in `cycle2_path.required_combinations`.

**Commands (per required combo)**:
```bash
plans/review_logged.sh <STORY_ID> --tool <tool> --prompt <style> --base <BASE_BRANCH>
```
Repeat with additional tools as needed. Minimum 1 combo; dual-combo requires both styles.

**Tool coverage policy (Cycle 2)**:
- Honor `cycle2_path.required_combinations` in the manifest.
- If `opus` is not in required combinations, omission is allowed but must be documented in handoff notes.
- If `opus` is required and unavailable, block with explicit reason; do not silently downgrade combinations.

**Required scope**: FIX_DIFF + AT_REGRESSION (not story-scope)
**Required basis line**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`
**Must verify**: gaps actually closed, no regressions, tests real/compiling/non-phantom

**Artifact requirements**:
- Normalized filenames: `<tool>.enriched.md`, `<tool>.generic.md` per tool
- Per-story manifest: `R7_EXTERNAL_MANIFEST.json` (source of truth, gate artifact)
- Per-story rendered summary: `R7_EXTERNAL_MANIFEST.md` (human-readable companion)
- Render companions from `plans/render_external_manifest.py`; do not hand-edit.

**`R7_EXTERNAL_MANIFEST.json` schema (required fields)**:
```json
{
  "schema_version": "r7_external_manifest.v2",
  "head_commit": "<sha>",
  "created_at": "<ISO 8601>",
  "story_id": "<STORY_ID>",
  "slice_id": "<slice-id>",
  "phase": "R7d",
  "cycle": "C2",
  "review_basis": "FIX_DIFF + AT_REGRESSION (Cycle 2)",
  "required_combinations": [
    { "tool": "codex", "prompt_style": "enriched" },
    { "tool": "codex", "prompt_style": "generic" },
    { "tool": "kimi", "prompt_style": "enriched" },
    { "tool": "kimi", "prompt_style": "generic" }
  ],
  "tools": [
    {
      "tool": "codex",
      "model": "gpt-5.3",
      "artifacts": {
        "enriched": { "path": "codex.enriched.md", "exists": true },
        "generic":  { "path": "codex.generic.md",  "exists": true }
      }
    }
  ],
  "cycle2_path": {
    "mode": "dual_combo",
    "required_combinations": [
      { "tool": "codex", "prompt_style": "enriched" },
      { "tool": "codex", "prompt_style": "generic" },
      { "tool": "kimi", "prompt_style": "enriched" },
      { "tool": "kimi", "prompt_style": "generic" }
    ]
  },
  "regression_scope": {
    "base_commit": "<sha>",
    "head_commit": "<sha>",
    "affected_ats": ["AT-1", "AT-2"],
    "changed_files": ["src/foo.rs"]
  },
  "validation": {
    "status": "PASS",
    "review_basis_check": "PASS",
    "required_combinations_check": "PASS",
    "head_commit_alignment_check": "PASS",
    "base_commit_alignment_check": "PASS"
  }
}
```

**Single-combo RECON-CLEAN flow (structured, machine-verifiable)**:
If Cycle 1 + self-review reported no blocking work and no code changes are required:
1. Lead authorizes RECON-CLEAN by setting:
   - `cycle2_path.mode = "recon_clean_single"`
   - `cycle2_path.single_combo_choice = { "tool": "<tool>", "prompt_style": "<generic|enriched>" }`
   - `cycle2_path.required_combinations = [ single_combo_choice ]`
   - `cycle2_path.single_combo_justification` is non-empty
2. Confirms R5b no-fix path (`R5B_NO_FIXES_NEEDED.md`) and R5b self-review JSON has `finding_counts: { "P0": 0, "P1": 0, "P2": 0 }`
3. Record:
   - `RECON-CLEAN approved by: <lead>`
   - `RECON-CLEAN verified: reviewed <artifact>`
4. Run only the approved single combo and cite findings in `R7_EXTERNAL_MANIFEST.md`.

##### R7d.2 — Code Review Expert

**Command**: `code-review-expert` skill on full diff (R5 + R7a-R7c changes)
**Focus**: SOLID violations, security risks, boundary bugs, code quality
**Output**: `R7D_CODE_REVIEW_EXPERT.md` + `R7D_CODE_REVIEW_EXPERT.json` (sidecar)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO` or `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE` | One C2 manifest per story; required combos present for `cycle2_path.mode` (`dual_combo` requires dual-combo requirements; `recon_clean_single` requires one combo and `single_combo_justification`) |
| `R7D_CODE_REVIEW_EXPERT_COMPLETE` | Artifact exists; findings disposition recorded |
| `R7D_BLOCKERS_RESOLVED` | No unresolved P0/P1 findings before advancing to R7e |

#### R7e — Devils Advocate (Mutation / Test-the-Tests)

**Command**: `/devils-advocate` on full proving suite for gapped ATs
**Focus**: Simpler-Than-Correct gate (independent), mutation resistance of proving tests
**Scope**: ALL proving tests for flagged ATs (not just new tests)
**Machine verification**: `cargo mutants --file <enforcement>.rs -- --test <proving_targets>`

**Operator steps**:
1. Run mutation analysis on impacted proving tests
2. Review survivors
3. For each survivor: fix tests OR record justified structural limitation
4. Re-run until no unacceptable survivors remain

**Output**:
- `R7E_DEVILS_ADVOCATE.md` + `R7E_DEVILS_ADVOCATE_RECHECK.md`
- `R7E_MUTATION_RESULTS.json`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7E_MUTATION_ANALYSIS_COMPLETE` | Mutation artifact exists; scope covers all impacted proving tests |
| `R7E_SIMPLER_THAN_CORRECT_GATE` | No unresolved mutation survivor that permits wrong impl; structural exceptions documented with owner/target |

#### R7f — Debt Register Validation (final)

**Inputs**: `GAP_LIST.json`, `DEBT_REGISTER.json`, evidence ledgers

**Operator steps**:
1. Validate `DEBT_REGISTER.json` schema
2. Cross-check all DEFERRED gaps → debt entries
3. Reject empty `owner` or `target_slice == "TBD"`
4. Detect overdue debt (OVERDUE_DEBT)
5. Produce final debt validation report

**Output**: `R7F_DEBT_REGISTER_VALIDATION.md` + `R7F_DEBT_REGISTER_VALIDATION.json`

**Gate checks (hard)**:

| Gate ID | Check |
|---------|-------|
| `R7F_DEBT_SCHEMA_VALID` | JSON schema passes |
| `R7F_ALL_DEFERRED_MAPPED` | Every DEFERRED gap has matching `gap_id` |
| `R7F_NO_INVALID_DEBT_FIELDS` | No empty `owner`; no `target_slice: "TBD"` |
| `R7F_NO_OVERDUE_DEBT` | No overdue unresolved debt |

**Any failure blocks `prd_set_pass.sh` path for current slice.**

**Receipt**: `plans/wf_step.sh ${STORY_ID} cycle2`

---

### R7 Exit Conditions (ALL must be true)

| Gate ID | Phase |
|---------|-------|
| `R7A_CONTRACT_REVIEW_COMPLETE` | R7a |
| `R7A_DECISION_PASS_REQUIRED` | R7a |
| `R7B_STRATEGIC_REVIEW_COMPLETE` | risk-gate R7b |
| `R7C_WIRING_CLASSIFICATION_COMPLETE` | R7c |
| `R7C_NO_UNCLASSIFIED_SAFETY_AT` | R7c |
| `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO` / `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE` | R7d.1 |
| `R7D_CODE_REVIEW_EXPERT_COMPLETE` | R7d.2 |
| `R7C_FIX_ONLY_FINDING_FILES_CHANGED` | R7c-fix |
| `R7C_FIX_NO_UNWRAP_IN_PROD` | R7c-fix |
| `R7D_BLOCKERS_RESOLVED` | R7d |
| `R7E_MUTATION_ANALYSIS_COMPLETE` | R7e |
| `R7E_SIMPLER_THAN_CORRECT_GATE` | R7e |
| `R7F_DEBT_SCHEMA_VALID` | R7f |
| `R7F_ALL_DEFERRED_MAPPED` | R7f |
| `R7F_NO_INVALID_DEBT_FIELDS` | R7f |
| `R7F_NO_OVERDUE_DEBT` | R7f |
| No unresolved P0/P1 findings remain | All |

**Final summary artifact**: `SUMMARY.md` + `SUMMARY.json` (optional sidecar for dashboards) — story verdicts, wiring qualifiers, debt summary, phase artifact index.

---

## 4) Pass-Flip Gate

**Command**: `plans/prd_set_pass.sh ${STORY_ID} true`

A story is pass-eligible only if ALL conditions are met:

| Gate | Check |
|------|-------|
| Proof | Story verdict is RECONCILED or RECONCILED-WITH-DEBT (RECONCILED_UNIT_ONLY passes this check but is blocked by Wiring) |
| Wiring | Every safety-critical AT is PROVEN-INTEGRATED |
| Gaps | No unresolved P0/P1 |
| Debt | DEBT_REGISTER.json valid for all deferred items |
| External C1 | `R3_EXTERNAL_C1_COMPLETE` passed; all findings mapped (R4b) |
| External C2 | `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO` or `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE` passed |
| Receipts | All 8 workflow receipts present (wf_step.sh chain) |
| Verify | `verify.sh full` passed with matching HEAD and no `FAILED_GATE` marker in latest verify artifact |
| Contract | `R7A_CONTRACT_REVIEW.json` has `decision: "PASS"` (copy to `artifacts/story/<ID>/contract_review.json` for `prd_set_pass.sh` compatibility, or set `CONTRACT_REVIEW_FILE` env var) |
| Loss mode | `worst_case`, `fail_closed_cap`, `drift_metric` all populated |
| Proof graph | `proof_graph.json` validates with `validate.py --strict` (or story in exempt list) |
| Fail-closed | `fail_closed_coverage.sh` passes (test counts + patterns) |
| Postmortem | If required: `postmortem_gate.sh` passes. If exempt: `POSTMORTEM_EXEMPT` in R6 summary. |
| R7 exit | All R7 exit conditions met |
> **Tip (verify_full timeout)**: If `verify.sh full` times out during preflight, set `PREFLIGHT_TIMEOUT=1200 ./plans/verify.sh full`. Default full-mode timeout is 1800s; override for slower machines or large workspaces.
>
> **Tip (verify_full triage)**: If Step 8 still fails after a full run, inspect latest verify artifact (`artifacts/verify/<run_id>/`). If `FAILED_GATE` exists, resolve that gate first; do not continue to pass-flip.


If any condition fails: **`prd_set_pass.sh` is blocked.**

---

## 5) Non-Negotiable Anti-Gaming Rules

1. **No diff-only review in Cycle 1** — Story-scope or rejected (`DIFF_ONLY_REVIEW_REJECTED`)
2. **No self-review of own batch** in cross-review phases
3. **No DEFERRED without debt entry** — schema-validated, not prose
4. **No "code is better" divergence** without evidence + lead approval
5. **No blanket `--theirs`** on tooling/prompt files without merge-base diff inspection
6. **No single-prompt reviews in Cycle 1** — always both generic + enriched per tool; Cycle 2 follows manifest mode (`dual_combo` or `recon_clean_single`); if a configured tool is intentionally omitted (for example, `opus` unavailable), record reason in handoff
7. **No RECON-CLEAN without lead sign-off** on blocking-finding claim
8. **No fake citations** — file:line must contain enforcement/test, not whitespace
9. **No Cycle 2 without R5b gate** — `R5B_SELF_REVIEW_PROVEN` must pass first
10. **No gap-list-complete without coverage proof** — "no gaps" requires structured justification

See [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md) for the full catalog with root causes and fixes.

---

## 6) Artifact Layout + Provenance

### 6.1 Canonical Directory Layout

All paths are relative to the repository root. Artifacts within `reviews/reconciliations/<SLICE_ID>/` use **deterministic, phase-prefixed names** — no timestamps, no random suffixes. A validator can check file existence without globbing.

```
reviews/premortems/
  STORY_PREMORTEM_TEMPLATE.md
  PREMORTEM_RECONCILIATION_PROCESS.md         # Index + Appendix A
  <STORY_ID>_premortem.md
  CROSS_REVIEW_by_<REVIEWER>.md               # Mode A Phase 4

reviews/reconciliations/<SLICE_ID>/
  # ── R1: Evidence Ledgers ──
  <STORY_ID>_reconciliation.md
  <STORY_ID>_reconciliation.json              # sidecar (gate fields only)

  # ── R2: Lead Evaluation ──
  R2_LEAD_EVAL.md
  R2_LEAD_EVAL.json                           # sidecar

  # ── R3A: Internal Cross-Review ──
  R3_RECONCILE_REVIEW_by_<REVIEWER>.md
  R3_RECONCILE_REVIEW_by_<REVIEWER>.json      # sidecar

  # ── R3B: External Reviews (Cycle 1) ──
  external/
    cycle1/
      <STORY_ID>/
        codex.enriched.md                     # normalized from review_logged.sh output
        codex.generic.md
        opus.enriched.md                      # if run
        opus.generic.md                       # if run
        kimi.enriched.md                      # if run
        kimi.generic.md                       # if run
        R3_EXTERNAL_MANIFEST.json             # source of truth (gate artifact)
        R3_EXTERNAL_MANIFEST.md               # rendered summary (human-readable, generated from JSON)

  # ── R4 / R4b: Gap List + Finding Mapping ──
  GAP_LIST.md
  GAP_LIST.json                               # JSON-primary
  R4B_EXTERNAL_MAPPING.json                   # JSON-primary
  R4B_EXTERNAL_MAPPING.md                     # rendered summary
  DEBT_REGISTER.json

  # ── R5: Remediation ──
  R5_REMEDIATION_PLAN.md                      # written before coding (one section per gap)
  R5_REMEDIATION_NOTES.md
  R5_REMEDIATION_NOTES.json                   # sidecar (gap_id mappings, touched files)

  # ── R5b: Self-Review ──
  R5B_FIX_PLAN.md                             # R5b.2 planner output (read-only synthesis)
  R5B_FIX_LOG.md                              # R5b.3 fixer output (what was changed)
  SELF_REVIEW_R5b.md                          # final narrative summary
  R5B_SELF_REVIEW_GATE.json                   # sidecar (gate summary)
  receipts/
    r5b_pr_review.json
    r5b_failure_mode_review.json
    r5b_strategic_review.json
    r5b_contract_review.json
    r5b_validator_audit.json
    r5b_devils_advocate.json

  # ── R6: Verify ──
  R6_VERIFY_SUMMARY.md
  R6_VERIFY_SUMMARY.json                      # JSON-primary (gate artifact)

  # ── R7: Post-Reconciliation ──
  R7A_CONTRACT_REVIEW.md
  R7A_CONTRACT_REVIEW.json
  R7B_STRATEGIC_REVIEW.md
  R7B_STRATEGIC_REVIEW.json                   # sidecar
  R7C_WIRING_AUDIT.md
  R7C_WIRING_AUDIT.json
  R7C_FIX_PLAN.md                            # written before coding (one section per finding)
  R7C_FIX_NOTES.md                           # narrative: what was fixed, per finding
  R7D_CODE_REVIEW_EXPERT.md
  R7D_CODE_REVIEW_EXPERT.json                 # sidecar
  R7E_DEVILS_ADVOCATE.md
  R7E_DEVILS_ADVOCATE_RECHECK.md
  R7E_MUTATION_RESULTS.json
  R7F_DEBT_REGISTER_VALIDATION.md
  R7F_DEBT_REGISTER_VALIDATION.json

  # ── R7d.1: External Reviews (Cycle 2) ──
  external/
    cycle2/
      <STORY_ID>/
        codex.enriched.md
        codex.generic.md
        opus.enriched.md                      # if run
        opus.generic.md                       # if run
        kimi.enriched.md                      # if run
        kimi.generic.md                       # if run
        R7_EXTERNAL_MANIFEST.json             # source of truth (gate artifact)
        R7_EXTERNAL_MANIFEST.md               # rendered summary (human-readable, generated from JSON)

  # ── Final Roll-Up ──
  SUMMARY.md
  SUMMARY.json                                # optional sidecar for dashboards

artifacts/story/<STORY_ID>/
  proof_graph.json
  postmortem.md                              # conditionally required (R6 step 11)

plans/prompts/
  slice_reconcile_r1_audit.md                 # derived copy of Appendix A (renamed from slice_reconcile_implement.md)

plans/step_prompts/recon/
  r1_audit.md                                 # R1 read-only audit prompt (renamed from implement.md)
  implement.md                                # R5 remediation prompt
  self_review.md
  cycle1.md
  cycle2.md
```

### 6.1.1 Recon Bundle Portability (Deterministic Export/Import)

Use `plans/recon_bundle.sh` to move slice-core reconciliation evidence between worktrees without manual copy drift.

Canonical export command:
```bash
./plans/recon_bundle.sh export \
  --slice S14 \
  --verify-run 20260226_120000 \
  --bundle-id S14_recon_20260226 \
  --out-root artifacts/recon_bundles
```

Canonical import command (strict by default):
```bash
./plans/recon_bundle.sh import \
  --bundle artifacts/recon_bundles/S14_recon_20260226
```

Dry-run validation before write:
```bash
./plans/recon_bundle.sh import \
  --bundle artifacts/recon_bundles/S14_recon_20260226 \
  --dry-run
```

Head mismatch policy:
- Import blocks when `source_head_sha` differs from current `HEAD`.
- Override only when intentionally importing across different heads:
  `./plans/recon_bundle.sh import --bundle <dir> --allow-head-mismatch --dry-run`

Bundle payload scope (fail-closed):
- `reviews/reconciliations/<slice>/**`
- `.wf/receipts/<slice>-*/**`
- `.wf/recon_scope_lock/<slice>-*.scope_lock.json`
- `artifacts/story/<slice>-*/**`
- Optional `artifacts/verify/<run_id>/**` when `--verify-run` is supplied.

### 6.2 Provenance Header (Required on All Review Artifacts)

Every review artifact (`.md` and `.json`) produced in R1–R7 must include a standard provenance header. This applies to internal reviews, external tool reviews, and manifests.

#### 6.2.1 Required Fields (5 mandatory)

| Field | Values |
|-------|--------|
| `tool` | `codex` \| `opus` \| `kimi` \| `internal` \| `script` |
| `model` | String (e.g., `gpt-5.3`, `claude-opus-4-6`, `kimi-k2.5`, `n/a`) |
| `prompt_style` | `generic` \| `enriched` \| `none` |
| `cycle` | `C1` \| `C2` \| `SELF` \| `NONE` |
| `phase_equivalent` | `R1` \| `R2` \| `R3` \| `R4` \| `R4b` \| `R5` \| `R5b` \| `R5b.1` \| `R5b.2` \| `R5b.3` \| `R5b.4` \| `R6` \| `R7a` \| `R7b` \| `R7c` \| `R7d` \| `R7e` \| `R7f` |

#### 6.2.2 Full Provenance Set (recommended for all artifacts)

| Field | Required? | Notes |
|-------|-----------|-------|
| `tool` | Yes | |
| `model` | Yes | `n/a` for internal/script |
| `prompt_style` | Yes | `none` for internal/script |
| `cycle` | Yes | |
| `phase_equivalent` | Yes | |
| `review_basis` | Yes (review phases) | Exact string, e.g. `STORY_SCOPE (Cycle 1)`. JSON enum equivalent: `FIX_DIFF_AT_REGRESSION` (no spaces). Validators match on `FIX_DIFF` prefix. |
| `story_id` | Yes | Or `BATCH-<ID>` for batch artifacts |
| `slice_id` | Yes | |
| `head_commit` | Yes | |
| `base_commit` | C2 required | Required for FIX_DIFF reviews |
| `generated_at` | Yes | ISO 8601 UTC |
| `artifact_provenance` | Yes | `logger-v2`, `manual`, `renderer-v1` |
| `schema_version` | Yes (JSON) | |

#### 6.2.3 Markdown Provenance Format (YAML front matter)

Every `*.md` review artifact must begin with YAML front matter:

```yaml
---
provenance:
  tool: codex
  model: gpt-5.3
  prompt_style: enriched
  cycle: C1
  phase_equivalent: R3
  review_basis: "STORY_SCOPE (Cycle 1)"
  story_id: S1-004
  slice_id: S1
  head_commit: "abc1234def5678"
  base_commit: "main@{2026-02-22}"   # optional for C1; required for C2
  generated_at: "2026-02-23T18:42:11Z"
  artifact_provenance: "logger-v2"
  schema_version: "review_markdown_header.v1"
---
```

**Internal/manual review**: `tool: internal`, `model: n/a`, `prompt_style: none`, `artifact_provenance: manual`
**Script-generated render**: `tool: script`, `model: n/a`, `prompt_style: none`, `artifact_provenance: renderer-v1`

#### 6.2.4 JSON Provenance Format

JSON artifacts include the same fields at the top level (flat, not nested under `provenance`). JSON artifacts additionally include the guardrail fields:

```json
{
  "schema_version": "<schema_name>.v1",
  "head_commit": "<sha>",
  "created_at": "<ISO 8601>",
  "tool": "codex",
  "model": "gpt-5.3",
  "prompt_style": "enriched",
  "cycle": "C1",
  "phase_equivalent": "R3",
  "review_basis": "STORY_SCOPE (Cycle 1)",
  "story_id": "S1-004",
  "slice_id": "S1"
}
```

Sidecar JSON additionally includes:
```json
{
  "markdown_sha256": "<sha256 of companion .md file>",
  "markdown_path": "<relative path to .md file>"
}
```

Validators reject if: `head_commit` mismatch, `markdown_sha256` drift, unsupported `schema_version`, missing mandatory provenance field.

### 6.3 Artifact Format Summary

| Phase | Artifact | Format | Schema |
|-------|----------|--------|--------|
| R1 | `<STORY_ID>_reconciliation` | Markdown + sidecar [Wave 2: JSON-primary] | `evidence_ledger.schema.json` |
| R2 | `R2_LEAD_EVAL` | Markdown + sidecar | `lead_eval_sidecar.schema.json` |
| R3A | `R3_RECONCILE_REVIEW_by_<REVIEWER>` | Markdown + sidecar | `cross_review.schema.json` |
| R3B | `R3_EXTERNAL_MANIFEST` | JSON-primary + rendered .md | `r3_external_manifest.schema.json` |
| R3B | `<tool>.<style>.md` | Markdown (external review) | `review_receipt.schema.json` |
| R4 | `GAP_LIST` | JSON-primary + .md companion | `gap_list.schema.json` |
| R4b | `R4B_EXTERNAL_MAPPING` | JSON-primary + rendered .md | `phase_mapping.schema.json` |
| R5 | `R5_REMEDIATION_PLAN` | Markdown | — |
| R5 | `R5_REMEDIATION_NOTES` | Markdown + sidecar | — |
| R5b.2 | `R5B_FIX_PLAN` | Markdown | — |
| R5b.3 | `R5B_FIX_LOG` | Markdown | — |
| R5b | `SELF_REVIEW_R5b` / `R5B_SELF_REVIEW_GATE` | Markdown + sidecar | `self_review_sidecar.schema.json` |
| R6 | `R6_VERIFY_SUMMARY` | JSON-primary + .md companion | `verify_result.schema.json` |
| R7a | `R7A_CONTRACT_REVIEW` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| risk-gate R7b | `R7B_STRATEGIC_REVIEW` | Markdown + sidecar | `review_artifact_sidecar.schema.json` |
| R7c | `R7C_WIRING_AUDIT` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| R7c-fix | `R7C_FIX_PLAN` / `R7C_FIX_NOTES` | Markdown | — |
| R7d.1 | `R7_EXTERNAL_MANIFEST` | JSON-primary + rendered .md | `r7_external_manifest.schema.json` |
| R7d.2 | `R7D_CODE_REVIEW_EXPERT` | Markdown + sidecar | `review_artifact_sidecar.schema.json` |
| R7e | `R7E_DEVILS_ADVOCATE` / `R7E_MUTATION_RESULTS` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| R7f | `R7F_DEBT_REGISTER_VALIDATION` | Markdown + JSON | — |
| R6 | `postmortem.md` (in `artifacts/story/`) | Markdown | validated by `postmortem_gate.sh` |
| Gate | premortem ready | JSON-primary | `premortem_ready.schema.json` |

**Rule**: If the artifact directly controls a gate or pass-flip → JSON-primary. If it primarily supports human reasoning → markdown + JSON sidecar. Every phase produces both `.md` and `.json`.

### 6.4 Validators

| Script | Purpose |
|--------|---------|
| `plans/validate_recon_artifact.sh` | jq-based schema validation for all artifact types |
| `plans/validate_review_header.py` | Provenance header validation (5 mandatory fields + format) |
| `plans/validate_external_manifest.py` | External manifest completeness (tools, artifacts, citations) |
| `plans/render_external_manifest.py` | Generate `.md` companion from manifest JSON |

---

## 7) Quick Verdict Reference

| Verdict | Scope | Meaning |
|---------|-------|---------|
| PROVEN | Per-AT | Enforcement exists, test proves causality, fail-closed confirmed |
| WEAK_PROOF | Per-AT | Test exists but only checks "something happened," not which guard |
| CLAIMED_NOT_PROVEN | Per-AT | No enforcement or no causal test |
| UNTESTED_ENFORCEMENT | Per-AT | Enforcement and test both exist but are disconnected |
| WRONG_IMPL_UNBLOCKED | Per-AT | §5 wrong impl has no tightening test |
| DEFERRED | Per-AT | AT not yet implemented; tracked in debt register |
| PARTIAL | Intermediate | At least one AT has gaps; replaced by final verdict in R6 |
| RECONCILED | Story | All P0/P1 closed, unit correctness proven |
| RECONCILED-WITH-DEBT | Story | P2 items deferred, debt register populated |
| RECONCILED_UNIT_ONLY | Story | Unit correctness proven but safety-critical AT is PROVEN-UNIT (not wired) |
| NOT RECONCILED | Story | P0 gaps remain open |
| PROVEN-INTEGRATED | Wiring | Guard reachable from production entry point |
| PROVEN-UNIT | Wiring | Guard has zero production callers |

Full definitions and escalation rules in [POLICY](PREMORTEM_RECON_POLICY.md).

---

## 8) Gate ID Reference (All Phases)

| Gate ID | Phase | Blocking? |
|---------|-------|-----------|
| `R1_READ_ONLY_INTEGRITY_OK` | R1 | Yes |
| `R1_EVIDENCE_LEDGER_COMPLETE` | R1 | Yes |
| `R2_LEAD_EVAL_COMPLETE` | R2 | Yes |
| `R2_NO_UNREVIEWED_STORIES` | R2 | Yes |
| `R3_INTERNAL_CROSS_REVIEW_COMPLETE` | R3A | Yes |
| `R3_EXTERNAL_C1_COMPLETE` | R3B | Yes |
| `R3_DIFF_ONLY_REVIEW_BLOCK` | R3 | Yes |
| `R4_GAP_LIST_COMPLETE` | R4 | Yes |
| `R4_NO_UNCHECKED_CLEAN_REVIEW` | R4 | Yes |
| `R4_DEBT_DRAFT_COMPLETE` | R4 | Yes |
| `R4B_ALL_FINDINGS_MAPPED` | R4b | Yes |
| `R4B_NO_UNMAPPED_P0_P1` | R4b | Yes |
| `R5_ONLY_GAP_FILES_CHANGED` | R5 | Yes |
| `R5_GAP_TRACEABILITY_OK` | R5 | Yes |
| `R5_NO_UNWRAP_IN_PROD` | R5 | Yes |
| `R5B_CLEAN_TREE` | R5b | Yes (blocks Cycle 2) |
| `R5B_SELF_REVIEW_PROVEN` | R5b | Yes (blocks Cycle 2) |
| `R6_PROOF_GATE` | R6 | Yes |
| `R6_RUNTIME_ENFORCEMENT_GATE` | R6 | Yes |
| `R6_MECHANICAL_GATES` | R6 | Yes |
| `R6_PROOF_GRAPH_GATE` | R6 | Yes |
| `R6_POSTMORTEM_GATE` | R6 | Yes (conditional) |
| `R7A_CONTRACT_REVIEW_COMPLETE` | R7a | Yes |
| `R7A_DECISION_PASS_REQUIRED` | R7a | Yes |
| `R7B_STRATEGIC_REVIEW_COMPLETE` | risk-gate R7b (high/shared-primitive only) | Yes |
| `R7C_WIRING_CLASSIFICATION_COMPLETE` | R7c | Yes |
| `R7C_NO_UNCLASSIFIED_SAFETY_AT` | R7c | Yes |
| `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO` / `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE` | R7d.1 | Yes |
| `R7D_CODE_REVIEW_EXPERT_COMPLETE` | R7d.2 | Yes |
| `R7C_FIX_ONLY_FINDING_FILES_CHANGED` | R7c-fix | Yes |
| `R7C_FIX_NO_UNWRAP_IN_PROD` | R7c-fix | Yes |
| `R7D_BLOCKERS_RESOLVED` | R7d | Yes |
| `R7E_MUTATION_ANALYSIS_COMPLETE` | R7e | Yes |
| `R7E_SIMPLER_THAN_CORRECT_GATE` | R7e | Yes |
| `R7F_DEBT_SCHEMA_VALID` | R7f | Yes |
| `R7F_ALL_DEFERRED_MAPPED` | R7f | Yes |
| `R7F_NO_INVALID_DEBT_FIELDS` | R7f | Yes |
| `R7F_NO_OVERDUE_DEBT` | R7f | Yes |
