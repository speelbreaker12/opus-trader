# Reconciliation Policy

> Normative rules governing verdicts, gates, artifact schemas, and review scope.
> For execution instructions, see [RUNBOOK](RUNBOOK_PREMORTEM_RECON.md).
> For anti-patterns and lessons, see [ANTIPATTERNS](PREMORTEM_RECON_ANTIPATTERNS.md).
> For metrics and rationale, see [METRICS](PREMORTEM_RECON_METRICS.md).

---

## 1. Glossary (Normative)

| Term | Definition |
|------|------------|
| AT | Acceptance Test -- a contract clause translated into a verifiable behavior. |
| TRIP Test | A test that triggers a safety guard and proves causality (e.g., asserts `dispatch_count == 0` AND `reject_reason == X`). |
| NON-TRIP Test | A test that verifies the absence of a guard trigger under valid conditions (pass-through proof). |
| STOPLIGHT | Premortem readiness status: RED (blockers exist, do not implement), YELLOW (deferred debt accepted), GREEN (ready to implement). |
| Enforcement Point | Specific `file:line::function` where a contract clause is enforced (guard, check, or validation). |
| Wrong Impl | An easier/cheaper implementation that satisfies naive tests but violates the contract. |
| Tightening Test | A test specifically designed to distinguish the correct implementation from a predicted wrong implementation. |
| Fail-Closed | Error/edge-case handling that defaults to rejection/degradation (not warn-and-continue). |
| Golden Vector | A table-driven test with 10-30 input cases covering boundary, NaN/Inf/missing, and wrong-impl scenarios. |
| Evidence Ledger | Per-story document produced during reconciliation with file:line citations for every audit check. |
| Simpler-Than-Correct Gate | A meta-check: "Is there any implementation SIMPLER than the correct one that passes the entire test suite?" If yes, the suite has a mutation gap. Applied in Phase R5b.1 (preliminary, reviewers catch gaps) and definitively in Phase R7e (independent auditor). R5b is defense-in-depth; it does not replace R7e. |
| Proof Graph | Per-story `proof_graph.json` -- structured JSON mapping each AT to enforcement point, tests, wiring status, observability, and verdict. Validated by `python/proof_graph/validate.py` with 60 rules (43 V1+V2, 17 V2-only). Schema versions 1 and 2. |
| Story Proof Scope | The minimum context needed to audit a story's contract compliance: PRD item, `enforcing_contract_ats[]`, premortem (especially sections 2/4/5), recon preflight, `scope.touch` files, proving test files from `implementation_tests[]`, relevant `specs/CONTRACT.md` sections, and direct integration surfaces for causality. |
| Review Basis | An explicit label every reviewer must include in their output: `STORY_SCOPE (Cycle 1)` or `FIX_DIFF + AT_REGRESSION (Cycle 2)`. |

---

## 2. Verdict Systems

### 2.1 Per-AT Verdicts

| Verdict | Meaning |
|---------|---------|
| **PROVEN** | Enforcement exists, test proves causality, fail-closed confirmed. |
| **WEAK_PROOF** | Test exists but checks "something happened," not which guard caused it. |
| **CLAIMED_NOT_PROVEN** | No enforcement found, or enforcement exists but no causal test. |
| **UNTESTED_ENFORCEMENT** | Enforcement point and test both exist but are disconnected. |
| **WRONG_IMPL_UNBLOCKED** | A wrong-impl from the premortem has no tightening test to distinguish it from correct. |
| **DEFERRED** | AT not yet implemented; tracked in debt register. |

**PROVEN requires cause-specific assertions**: at least one of `reject_reason`, `dispatch_count`, `latch_reason`, or `mode_transition`.

**Safety-critical escalation**: `WEAK_PROOF` on a MED/HIGH `loss_mode` AT is treated as `CLAIMED_NOT_PROVEN` and blocks `RECONCILED`. Asserting `result.is_err()` without verifying which guard caused the rejection is insufficient for safety-critical ATs.

**LOW risk tolerance**: `WEAK_PROOF` on a LOW `loss_mode` AT may be accepted as `RECONCILED-WITH-DEBT`, but only with a debt register entry (`DEBT_REGISTER.json`) specifying `owner` and `target_slice` for the proof upgrade. `WEAK_PROOF` without a debt entry is treated as `CLAIMED_NOT_PROVEN` regardless of risk level.

### 2.2 Evidence Ledger Intermediate Verdict

| Verdict | Meaning |
|---------|---------|
| **PARTIAL** | At least one AT has gaps requiring remediation. Replaced by a final verdict in Phase R6. |

### 2.3 Story-Level Verdicts

| Verdict | Meaning |
|---------|---------|
| **RECONCILED** | All premortem requirements verified in code. All P0/P1 gaps fixed. Unit correctness proven. |
| **RECONCILED-WITH-DEBT** | Requirements verified but P2 items deferred. Debt register populated. |
| **NOT RECONCILED** | P0 gaps remain open. Enforcement missing or tests absent. |
| **RECONCILED_UNIT_ONLY** | Unit correctness proven but at least one safety-critical AT is PROVEN-UNIT (not wired into production). Blocks pass-flip via the runtime-enforcement gate. |

**Derivation rules** (evaluated in order):
1. Any `CLAIMED_NOT_PROVEN` or `WRONG_IMPL_UNBLOCKED` on a safety-critical AT → `NOT RECONCILED`.
2. All per-AT verdicts permit reconciliation but R7c wiring audit shows `PROVEN-UNIT` on at least one safety-critical AT → `RECONCILED_UNIT_ONLY`.
3. All P0/P1 gaps fixed, no debt → `RECONCILED`.
4. All P0/P1 gaps fixed, P2 items deferred with debt register entries → `RECONCILED-WITH-DEBT`.

### 2.4 Wiring Qualifiers

| Qualifier | Meaning |
|-----------|---------|
| **PROVEN-INTEGRATED** | Function works AND has production callers (reachable from a defined entry point). |
| **PROVEN-UNIT** | Function works but has zero production callers (island guard). |

Wiring status does **not** change the proof verdict. `RECONCILED` means "unit correctness proven," which remains true regardless of wiring.

### 2.5 Runtime-Enforcement Gate

Separate from proof verdict. `prd_set_pass.sh` requires that every safety-critical AT is `PROVEN-INTEGRATED`.

| Condition | Pass-Eligible? |
|-----------|---------------|
| `PROVEN-INTEGRATED` on all safety-critical ATs | Yes |
| `PROVEN-UNIT` on any safety-critical AT | **No** -- blocked; requires integration story |
| `PROVEN-UNIT` on non-safety-critical ATs (observability, metrics) | Yes -- track as debt |

A story can be `RECONCILED` (proof valid) but still blocked from passing because its guards are not wired.

---

## 3. Hard Gate Definitions

### 3.1 STOPLIGHT Gate

| STOPLIGHT | Action |
|-----------|--------|
| **RED** | STOP. Premortem has unresolved blockers. Fix premortem first. |
| **YELLOW** | Proceed. All deferred items must appear in the evidence ledger's gap list. |
| **GREEN** | Proceed. |

If no premortem exists for a story, write one first (Part A). Reconciliation without a premortem is ad-hoc code review.

If both the premortem and the recon preflight have a STOPLIGHT, the more restrictive gate wins.

### 3.2 PREMORTEM_READY Gate

**Command**: `plans/premortem_ready.sh ${STORY_ID}` — mechanical enforcement of all six checks.

Six checks, evaluated in order:

| # | Check | Failure | Exit |
|---|-------|---------|------|
| 1 | Premortem file exists | `NO-GO: PREMORTEM_MISSING`. Write premortem first (Mode A). No surrogate path. | Stop |
| 2 | All sections §0-§10 present | `NO-GO: SECTIONS_MISSING` (delegates to `premortem_gate.sh`) | Stop |
| 3 | STOPLIGHT is not RED | `NO-GO: STOPLIGHT_RED` | Stop |
| 4 | If STOPLIGHT is YELLOW: every gap marked DEFERRED or FIX IN STEP 5 | `NO-GO: UNRESOLVED_YELLOW_GAPS` | Stop |
| 5 | No AT ownership conflicts (no AT claimed as primary by 2+ stories) | `NO-GO: AT_OWNERSHIP_CONFLICT` | Stop |
| 6 | Required context files exist (`specs/CONTRACT.md`, prd.json entry, scope.touch files) | `NO-GO: MISSING_ARTIFACT: <filename>` | Stop |

All six are hard stops. If any check fails, reconciliation cannot proceed.

### 3.3 Review Basis Line (Hard Rule)

Every review artifact must include:

```
Review basis: STORY_SCOPE (Cycle 1)
```
or
```
Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)
```

**Enforcement**: Validation scripts grep for the Review Basis line. A missing line produces `REVIEW_BASIS_MISSING` warning that the lead must acknowledge. Does not block but must be dispositioned.

### 3.4 Pre-Existing Citation Gate (Cycle 1 -- Hard Rule)

A Cycle 1 review artifact must cite at least one **pre-existing enforcement point** (file:line of a guard/gate function) AND at least one **pre-existing proving test** (file:line of a test function) from the story proof scope -- neither of which appears in the `git diff`.

- Reviewers must label their citations as `enforcement` or `test`.
- If every cited file:line in the review also appears in the diff, the review is auto-rejected with `DIFF_ONLY_REVIEW_REJECTED`.
- Citing a random utility function does not satisfy the gate. The cited enforcement point and test must be from the story's contract proof.

### 3.5 Phase-Mapping Requirement

When using external review tools (outside the R1-R7 phase structure), each review batch must be explicitly labeled with its phase-equivalent and cycle. Example: `Kimi C1 = Phase R1 (story-scope audit)`, `Codex C2 enriched = Phase R7 (post-remediation)`.

### 3.6 Evidence Ledger Requirement

Every story must have an evidence ledger (one per story) before the `cycle1` receipt can be issued. The evidence ledger maps each AT to its verdict with file:line citations.

### 3.7 RECON-CLEAN Independent Verification Gate

When Cycle 2 is abbreviated via the Cycle-2 manifest `recon_clean_single` mode, the lead must independently verify:

1. Confirm explicit manifest fields (Cycle 2 manifest or self-review manifest):
   - `cycle2_path.mode == "recon_clean_single"`
   - `cycle2_path.single_combo_choice.tool` and `.prompt_style` match the selected single Cycle 2 review
   - `cycle2_path.single_combo_justification` is non-empty
2. Confirm `r5b` was a no-fix path (`R5B_NO_FIXES_NEEDED.md` exists) and its JSON finding counts are `P0: 0, P1: 0, P2: 0`.
3. Record verification in the resolution artifact: `RECON-CLEAN verified: reviewed <artifact name>, confirmed mode: recon_clean_single`.
4. Include lead sign-off: `RECON-CLEAN approved by: <lead name/agent>`.

Without independent verification, RECON-CLEAN is not valid.

#### 3.7.1 Required RECON-CLEAN Data Fields

Manifest/summary fields that drive Cycle-2 flow and RECON-CLEAN eligibility must be explicit:

- `cycle2_path.mode` (`"dual_combo"` or `"recon_clean_single"`)
- `cycle2_path.required_combinations` (`array`)
- `cycle2_path.single_combo_choice` (`object`; required when `mode="recon_clean_single"`)
- `cycle2_path.single_combo_justification` (`string`; required when `mode="recon_clean_single"`)

### 3.8 R5b Skill Receipt Validation

Six receipt files must exist at `reviews/reconciliations/<slice>/receipts/`:

| Skill | Receipt filename |
|-------|-----------------|
| `/pr-review` | `r5b_pr_review.json` |
| `/failure-mode-review` | `r5b_failure_mode_review.json` |
| `/strategic-failure-review` | `r5b_strategic_review.json` |
| `/contract-review` | `r5b_contract_review.json` |
| `/validator-audit` | `r5b_validator_audit.json` |
| `/devils-advocate` | `r5b_devils_advocate.json` |

Additionally, the R5b planning/fix artifacts must exist:
- `R5B_FIX_PLAN.md` — synthesis + fix plan (R5b.2 output)
- `R5B_FIX_LOG.md` or `R5B_NO_FIXES_NEEDED.md` — fix record (R5b.3 output)

**Validation checks** (all must pass or Cycle 2 is blocked with `SELF_REVIEW_UNPROVEN: <reason>`):

1. All 6 receipt files exist.
2. Each receipt's `head_commit` matches current HEAD (prevents stale receipts).
3. Each receipt's `started_at`/`ended_at` timestamps are plausible and within the R5b window.
4. Each receipt's `exit_status` is `"completed"` (not `"skipped"` or `"failed"`).
5. Each receipt's `artifact_paths[]` reference files that exist on disk.
6. `R5B_FIX_PLAN.md` exists.
7. `R5B_FIX_LOG.md` or `R5B_NO_FIXES_NEEDED.md` exists.

### 3.9 prd_set_pass.sh Gate

Fifteen checks, all must pass:

| # | Check | What blocks |
|---|-------|-------------|
| 1 | Story verdict is `RECONCILED` or `RECONCILED-WITH-DEBT` | `NOT RECONCILED` blocks; `RECONCILED_UNIT_ONLY` passes this check but is always blocked by check #2 |
| 2 | Every safety-critical AT is `PROVEN-INTEGRATED` | `PROVEN-UNIT` on safety-critical AT blocks (this is the gate that blocks `RECONCILED_UNIT_ONLY` stories) |
| 3 | All 8 workflow receipts present (`.wf/receipts/<ID>/`) | Missing receipt blocks |
| 4 | `verify.sh` passed | Failed verification blocks |
| 5 | `contract_review.json` contains `"decision": "PASS"` | Non-PASS decision blocks |
| 6 | `loss_mode` fields populated (all 3 subfields: `worst_case`, `fail_closed_cap`, `drift_metric`) | Empty or TBD blocks (exempt: policy/certification stories) |
| 7 | R5b skill receipts verified (6 files, head_commit match, timestamps, exit_status, artifact_paths) + fix plan/log exist | Any `SELF_REVIEW_UNPROVEN` blocks |
| 8 | No `WEAK_PROOF` on MED/HIGH `loss_mode` ATs | Remaining WEAK_PROOF blocks |
| 9 | Debt register valid: every DEFERRED gap has entry, no TBD target_slice, no empty owner | Invalid debt entry blocks |
| 10 | No overdue debt (target_slice already passed) | Overdue debt blocks until re-targeted |
| 11 | `proof_graph.json` exists at `artifacts/story/<ID>/proof_graph.json` | Missing proof graph blocks (unless listed in `plans/proof_graph_exempt.txt`) |
| 12 | `python/proof_graph/validate.py --strict` passes (60 rules, WARNs promoted to ERRORs) | Exit code 1 on failure blocks; exit code 20 on trading halt |
| 13 | `R3_EXTERNAL_C1_COMPLETE` passed; all external C1 findings mapped via R4b | Unmapped external finding blocks |
| 14 | `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO` or `R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE` passed (mode + findings-driven selection) | Missing Cycle 2 review gate |
| 15 | `fail_closed_coverage.sh` passes (test counts + fail-closed keyword patterns) | Insufficient fail-closed test coverage blocks |

### 3.10 Proof Graph Gate

`validate.py --strict` enforces 60 rules (R-001..R-057 + R-006b/R-016b/R-024b). Key rules include:

- R-001: RECONCILED verdict with BLOCKING contradiction
- R-004: Stale test SHA
- R-007: Phantom AT not in `specs/CONTRACT.md`
- R-008: Placeholder detection
- R-015: FAIL_OPEN_RISK
- R-016b: Safety-critical AT without TRIP tests
- R-050: Duplicate at_id detection
- R-052: Wiring-verdict alignment
- R-053: YELLOW stoplight on safety_critical
- R-056: DEFERRED verdict on safety_critical AT
- R-057: UNTESTED_ENFORCEMENT/CLAIMED_NOT_PROVEN on safety_critical AT

Exit codes: 0 (pass), 1 (validation failure), 2 (usage/schema error), 3 (file/parse error), 20 (trading halt).

Generate skeleton: `python3 python/proof_graph/init.py <ID> --premortem-path reviews/premortems/<ID>_premortem.md`.

---

## 4. Review Scope Rules

### 4.1 Two Review Cycles

| Cycle | When | Scope | Mental model |
|-------|------|-------|--------------|
| **Cycle 1** | After Phase R1 (initial audit) | Full story-scope implementation -- the current code, not just what changed | "I inherited this code and I'm trying to break its proof" |
| **Cycle 2** | After Phase R5/R5b (remediation + self-review) | Fix diff + AT regression spot-check on affected proofs | "Did the fixes close the gaps without opening new ones?" |

### 4.2 Story Proof Scope (Default Review Unit)

The default review scope is the story proof scope -- not the diff, not the whole slice:

1. PRD item for the story (`jq '.stories["<ID>"]' plans/prd.json`)
2. `enforcing_contract_ats[]` -- which ATs this story claims to enforce
3. Premortem (`reviews/premortems/<ID>_premortem.md`) -- especially sections 4, 5, 2
4. Recon preflight artifact (AT proof audit from Step 1)
5. `scope.touch` files -- the actual implementation source code
6. Proving test files from `implementation_tests[]`
7. Relevant `specs/CONTRACT.md` sections only (not the whole contract)
8. Direct integration surfaces only if needed (e.g., PolicyGuard/WAL/TLSM) to validate causality

The framing is "contract-proof audit," not "code review."

### 4.3 Escalation to Wider Scope

Escalate beyond story-scope only when:

| Trigger | Action |
|---------|--------|
| Story touches a shared primitive (PolicyGuard, TradingMode, WAL, dispatch gate) | Review all stories that depend on the primitive |
| Reviewer finds a pattern bug likely repeated elsewhere | Spot-check 2-3 other stories for the same pattern |
| Modified module is used by multiple stories (blast radius) | Review affected siblings' AT proofs |

Default to story-scope.

### 4.4 Review Basis Enforcement

- Cycle 1: `STORY_SCOPE` -- full story implementation, not diff-only.
- Cycle 2: `FIX_DIFF + AT_REGRESSION` -- remediation diff plus targeted re-check of AT proofs affected by changes.
- Every review artifact (self-review and external) must include the Review Basis line.
- **GREEN path (recon only)**: If Cycle 1 + self-review reported zero blocking findings and no code changed, Cycle 2 requires only 1 external artifact (relaxed). `recon_relaxation: "min_reviews_relaxed_to_1"` is emitted only when manifest fields confirm:
  - `code_changed == false`
  - `finding_counts.P0 == 0`
  - `finding_counts.P1 == 0`
  - `blocking_findings_present == false`
- **YELLOW/RED path**: Code changed in fix step → 2 external artifacts required (full). `prd_set_pass.sh` must be re-run regardless of prior `passes=true` status.
- Cycle 2 R7d-R7e scope: remediation diff (R5 + R5b + R7a-c changes) plus targeted re-check of AT proofs affected by those changes. If a fix modified a test for AT-960, re-run mutation analysis on AT-960's full proof chain.

---

## 5. Artifact Schema Rules

### 5.1 Format Rule

- **Gate-driving artifacts**: JSON-primary. Markdown is rendered only (never edited manually).
- **Human judgment artifacts**: Markdown + JSON sidecar. Markdown is source of truth; sidecar is gate summary.

### 5.1a Evidence Packager Contract (JSON-first)

To reduce duplicated transcription, each phase uses a packager workflow:

1. Reviewer provides the JSON evidence in the prescribed schema.
2. The packager renders markdown companions for review readability.
3. Gate checks compare rendered artifacts against JSON keys and `markdown_sha256` drift.

Packager-only expectations:

- Phase artifacts listed as JSON-primary in this policy are machine sources.
- Markdown companions are review ergonomics and may summarize; they must not introduce required facts absent from JSON.
- If a required field is absent in JSON, manual review can continue but the gate cannot pass.

### 5.2 Schema Inventory

| Artifact | Format | Phase | Location |
|----------|--------|-------|----------|
| Evidence ledger | Markdown (source) | R1 | `reviews/reconciliations/<slice>/<ID>_reconciliation.md` |
| Skill receipts (6) | JSON-primary | R5b.1 | `reviews/reconciliations/<slice>/receipts/r5b_*.json` |
| Fix plan | Markdown | R5b.2 | `reviews/reconciliations/<slice>/R5B_FIX_PLAN.md` |
| Fix log | Markdown | R5b.3 | `reviews/reconciliations/<slice>/R5B_FIX_LOG.md` |
| Gap list (cross-review output) | JSON + Markdown | R3/R4 | `reviews/reconciliations/<slice>/GAP_LIST.md` |
| Debt register | JSON-primary | R7f | `reviews/reconciliations/<slice>/DEBT_REGISTER.json` |
| Proof graph | JSON-primary | R6 | `artifacts/story/<ID>/proof_graph.json` |
| Self-review | Markdown (source) | R5b | `reviews/reconciliations/<slice>/SELF_REVIEW_R5b.md` |
| Contract review | Markdown (source) | R7a | `reviews/reconciliations/<slice>/R7A_CONTRACT_REVIEW.md` |
| Strategic review | Markdown (source) | risk-gate R7b | `reviews/reconciliations/<slice>/R7B_STRATEGIC_REVIEW.md` |
| Wiring audit | Markdown (source) | R7c | `reviews/reconciliations/<slice>/R7C_WIRING_AUDIT.md` |
| Devils advocate | Markdown (source) | R7e | `reviews/reconciliations/<slice>/R7E_DEVILS_ADVOCATE.md` |
| Devils advocate recheck | Markdown (source) | R7e | `reviews/reconciliations/<slice>/R7E_DEVILS_ADVOCATE_RECHECK.md` |

### 5.3 Guardrail Fields

All JSON-primary artifacts must include:

| Field | Purpose |
|-------|---------|
| `schema_version` | Reject on unsupported version |
| `head_commit` | Reject on mismatch with current HEAD |
| `created_at` | Timestamp for staleness detection |

JSON sidecar artifacts additionally include:

| Field | Purpose |
|-------|---------|
| `markdown_sha256` | Reject on drift from source markdown |
| `markdown_path` | Path to source markdown file |

### 5.4 Validator Rules

The validator rejects on:
- `head_commit` mismatch with current HEAD
- `markdown_sha256` drift (sidecar no longer matches markdown source)
- Unsupported `schema_version`

---

## 6. Evidence Pack Requirements

Every reconciled story must produce this minimum set. Missing items block the `RECONCILED` verdict.

| # | Artifact | Phase | What it proves |
|---|----------|-------|---------------|
| 1 | **Preflight artifact** (AT proof audit table) | R1 | Each AT has an enforcement point + proving test (or explicit gap) |
| 2a | **Self-review artifact** (with premortem cross-check + Evidence Index) | R5b | 6-skill stack run (R5b.1); findings synthesized + fix plan written (R5b.2); fixes applied (R5b.3); affected skills re-run (R5b.4) |
| 2b | **Skill receipts** (6 JSON files in `reviews/reconciliations/<slice>/receipts/`) | R5b.1 | Machine-verifiable proof that each skill was executed (head_commit matches, timestamps plausible, artifacts exist) |
| 2c | **Fix plan + fix log** (`R5B_FIX_PLAN.md` + `R5B_FIX_LOG.md`) | R5b.2-3 | Auditable record of what was planned vs what was changed |
| 3 | **Cycle 1 external review artifact(s)** (logged via `review_logged.sh`) | R3 | Independent auditor confirmed contract compliance on story proof scope |
| 4 | **Cycle 2 external review artifact(s)** (logged, or `RECON-CLEAN` exception) | R7 | Fix diff verified; Cycle 1 findings closed; no regressions |
| 5 | **Review resolution artifact** | R6 | All BLOCKING findings closed; verdicts assigned with evidence |
| 6 | **Verify output** + `verify.meta.json` | verify_full | `verify.sh` passed with correct mode/head; test count matches |
| 7a | **Test output + diff summary** *(if code changed)* | R5/R5b | Fixes compile, tests pass, diff is additive |
| 7b | **`NO_CODE_CHANGE_AUDIT_ONLY` section** *(if no code changed)* | R5b | Negative evidence: `git diff -> 0`, proof checks still run, no fixes needed |
| 8 | **`proof_graph.json`** | R6 | Machine-verifiable proof graph: per-AT enforcement, tests, wiring, verdicts; validated by `validate.py --strict` at pass-flip |

**RECON-CLEAN exception (item 4)**: If Cycle 1 + self-review found zero BLOCKING findings and the story required no code changes, Cycle 2 may be replaced by an abbreviated RECON-CLEAN note. The note must include:
- Confirmation that preflight + self-review + Cycle 1 found `BLOCKING=0`
- `git diff -> 0` proof
- Explicit statement: "Cycle 2 abbreviated: no fix diff to review"
- Lead sign-off: `RECON-CLEAN approved by: <lead name/agent>`
- Independent verification per Section 3.7

---

## 7. Debt Register Schema

Location: `reviews/reconciliations/<slice>/DEBT_REGISTER.json`

### 7.1 Required Fields

```json
{
  "debt_items": [
    {
      "gap_id": "GAP-007-3",
      "story_id": "S1-007",
      "at_id": "AT-920",
      "description": "Observability: structured log on rejection path",
      "priority": "P2",
      "owner": "reconcile-dispatch",
      "target_slice": "S2",
      "created_at": "2026-02-21T15:00:00Z",
      "status": "open"
    }
  ]
}
```

| Field | Type | Constraint |
|-------|------|------------|
| `gap_id` | string | Must match a DEFERRED gap in an evidence ledger |
| `story_id` | string | Valid story ID |
| `at_id` | string | Valid AT ID |
| `description` | string | Non-empty |
| `priority` | string | `P0` / `P1` / `P2` / `DEFERRED` |
| `owner` | string | Non-empty (not blank, not "TBD") |
| `target_slice` | string | Valid slice ID (not "TBD") |
| `created_at` | string | ISO 8601 timestamp |
| `status` | string | `open` / `resolved` |

### 7.2 R7f Validation Rules

1. Every `DEFERRED` gap in evidence ledgers has a matching `gap_id` in the debt register.
2. No entry has `target_slice: "TBD"` or empty `owner`.
3. Any debt item whose `target_slice` has already passed (slice is complete) produces `OVERDUE_DEBT` -- this blocks `prd_set_pass.sh` for the current slice until the item is re-targeted or resolved.

---

## 8. Skill Receipt Schema

Location: `reviews/reconciliations/<slice>/receipts/r5b_<skill>.json`

### 8.1 Required Fields

```json
{
  "skill_name": "/pr-review",
  "story_id": "S1-007",
  "head_commit": "abc123f",
  "started_at": "2026-02-21T14:30:00Z",
  "ended_at": "2026-02-21T14:32:15Z",
  "exit_status": "completed",
  "artifact_paths": ["artifacts/story/S1-007/self_review/pr_review.md"],
  "finding_counts": { "P0": 0, "P1": 1, "P2": 3 }
}
```

**Recon-mode receipt extras** (present only in recon mode):

| Field | Values | When present |
|-------|--------|-------------|
| `recon_mode` | `true` | Always in recon |
| `recon_relaxation` | `implement_diff_check_skipped` | Implement step (no diff required) |
| `recon_relaxation` | `min_reviews_relaxed_to_1` | Cycle 2 step (GREEN path — no code changes) |

| Field | Type | Constraint |
|-------|------|------------|
| `skill_name` | string | One of: `/pr-review`, `/failure-mode-review`, `/strategic-failure-review`, `/contract-review`, `/devils-advocate` |
| `story_id` | string | Valid story ID |
| `head_commit` | string | Must match HEAD at time of execution |
| `started_at` | string | ISO 8601 timestamp |
| `ended_at` | string | ISO 8601 timestamp, after `started_at` |
| `exit_status` | string | `completed` / `skipped` / `failed` |
| `artifact_paths` | array of strings | Each path must reference an existing file on disk |
| `finding_counts` | object | Keys: `P0`, `P1`, `P2`; values: non-negative integers |

### 8.2 Receipt Filenames

| Skill | Filename |
|-------|----------|
| `/pr-review` | `r5b_pr_review.json` |
| `/failure-mode-review` | `r5b_failure_mode_review.json` |
| `/strategic-failure-review` | `r5b_strategic_review.json` |
| `/contract-review` | `r5b_contract_review.json` |
| `/validator-audit` | `r5b_validator_audit.json` |
| `/devils-advocate` | `r5b_devils_advocate.json` |

### 8.3 R6 Gate Check Rules

All 7 checks must pass (blocking with `SELF_REVIEW_UNPROVEN: <reason>` on failure):

1. All 6 receipt files exist.
2. Each `head_commit` matches current HEAD.
3. Each `started_at`/`ended_at` is plausible and within the R5b window.
4. Each `exit_status` is `"completed"`.
5. Each `artifact_paths[]` entry references a file that exists on disk.
6. `R5B_FIX_PLAN.md` exists.
7. `R5B_FIX_LOG.md` or `R5B_NO_FIXES_NEEDED.md` exists.

---

## 9. Per-AT Evidence Checklist

For every AT claimed by the story's premortem, the agent fills this evidence row:

| # | Check | Expected Verdicts | Evidence Required |
|---|-------|-------------------|-------------------|
| 1 | Enforcement point exists in code? | PROVEN / CLAIMED_NOT_PROVEN | file:line -- function/method name |
| 2 | Proving test exists? | PROVEN / CLAIMED_NOT_PROVEN | test file:line -- test function name |
| 3 | Test proves causality? | PROVEN / WEAK_PROOF / UNTESTED_ENFORCEMENT | mechanism: dispatch_count / reject_reason / latch_reason |
| 4 | TRIP test exists? (if safety-critical) | PROVEN / CLAIMED_NOT_PROVEN | test name + what it trips |
| 5 | NON-TRIP test exists? (if safety-critical) | PROVEN / CLAIMED_NOT_PROVEN | test name + what it doesn't trip |
| 6 | Golden vector table exists? | PROVEN / MISSING_GOLDEN_VECTOR | test name + row count |
| 7 | Premortem section 5 wrong impls blocked? | PROVEN / WRONG_IMPL_UNBLOCKED | which wrong impls have tightened tests, which don't |
| 8 | Fail-closed on error paths? | PROVEN / FAIL_OPEN | file:line -- what happens on NaN/None/error |
| 9 | No unwrap() in production path? | PROVEN / UNWRAP_IN_PROD | `rg "unwrap()"` result for enforcement file |
| 10 | Observability on reject path? | PROVEN / SILENT_REJECT | structured log / metric / reason code at file:line |

---

## 10. Per-Section Reconciliation Checks

| Premortem Section | What the agent checks | Evidence required |
|-------------------|----------------------|-------------------|
| Section 0: Touch scope | Do the files listed in touch scope actually exist and contain the relevant code? | List actual files touched with line ranges |
| Section 1: Clause audit | Does the implementation enforce the correct contract clauses? | AT -> enforcement point mapping with file:line |
| Section 2: Assumptions | Were assumptions validated or killed? Do the predicted tests exist? | For each assumption: test name or "not tested" |
| Section 3: Failure modes | Are the predicted failure modes mitigated in code? | For each mode: mitigation location or "unmitigated" |
| Section 4: Open decisions | Was the chosen option actually implemented (not an alternative)? | Code evidence matching the decision |
| Section 5: Wrong-impl gate | Are the wrong impls blocked by tightened tests? | Test name per wrong impl, or "no tightening test" |
| Section 6: Proof plan | Does the actual test suite match the planned tests? | Planned test name -> actual test name mapping |
| Section 7: Economic risk | Does the drift metric exist and increment correctly? | Metric name at file:line |
| Section 8: Conflict scan | Were predicted hot-zone conflicts resolved? | Merge status / file ownership |

---

## 11. Fail-Closed Check Categories

Six categories. Scope: each input, each intermediate type conversion, and each output of every enforcement function.

| # | Category | Check | Expected behavior |
|---|----------|-------|-------------------|
| 1 | **Missing/None** | Input is None, empty, or absent field | Reject or degrade |
| 2 | **NaN/Inf** | Numeric input is NaN or Inf | Reject or degrade |
| 3 | **Negative** | Value is negative where unsigned/positive is expected | Reject or degrade |
| 4 | **Out-of-domain** | `type::MAX`, percentage > 1.0, timestamp beyond sane range | Reject or degrade |
| 5 | **Corrupt/garbage** | Unreasonable future date, negative unsigned, garbage bytes | Reject or degrade |
| 6 | **Narrowing casts** | `(f64).round() as i64` silently saturates; `as u32` truncates | Source value must be bounded before cast |

**"Invalid" means all six categories -- not just NaN.**

Additional scope requirements:
- Intermediate computations that cross type boundaries (e.g., `(f64).round() as i64` saturates silently).
- Constants with wrong comments (e.g., `~7.3e15` comment on a `7.3e12` value).
- Input combinations where one input's presence causes checks on other inputs to be skipped.
- For functions with 2+ branching inputs: combinatorial coverage of cross-cutting combinations.

No warn-and-continue. No silent fallback.
