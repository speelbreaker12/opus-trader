# Premortem + Reconciliation Runbook

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

Checks:
1. Premortem file exists
2. STOPLIGHT != RED
3. No AT ownership conflicts (no AT claimed as primary by 2+ stories)
4. All sections §0-§10 present (delegates to `premortem_gate.sh`)

**Exit 0** = proceed. **Exit 1** = blocked (fix premortem first).

### 1.3 STOPLIGHT Gate (Mode B)

| STOPLIGHT | Action |
|-----------|--------|
| RED | **STOP** — fix premortem first |
| YELLOW | Continue; carry all deferred items into gap list |
| GREEN | Continue |

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

### Step Supervisor Phase Mapping

| `wf_step.sh` step | Part B phase(s) | Pod |
|--------------------|----------------|-----|
| `preflight` | R1 | A |
| `implement` | R5 | A |
| `self_review` | R5b | B |
| `cycle1` | R2 + R3 (R3A + R3B) + R4 + R4b | B |
| `fix` | R7a-R7c fixes | C |
| `cycle2` | R7d (R7d.1 + R7d.2) + R7e + R7f | C |
| `resolution` | R6 | D |
| `verify_full` | `verify.sh full` | D |
| `pass` | `prd_set_pass.sh` | supervisor |

Receipt systems: `wf_step.sh` receipts (`.wf/receipts/<ID>/`) track step completion. R5b skill receipts (`reviews/reconciliations/<slice>/receipts/`) track individual skill execution.

---

### R1 — Parallel Reconcile (Read-Only)

**Mode**: `READ_ONLY` (no file modifications)

**Inputs (required per story)**:
- `plans/prd.json` (story entry)
- `specs/CONTRACT.md` (relevant AT clauses)
- `reviews/premortems/<STORY_ID>_premortem.md` (or approved fallback preflight artifact)
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
- Validate: `plans/validate_recon_artifact.sh evidence_ledger <path>` [Wave 2]
**Receipt**: `plans/wf_step.sh ${STORY_ID} preflight`

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R1_READ_ONLY_INTEGRITY_OK` | `git status --porcelain` unchanged (start == end) |
| `R1_EVIDENCE_LEDGER_COMPLETE` | Artifact exists, contains per-AT table, contains citations for enforcement + test, contains gap section, contains story verdict |

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

**Artifact requirements**:
- `review_logged.sh` outputs are normalized into canonical filenames (see [§6 Canonical Directory Layout](#6-artifact-layout--provenance)):
  - `<tool>.enriched.md` and `<tool>.generic.md` per tool
- Per-story manifest: `R3_EXTERNAL_MANIFEST.json` (source of truth, gate artifact)
- Per-story rendered summary: `R3_EXTERNAL_MANIFEST.md` (human-readable companion)

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
  "validated_preexisting_enforcement_citation": true,
  "validated_preexisting_test_citation": true,
  "validation_status": "completed"
}
```

**Blocking if**: missing basis line (exit 3), missing pre-existing citations (exit 4), missing phase mapping label (exit 5)

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

**Inputs**: `GAP_LIST.json` / `GAP_LIST.md`, story code + tests, R1 evidence ledgers

**Hard rules**:
- Fix only listed gaps (no unrelated refactors)
- Every change must map to one or more `GAP-*` IDs
- New tests follow premortem §6 proof plan (TRIP/NON-TRIP, causality)
- Golden vector rows must justify themselves ("This row catches [wrong impl from §5]")
- No `unwrap()` introduced in production paths
- Run tests before and after — no regressions

**Operator steps**:
1. Implement code/test/observability fixes for each gap
2. Update evidence ledger rows: GAP → FIXED, add new file:line citations
3. Generate proof graph: `python3 python/proof_graph/scaffold.py ${STORY_ID}`, populate from evidence ledger verdicts/citations, validate with `python3 python/proof_graph/validate.py --strict artifacts/story/${STORY_ID}/proof_graph.json`
4. Run verification commands (at least `verify.sh quick` + targeted tests)

**Output**:
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

**Operator steps**:
1. Run 5-skill stack on story-scope code (not just diff):
   - `/pr-review`
   - `/failure-mode-review`
   - `/strategic-failure-review`
   - `/contract-review`
   - `/devils-advocate`
2. Walk premortem: §2 assumptions → §4 decisions → §5 wrong impls → §6 proof plan → §10 STOPLIGHT
3. Fix all P0/P1 blockers immediately
4. Re-run affected skill(s) after fixes
5. Emit gate artifact with `head_commit` validation
6. Produce 5 skill receipts in `reviews/reconciliations/<slice>/receipts/`

**Output**:
- `SELF_REVIEW_R5b.md` (narrative)
- `R5B_SELF_REVIEW_GATE.json` (sidecar schema: `specs/schemas/recon/self_review_sidecar.schema.json`)
- 5 skill receipt JSONs in `receipts/`:
  - `r5b_pr_review.json`
  - `r5b_failure_mode_review.json`
  - `r5b_strategic_review.json`
  - `r5b_contract_review.json`
  - `r5b_devils_advocate.json`
**Receipt**: `plans/wf_step.sh ${STORY_ID} self_review`

**Gate checks (hard)**:

| Gate ID | Check |
|---------|-------|
| `R5B_SELF_REVIEW_PROVEN` | All 5 receipt files exist; `head_commit` in each == current HEAD; `started_at`/`ended_at` timestamps plausible; `exit_status == "completed"` for all; all `artifact_paths[]` exist on disk |

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

**Output**:
- `R6_VERIFY_SUMMARY.md` (narrative)
- `R6_VERIFY_SUMMARY.json` (schema: `specs/schemas/recon/verify_result.schema.json`) — JSON-primary (gate artifact)
**Receipt**: `plans/wf_step.sh ${STORY_ID} resolution`

**Gate checks (hard, pass-flip relevant)**:

| Gate ID | Check |
|---------|-------|
| `R6_PROOF_GATE` | Story verdict is RECONCILED or RECONCILED-WITH-DEBT |
| `R6_RUNTIME_ENFORCEMENT_GATE` | Every safety-critical AT is PROVEN-INTEGRATED; PROVEN-UNIT on safety-critical AT blocks pass |
| `R6_MECHANICAL_GATES` | Workflow receipts present; `verify.sh` passed; `contract_review.json` decision == "PASS"; `loss_mode` populated; R5b receipts verified |
| `R6_PROOF_GRAPH_GATE` | `proof_graph.json` exists; `validate.py --strict` passes; exemptions only via `proof_graph_exempt.txt` |

---

### R7 — Post-Reconciliation Validation (Cycle 2: FIX_DIFF + AT_REGRESSION)

**Mode**: `CYCLE2_POST_REMEDIATION_AUDIT`
**Cycle scope (hard)**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`

**Hard rule**: Cycle 2 cannot start unless `R5B_SELF_REVIEW_PROVEN` passed.

**Execution order**: R7a, R7b, R7c may run in parallel → apply fixes → R7d.1 + R7d.2 + R7e → R7f runs last.

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

#### R7b — Strategic Failure Review (cross-story/systemic)

**Command**: `/strategic-failure-review` on full reconciliation output
**Focus**: Hidden systemic risk, shared primitive blast radius, capital-risk path regressions
**Escalation**: If HIGH loss_mode guard is NOT-WIRED on live system → `OPERATIONAL_ESCALATION_REQUIRED`
**Output**: `R7B_STRATEGIC_REVIEW.md` + `R7B_STRATEGIC_REVIEW.json` (sidecar)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7B_STRATEGIC_REVIEW_COMPLETE` | Artifact exists; review basis line present; findings disposition recorded (FIXED / STRUCTURAL / DEFERRED) |

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

#### R7d — External Review Cycle 2 + Code Review Expert

##### R7d.1 — External Review Cycle 2 (mandatory, dual-prompt)

**Commands (per story, exact)**:
```bash
plans/review_logged.sh <STORY_ID> --tool codex --prompt enriched --base <BASE_BRANCH>
plans/review_logged.sh <STORY_ID> --tool codex --prompt generic  --base <BASE_BRANCH>
```
Repeat with additional tools as available. Minimum 1 tool, recommended 2+, both prompt styles.

**Required scope**: FIX_DIFF + AT_REGRESSION (not story-scope)
**Required basis line**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`
**Must verify**: gaps actually closed, no regressions, tests real/compiling/non-phantom

**Artifact requirements**:
- Normalized filenames: `<tool>.enriched.md`, `<tool>.generic.md` per tool
- Per-story manifest: `R7_EXTERNAL_MANIFEST.json` (source of truth, gate artifact)
- Per-story rendered summary: `R7_EXTERNAL_MANIFEST.md` (human-readable companion)

**`R7_EXTERNAL_MANIFEST.json` schema (required fields)**:
```json
{
  "schema_version": "r7_external_manifest.v1",
  "head_commit": "<sha>",
  "created_at": "<ISO 8601>",
  "story_id": "<STORY_ID>",
  "cycle": "C2",
  "review_basis": "FIX_DIFF + AT_REGRESSION (Cycle 2)",
  "base_commit": "<sha>",
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
  "validation_status": "completed"
}
```

**RECON-CLEAN exception**: If Cycle 1 + self-review found `BLOCKING=0` AND no code changed (`git diff → 0`):
1. Lead independently verifies `BLOCKING=0` claim (reads at least 1 Cycle 1 artifact)
2. Confirms R5b self-review `finding_counts` show `P0: 0, P1: 0`
3. Records: `RECON-CLEAN approved by: <lead>` + `RECON-CLEAN verified: reviewed <artifact>`
4. Manifest `validation_status` = `"recon_clean"` (exempt from dual-prompt requirement)

##### R7d.2 — Code Review Expert

**Command**: `code-review-expert` skill on full diff (R5 + R7a-R7c changes)
**Focus**: SOLID violations, security risks, boundary bugs, code quality
**Output**: `R7D_CODE_REVIEW_EXPERT.md` + `R7D_CODE_REVIEW_EXPERT.json` (sidecar)

**Gate checks**:

| Gate ID | Check |
|---------|-------|
| `R7D_EXTERNAL_C2_COMPLETE` | One C2 manifest per story; both prompt styles present per tool; review basis line present in all artifacts (or RECON-CLEAN approved) |
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
| `R7B_STRATEGIC_REVIEW_COMPLETE` | R7b |
| `R7C_WIRING_CLASSIFICATION_COMPLETE` | R7c |
| `R7C_NO_UNCLASSIFIED_SAFETY_AT` | R7c |
| `R7D_EXTERNAL_C2_COMPLETE` | R7d.1 |
| `R7D_CODE_REVIEW_EXPERT_COMPLETE` | R7d.2 |
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
| External C2 | `R7D_EXTERNAL_C2_COMPLETE` passed (or RECON-CLEAN approved) |
| Receipts | All 8 workflow receipts present (wf_step.sh chain) |
| Verify | `verify.sh full` passed with matching HEAD |
| Contract | `contract_review.json` has `decision: "PASS"` |
| Loss mode | `worst_case`, `fail_closed_cap`, `drift_metric` all populated |
| Proof graph | `proof_graph.json` validates with `validate.py --strict` (or story in exempt list) |
| Fail-closed | `fail_closed_coverage.sh` passes (test counts + patterns) |
| R7 exit | All R7 exit conditions met |

If any condition fails: **`prd_set_pass.sh` is blocked.**

---

## 5) Non-Negotiable Anti-Gaming Rules

1. **No diff-only review in Cycle 1** — Story-scope or rejected (`DIFF_ONLY_REVIEW_REJECTED`)
2. **No self-review of own batch** in cross-review phases
3. **No DEFERRED without debt entry** — schema-validated, not prose
4. **No "code is better" divergence** without evidence + lead approval
5. **No blanket `--theirs`** on tooling/prompt files without merge-base diff inspection
6. **No single-prompt reviews** — always both generic + enriched per tool
7. **No RECON-CLEAN without lead sign-off** on BLOCKING=0 claim
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
        R3_EXTERNAL_MANIFEST.md               # rendered summary (human-readable)

  # ── R4 / R4b: Gap List + Finding Mapping ──
  GAP_LIST.md
  GAP_LIST.json                               # JSON-primary
  R4B_EXTERNAL_MAPPING.json                   # JSON-primary
  R4B_EXTERNAL_MAPPING.md                     # rendered summary
  DEBT_REGISTER.json

  # ── R5: Remediation ──
  R5_REMEDIATION_NOTES.md
  R5_REMEDIATION_NOTES.json                   # sidecar (gap_id mappings, touched files)

  # ── R5b: Self-Review ──
  SELF_REVIEW_R5b.md
  R5B_SELF_REVIEW_GATE.json                   # sidecar (gate summary)
  receipts/
    r5b_pr_review.json
    r5b_failure_mode_review.json
    r5b_strategic_review.json
    r5b_contract_review.json
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
        R7_EXTERNAL_MANIFEST.md               # rendered summary (human-readable)

  # ── Final Roll-Up ──
  SUMMARY.md
  SUMMARY.json                                # optional sidecar for dashboards

artifacts/story/<STORY_ID>/
  proof_graph.json

plans/prompts/
  slice_reconcile_implement.md                # derived copy of Appendix A

plans/step_prompts/recon/
  self_review.md
  cycle1.md
  cycle2.md
```

### 6.2 Provenance Header (Required on All Review Artifacts)

Every review artifact (`.md` and `.json`) produced in R1–R7 must include a standard provenance header. This applies to internal reviews, external tool reviews, and manifests.

#### 6.2.1 Required Fields (5 mandatory)

| Field | Values |
|-------|--------|
| `tool` | `codex` \| `opus` \| `kimi` \| `internal` \| `script` |
| `model` | String (e.g., `gpt-5.3`, `claude-opus-4-6`, `kimi-k2.5`, `n/a`) |
| `prompt_style` | `generic` \| `enriched` \| `none` |
| `cycle` | `C1` \| `C2` \| `SELF` \| `NONE` |
| `phase_equivalent` | `R1` \| `R2` \| `R3` \| `R4` \| `R4b` \| `R5` \| `R5b` \| `R6` \| `R7a` \| `R7b` \| `R7c` \| `R7d` \| `R7e` \| `R7f` |

#### 6.2.2 Full Provenance Set (recommended for all artifacts)

| Field | Required? | Notes |
|-------|-----------|-------|
| `tool` | Yes | |
| `model` | Yes | `n/a` for internal/script |
| `prompt_style` | Yes | `none` for internal/script |
| `cycle` | Yes | |
| `phase_equivalent` | Yes | |
| `review_basis` | Yes (review phases) | Exact string, e.g. `STORY_SCOPE (Cycle 1)` |
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
| R5 | `R5_REMEDIATION_NOTES` | Markdown + sidecar | — |
| R5b | `SELF_REVIEW_R5b` / `R5B_SELF_REVIEW_GATE` | Markdown + sidecar | `self_review_sidecar.schema.json` |
| R6 | `R6_VERIFY_SUMMARY` | JSON-primary + .md companion | `verify_result.schema.json` |
| R7a | `R7A_CONTRACT_REVIEW` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| R7b | `R7B_STRATEGIC_REVIEW` | Markdown + sidecar | `review_artifact_sidecar.schema.json` |
| R7c | `R7C_WIRING_AUDIT` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| R7d.1 | `R7_EXTERNAL_MANIFEST` | JSON-primary + rendered .md | `r7_external_manifest.schema.json` |
| R7d.2 | `R7D_CODE_REVIEW_EXPERT` | Markdown + sidecar | `review_artifact_sidecar.schema.json` |
| R7e | `R7E_DEVILS_ADVOCATE` / `R7E_MUTATION_RESULTS` | Markdown + JSON | `review_artifact_sidecar.schema.json` |
| R7f | `R7F_DEBT_REGISTER_VALIDATION` | Markdown + JSON | — |
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
| `R5B_SELF_REVIEW_PROVEN` | R5b | Yes (blocks Cycle 2) |
| `R6_PROOF_GATE` | R6 | Yes |
| `R6_RUNTIME_ENFORCEMENT_GATE` | R6 | Yes |
| `R6_MECHANICAL_GATES` | R6 | Yes |
| `R6_PROOF_GRAPH_GATE` | R6 | Yes |
| `R7A_CONTRACT_REVIEW_COMPLETE` | R7a | Yes |
| `R7A_DECISION_PASS_REQUIRED` | R7a | Yes |
| `R7B_STRATEGIC_REVIEW_COMPLETE` | R7b | Yes |
| `R7C_WIRING_CLASSIFICATION_COMPLETE` | R7c | Yes |
| `R7C_NO_UNCLASSIFIED_SAFETY_AT` | R7c | Yes |
| `R7D_EXTERNAL_C2_COMPLETE` | R7d.1 | Yes |
| `R7D_CODE_REVIEW_EXPERT_COMPLETE` | R7d.2 | Yes |
| `R7D_BLOCKERS_RESOLVED` | R7d | Yes |
| `R7E_MUTATION_ANALYSIS_COMPLETE` | R7e | Yes |
| `R7E_SIMPLER_THAN_CORRECT_GATE` | R7e | Yes |
| `R7F_DEBT_SCHEMA_VALID` | R7f | Yes |
| `R7F_ALL_DEFERRED_MAPPED` | R7f | Yes |
| `R7F_NO_INVALID_DEBT_FIELDS` | R7f | Yes |
| `R7F_NO_OVERDUE_DEBT` | R7f | Yes |
