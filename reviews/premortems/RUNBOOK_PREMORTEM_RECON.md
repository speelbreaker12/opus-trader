# Premortem + Reconciliation Runbook

> Operator instructions only. For verdict definitions and gate rules, see [POLICY](PREMORTEM_RECON_POLICY.md). For anti-patterns and lessons, see [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md).

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
2. Group stories by shared files/dependencies (3-4 balanced batches)
3. Assign 4 writer agents by domain batch
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
| `cycle1` | R2 + R3 + R4 + R4b | B |
| `fix` | R7a-R7c fixes | C |
| `cycle2` | R7d + R7e + R7f | C |
| `resolution` | R6 | D |
| `verify_full` | `verify.sh full` | D |
| `pass` | `prd_set_pass.sh` | supervisor |

Receipt systems: `wf_step.sh` receipts (`.wf/receipts/<ID>/`) track step completion. R5b skill receipts (`reviews/reconciliations/<slice>/receipts/`) track individual skill execution.

---

### R1 — Parallel Reconcile (Read-Only)

**Goal**: Build per-story evidence ledgers and per-AT verdicts.

**Precondition**: `plans/premortem_ready.sh ${STORY_ID}` exits 0
**Command**: Agent executes `plans/step_prompts/recon/preflight.md`
**Read-only check**: `git status --porcelain` at start and end must match

**Rules**:
- NO code changes
- If critical fail-open found → emit `EMERGENCY-P0` immediately
- Required basis line: `Review basis: STORY_SCOPE (Cycle 1)`
- Required citations: at least 1 pre-existing enforcement point + 1 pre-existing test (not diff-only)

**Per-AT verdict assignment**: PROVEN | WEAK_PROOF | CLAIMED_NOT_PROVEN | UNTESTED_ENFORCEMENT | WRONG_IMPL_UNBLOCKED | DEFERRED (see [POLICY](PREMORTEM_RECON_POLICY.md) for definitions)

**Output**:
- `evidence_ledger.json` per story (schema: `specs/schemas/recon/evidence_ledger.schema.json`)
- Validate: `plans/validate_recon_artifact.sh evidence_ledger <path>`
**Receipt**: `plans/wf_step.sh ${STORY_ID} preflight`
**Blocking if**: `gate_result=NO-GO` or `read_only_violation=true`

### R1+ — External Review Cycle 1

**Goal**: Independent contract-proof audit on full story scope.

**Command**: `plans/review_logged.sh ${STORY_ID} --tool <codex|opus|kimi> --prompt enriched --base ${BASE_BRANCH}`

**Rules**:
- Minimum 1 tool, recommended 2+ tools
- Always run BOTH prompt styles per tool (generic + enriched)
- Scope: full story proof scope (not diff-only)
- Required basis line: `Review basis: STORY_SCOPE (Cycle 1)`
- Required: pre-existing enforcement + test citations

**Output** per tool per prompt style:
- `artifacts/story/<ID>/<tool>/<STAMP>_review.md`
- `review_receipt.json` (schema: `specs/schemas/recon/review_receipt.schema.json`)
**Blocking if**: missing basis line (exit 3), missing pre-existing citations (exit 4), missing phase mapping label (exit 5)

### R2 — Lead Evaluation

**Goal**: Review evidence ledgers for quality and correctness.

**Steps**:
1. Check citation accuracy (spot-check 2-3 per story)
2. Check verdict calibration (would you give the same per-AT verdict?)
3. Validate safety-critical AT escalation rules (WEAK_PROOF on MED/HIGH → CLAIMED_NOT_PROVEN)
4. Flag red flags: PROVEN with no file:line, PROVEN on §5 wrong-impl without tightening test, WEAK_PROOF treated as PROVEN

**Output**: `r2_lead_eval.json` (sidecar schema: `specs/schemas/recon/lead_eval_sidecar.schema.json`) + markdown narrative
**Format**: Markdown + JSON sidecar

### R3 — Internal Cross-Review (Cycle 1)

**Goal**: Independent story-scope audit by agents who did NOT write the evidence ledger.

**Rules**:
- Story-scope review, NOT diff-only
- Reviewers must NOT review their own batch
- Each reviewer reviews ALL stories they did not audit in R1
- Required basis line: `Review basis: STORY_SCOPE (Cycle 1)`
- Must satisfy pre-existing citation gate

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

**Output**: `r3_cross_reviews/<REVIEWER>.json` (schema: `specs/schemas/recon/cross_review.schema.json`)

### R4 — Synthesis + Gap List

**Goal**: Produce unified remediation plan.

**Steps**:
1. Mechanically aggregate R1/R2/R3 gap arrays (scripted, not LLM synthesis)
2. Deduplicate by AT + gap description
3. Assign gap IDs: `GAP-<STORY-ID>-<SEQ>` or `GAP-SYSTEMIC-<SEQ>`
4. Assign priority: P0 | P1 | P2 | DEFERRED
5. Create debt entries for all DEFERRED gaps
6. Lead resolves conflicts and assigns final priorities

**Output**:
- `r4_gap_list.json` (schema: `specs/schemas/recon/gap_list.schema.json`) — JSON-primary
- `DEBT_REGISTER.json` (schema in [POLICY](PREMORTEM_RECON_POLICY.md))
**Validate**: `plans/validate_recon_artifact.sh gap_list r4_gap_list.json`

### R4b — External Review Finding Mapping

**Goal**: Confirm all external Cycle 1 review findings are represented in the gap list.

**Checklist**:
- [ ] Every external review finding maps to: `gap_id` OR `false_positive_justification`
- [ ] No unmapped P0/P1 findings
- [ ] Disagreements recorded with lead decision

**Output**: `r4b_codex_mapping.json` (schema: `specs/schemas/recon/phase_mapping.schema.json`) — JSON-primary
**Blocking if**: unmapped P0/P1 finding exists

### R5 — Remediation

**Goal**: Fix gaps only. No wholesale rewrites.

**Rules**:
1. Fix only what's in the R4 gap list
2. Each fix must cite the gap ID in commit message
3. New tests follow premortem §6 proof plan (TRIP/NON-TRIP, causality)
4. Golden vector rows must justify themselves ("This row catches [wrong impl from §5]")
5. No `unwrap()` in production paths
6. Run existing tests before and after — no regressions

**Output**: Code changes + `r5_fix_receipts/`
**Receipt**: `plans/wf_step.sh ${STORY_ID} implement`

### R5b — Self-Review Gate

**Goal**: Burn internal reviewer attention before external review.

**Steps**:
1. Run 5-skill stack on story-scope code (not just diff):
   - `/pr-review`
   - `/failure-mode-review`
   - `/strategic-failure-review`
   - `/contract-review`
   - `/devils-advocate`
2. Walk premortem: §2 assumptions → §4 decisions → §5 wrong impls → §6 proof plan → §10 STOPLIGHT
3. Fix all P0/P1 blockers immediately
4. Emit gate artifact with `head_commit` validation
5. Produce 5 skill receipts in `reviews/reconciliations/<slice>/receipts/`

**Output**:
- `r5b_self_review_gate.json` (sidecar schema: `specs/schemas/recon/self_review_sidecar.schema.json`)
- `SELF_REVIEW_R5b.md` (narrative)
- 5 skill receipt JSONs
**Receipt**: `plans/wf_step.sh ${STORY_ID} self_review`
**Blocking if**: any skill receipt has `exit_status != "completed"` or `head_commit` mismatch

### R6 — Verify

**Goal**: Confirm remediation closed intended gaps.

**Required basis line**: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`

**Checklist**:
- [ ] All P0 gaps closed
- [ ] All P1 gaps closed or deferred with debt entry
- [ ] No WEAK_PROOF on MED/HIGH loss_mode ATs (escalated to CLAIMED_NOT_PROVEN)
- [ ] Tests compile and pass (`cargo test` / `verify.sh quick`)
- [ ] No phantom tests (all `implementation_tests[]` exist as `#[test]` functions)
- [ ] Evidence ledgers updated with FIXED status
- [ ] STOPLIGHT re-evaluated if remediation introduced new assumptions
- [ ] R5b skill receipts verified (existence + head_commit + timestamps + exit_status)

**Assign story verdicts**: RECONCILED | RECONCILED-WITH-DEBT | NOT RECONCILED (see [POLICY](PREMORTEM_RECON_POLICY.md))

**Output**: `r6_verify.json` (schema: `specs/schemas/recon/verify_result.schema.json`) — JSON-primary
**Receipt**: `plans/wf_step.sh ${STORY_ID} resolution`

### R6+ — External Review Cycle 2

**Goal**: Independent verification that fixes closed gaps without opening new ones.

**Command**: `plans/review_logged.sh ${STORY_ID} --tool <codex|opus|kimi> --prompt enriched --base ${BASE_BRANCH}`

**Rules**:
- Scope: FIX_DIFF + AT_REGRESSION
- Required basis line: `Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)`
- Must verify: gaps actually closed, no regressions, tests real/compiling/non-phantom
- Minimum 1 tool, recommended 2+ tools, both prompt styles

**RECON-CLEAN exception**: If Cycle 1 + self-review found `BLOCKING=0` AND no code changed (`git diff → 0`):
1. Lead independently verifies `BLOCKING=0` claim (reads at least 1 Cycle 1 artifact)
2. Confirms R5b self-review `finding_counts` show `P0: 0, P1: 0`
3. Records: `RECON-CLEAN approved by: <lead>` + `RECON-CLEAN verified: reviewed <artifact>`

**Output**: `artifacts/story/<ID>/<tool>/<STAMP>_review.md` + `review_receipt.json`

### R7 — Post-Reconciliation Reviews

**Goal**: Final hardening before pass-flip. R7a-R7c run in parallel. R7d-R7e run after R7a-R7c fixes applied. R7f runs last.

#### R7a — Contract Review
**Command**: `/contract-review` scoped to R5 diff
**Catches**: Fail-open hazards, invalid enum values, contract drift from remediation
**Output**: `CONTRACT_REVIEW_R5.md` + sidecar

#### R7b — Strategic Failure Review
**Command**: `/strategic-failure-review` on full reconciliation output
**Catches**: Systemic cross-story risks, "island of guards" pattern
**Escalation**: If HIGH loss_mode guard is NOT-WIRED on live system → `OPERATIONAL_ESCALATION_REQUIRED`
**Output**: `STRATEGIC_REVIEW_R5.md` + sidecar

#### R7c — Production Wiring Audit
**Command**: Trace call chain from each enforcement function to entry points in `specs/ENTRY_POINTS.md`
**Classify each safety-critical AT**:
- **PROVEN-INTEGRATED** — reachable from production entry point
- **PROVEN-UNIT** — zero production callers (island guard)
**Output**: `LSP_CALL_CHAIN_CHECK.md` + sidecar

#### R7d — Code Review Expert
**Command**: `code-review-expert` skill on full diff (R5 + R7a-R7c changes)
**Catches**: SOLID violations, security risks, boundary bugs
**Output**: `CODE_REVIEW_R7.md` + sidecar

#### R7e — Devils Advocate
**Command**: `/devils-advocate` on full proving suite for gapped ATs
**Scope**: ALL proving tests for flagged ATs (not just new tests)
**Machine verification**: `cargo mutants --file <enforcement>.rs -- --test <proving_targets>`
**Two-pass**: Run analysis → fix gaps → rerun to confirm closure
**Output**: `DEVILS_ADVOCATE_R7.md` + `DEVILS_ADVOCATE_R7_RECHECK.md` + sidecars

#### R7f — Debt Register Validation
**Checks**:
- Every DEFERRED gap has matching `gap_id` in `DEBT_REGISTER.json`
- No entry has `target_slice: "TBD"` or empty `owner`
- No overdue debt (target_slice already passed)
**Output**: Validation result in `r7f_debt_validation.json`
**Blocking if**: any violation found

**Receipt**: `plans/wf_step.sh ${STORY_ID} cycle2`

---

## 4) Pass-Flip Gate

**Command**: `plans/prd_set_pass.sh ${STORY_ID} true`

A story is pass-eligible only if ALL conditions are met:

| Gate | Check |
|------|-------|
| Proof | Story verdict is RECONCILED or RECONCILED-WITH-DEBT |
| Wiring | Every safety-critical AT is PROVEN-INTEGRATED |
| Gaps | No unresolved P0/P1 |
| Debt | DEBT_REGISTER.json valid for all deferred items |
| External C1 | External Cycle 1 review artifact exists and findings are mapped (R4b) |
| External C2 | External Cycle 2 review artifact exists (or RECON-CLEAN approved) |
| Receipts | All 8 workflow receipts present (wf_step.sh chain) |
| Verify | `verify.sh full` passed with matching HEAD |
| Contract | `contract_review.json` has `decision: "PASS"` |
| Loss mode | `worst_case`, `fail_closed_cap`, `drift_metric` all populated |
| Proof graph | `proof_graph.json` validates with `validate.py --strict` (or story in exempt list) |
| Fail-closed | `fail_closed_coverage.sh` passes (test counts + patterns) |

If any condition fails: **`prd_set_pass.sh` is blocked.**

---

## 5) Non-Negotiable Anti-Gaming Rules

1. **No diff-only review in Cycle 1** — Story-scope or rejected
2. **No self-review of own batch** in cross-review phases
3. **No DEFERRED without debt entry** — schema-validated, not prose
4. **No "code is better" divergence** without evidence + lead approval
5. **No blanket `--theirs`** on tooling/prompt files without merge-base diff inspection
6. **No single-prompt reviews** — always both generic + enriched per tool
7. **No RECON-CLEAN without lead sign-off** on BLOCKING=0 claim
8. **No fake citations** — file:line must contain enforcement/test, not whitespace

See [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md) for the full catalog with root causes and fixes.

---

## 6) Artifact Format Summary

| Phase | Artifact | Format | Schema |
|-------|----------|--------|--------|
| R1 | evidence_ledger | JSON-primary | `evidence_ledger.schema.json` |
| R1+ | external review receipt | JSON-primary | `review_receipt.schema.json` |
| R2 | lead evaluation | Markdown + sidecar | `lead_eval_sidecar.schema.json` |
| R3 | cross-review | JSON-primary | `cross_review.schema.json` |
| R4 | gap list | JSON-primary | `gap_list.schema.json` |
| R4b | finding mapping | JSON-primary | `phase_mapping.schema.json` |
| R5b | self-review gate | Markdown + sidecar | `self_review_sidecar.schema.json` |
| R6 | verify result | JSON-primary | `verify_result.schema.json` |
| R6+ | external review receipt | JSON-primary | `review_receipt.schema.json` |
| R7a-e | review artifacts | Markdown + sidecar | `review_artifact_sidecar.schema.json` |
| R7f | debt validation | JSON-primary | (inline in DEBT_REGISTER.json) |
| Gate | premortem ready | JSON-primary | `premortem_ready.schema.json` |

**Rule**: If the artifact directly controls a gate or pass-flip → JSON-primary. If it primarily supports human reasoning → markdown + JSON sidecar.

### Guardrail Fields (All Artifacts)

Every JSON artifact (primary or sidecar) must include:

```json
{
  "schema_version": "<schema_name>.v1",
  "head_commit": "<current HEAD sha>",
  "created_at": "<ISO 8601 UTC>"
}
```

Sidecar artifacts additionally include:
```json
{
  "markdown_sha256": "<sha256 of companion .md file>",
  "markdown_path": "<relative path to .md file>"
}
```

Validators reject if: `head_commit` mismatch, `markdown_sha256` drift, unsupported `schema_version`.

---

## 7) Quick Verdict Reference

| Verdict | Scope | Meaning |
|---------|-------|---------|
| PROVEN | Per-AT | Enforcement exists, test proves causality, fail-closed confirmed |
| WEAK_PROOF | Per-AT | Test exists but only checks "something happened," not which guard |
| CLAIMED_NOT_PROVEN | Per-AT | No enforcement or no causal test |
| WRONG_IMPL_UNBLOCKED | Per-AT | §5 wrong impl has no tightening test |
| RECONCILED | Story | All P0/P1 closed, unit correctness proven |
| RECONCILED-WITH-DEBT | Story | P2 items deferred, debt register populated |
| NOT RECONCILED | Story | P0 gaps remain open |
| PROVEN-INTEGRATED | Wiring | Guard reachable from production entry point |
| PROVEN-UNIT | Wiring | Guard has zero production callers |

Full definitions and escalation rules in [POLICY](PREMORTEM_RECON_POLICY.md).
