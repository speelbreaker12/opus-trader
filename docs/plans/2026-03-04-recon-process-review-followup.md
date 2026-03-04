# Recon Process Review Follow-Up Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Convert `reviews/reconciliations/RECON_PROCESS_REVIEW.md` into a verified, contract-safe improvement batch that closes remaining high-risk workflow gaps and reduces reconciliation operating cost.

**Architecture:** Keep the current single 9-step reconciliation pipeline (`preflight -> ... -> pass`) unchanged, then improve throughput by tightening automation and reducing redundant operator work inside the existing path. Work in small, test-first harness changes (scripts + tests + docs) so each change is self-proving and fail-closed. Use one reconciliation story at a time per worktree to respect WIP limits and keep feedback loops short.

**Tech Stack:** Bash harness (`plans/*.sh`), Python validators (`plans/validators/*.py`), jq, Markdown protocol docs, shell test suite (`plans/tests/*.sh`)

**Primary Inputs:**
- `reviews/reconciliations/RECON_PROCESS_REVIEW.md`
- `reviews/reconciliations/PROTOCOL.md`
- `reviews/reconciliations/REFERENCE.md`
- `plans/wf_step.sh`
- `plans/verify.sh`, `plans/verify_fork.sh`
- `plans/prd_set_pass.sh`

**Execution prerequisites (set once):**
```bash
STORY_ID=<PRD_STORY_ID>
BASELINE_SHA="$(git rev-parse origin/main)"
export CODEX_MODEL="GPT-5.3-Codex"
export GEMINI_MODEL="gemini-3-pro-preview"
```

**External reviewer model set (canonical):**
- `codex`: `CODEX_MODEL=GPT-5.3-Codex` (used by review provenance and codex-exec fallback path)
- `opus`: `claude-opus-4-6` (fixed in `review_logged.sh`)
- `kimi`: `k2.5` (fixed in `review_logged.sh`)
- `gemini`: `GEMINI_MODEL=gemini-3-pro-preview` (default in `review_logged.sh`)

**Verification policy (applies to every `./plans/verify.sh ...` call):**
1. If `git status --porcelain` is clean, run verify locally as written.
2. If the worktree is dirty, choose and log one path in `plans/progress.txt` before continuing:
   - [RECOMMENDED] rely on CI verify for PR (clean checkout),
   - clean the tree (stash/commit unrelated changes) and rerun verify,
   - owner-approved exception: `VERIFY_ALLOW_DIRTY=1` with explicit rationale + dirty file list.

**Significant commit checkpoint (required before each commit that stages `plans/*.sh`):**
```bash
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" \
  --tools codex,opus,kimi,gemini \
  --uncommitted \
  --prompt enriched
./plans/code_review_expert_attest.sh
```
Expected: review artifacts are written under `artifacts/story/<STORY_ID>/{codex,opus,kimi,gemini}/` and attestation matches staged tree.

---

### Task 1: Revalidate Review Baseline and Freeze Action Register

**Files:**
- Modify: `reviews/reconciliations/RECON_PROCESS_REVIEW.md`
- Create: `reviews/reconciliations/RECON_PROCESS_ACTION_REGISTER_2026-03-04.md`
- Modify: `plans/progress.txt`

**Step 1: Regenerate appendix and status tags**

Run:
```bash
BASELINE_SHA="$(git rev-parse origin/main)"
./plans/generate_recon_review_appendix.sh \
  --commit "$BASELINE_SHA" \
  --date 2026-03-04 \
  --update-doc reviews/reconciliations/RECON_PROCESS_REVIEW.md
```
Expected: Appendix A is refreshed with current claim statuses pinned to immutable `BASELINE_SHA` (not a moving ref).

**Step 2: Write an action register with explicit state**

Create `RECON_PROCESS_ACTION_REGISTER_2026-03-04.md` with one row per recommendation:
- `id`
- `source_claim_or_recommendation`
- `status` (`OPEN`, `ALREADY_DONE`, `DEFERRED`)
- `owner`
- `baseline_sha`
- `proof_command`
- `proof_artifact_path`

**Step 3: Record ToC constraint explicitly**

Append to `plans/progress.txt`:
- current constraint (verification feedback loop vs documentation overhead)
- selected exploitation strategy for this batch
- scope of this execution batch
- immutable baseline commit (`BASELINE_SHA`)

**Step 4: Validate docs + workflow consistency**

Run:
```bash
./plans/verify.sh quick
```
Expected: quick verify green before starting implementation tasks; if worktree is dirty, apply the Verification policy above and record the decision.

**Step 5: Commit baseline freeze**

```bash
git add reviews/reconciliations/RECON_PROCESS_REVIEW.md \
        reviews/reconciliations/RECON_PROCESS_ACTION_REGISTER_2026-03-04.md \
        plans/progress.txt
git commit -m "recon(process): freeze baseline and action register from process review"
```

---

### Task 2: Add `prd_set_pass.sh --dry-run` (No-Mutation Gate Preview)

**Files:**
- Modify: `plans/prd_set_pass.sh`
- Modify: `plans/tests/test_prd_set_pass.sh`
- Modify: `plans/prd_gate_help.md`
- Modify: `reviews/reconciliations/PROTOCOL.md`

**Step 1: Write failing tests for dry-run semantics**

Add tests that assert:
- `--dry-run` executes all pass checks
- output includes PASS/FAIL diagnostics
- PRD `passes` field is not mutated

Run:
```bash
plans/tests/test_prd_set_pass.sh
```
Expected: FAIL (new dry-run tests fail before implementation).

**Step 2: Implement CLI + guard logic**

Implement `--dry-run` in `plans/prd_set_pass.sh`:
- parse new flag
- run full validation path
- skip PRD write/mutation when dry-run is set
- return non-zero on failed gates, zero on passable state

**Step 3: Update operator docs**

Document canonical preview command in:
- `plans/prd_gate_help.md`
- `reviews/reconciliations/PROTOCOL.md`

**Step 4: Re-run targeted tests**

Run:
```bash
plans/tests/test_prd_set_pass.sh
./plans/verify.sh quick
```
Expected: tests and quick verify pass.

**Step 5: Commit**

```bash
# Required for significant staged `plans/*.sh` changes:
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/code_review_expert_attest.sh

git add plans/prd_set_pass.sh \
        plans/tests/test_prd_set_pass.sh \
        plans/prd_gate_help.md \
        reviews/reconciliations/PROTOCOL.md
git commit -m "workflow: add prd_set_pass dry-run gate preview"
```

---

### Task 2B: Clean Stale Premortem Path References In `plans/prd.json` + Add Guard

**Files:**
- Modify: `plans/prd.json`
- Modify: `plans/prd_lint.sh` (or create `plans/recon_doc_refs_guard.sh` and wire from lint/verify)
- Create/Modify: `plans/tests/test_prd_lint.sh` (or dedicated guard test)
- Modify: `reviews/reconciliations/PROTOCOL.md`

**Step 1: Add failing guard test for stale path tokens**

Add a failing test that asserts machine-consumed PRD string fields reject legacy doc-path tokens:
- `reviews/premortems/RUNBOOK_PREMORTEM_RECON.md`
- `reviews/premortems/PREMORTEM_RECON_POLICY.md`
- `reviews/premortems/PREMORTEM_RECON_ANTIPATTERNS.md`
- `reviews/premortems/PREMORTEM_RECON_METRICS.md`

Run:
```bash
bash plans/tests/test_prd_lint.sh
```
Expected: FAIL before guard implementation.

**Step 2: Bulk-update stale path references in `plans/prd.json`**

Scope only machine-consumed path fields (do not rewrite historical narrative text in progress/changelog fields).

Verify:
```bash
jq '.. | strings | select(test("RUNBOOK_PREMORTEM_RECON|PREMORTEM_RECON_POLICY|PREMORTEM_RECON_ANTIPATTERNS|PREMORTEM_RECON_METRICS"))' plans/prd.json
```
Expected: empty for machine-consumed path fields, with any intentional historical text explicitly documented.

**Step 3: Add fail-closed guard**

Implement deterministic lint/guard failure when stale premortem path tokens appear in PRD path-bearing fields.

**Step 4: Re-run tests and verify**

```bash
bash plans/tests/test_prd_lint.sh
./plans/verify.sh quick
```
Expected: pass.

**Step 5: Commit**

```bash
# Required for significant staged `plans/*.sh` changes:
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/code_review_expert_attest.sh

git add plans/prd.json \
        plans/prd_lint.sh \
        plans/tests/test_prd_lint.sh \
        reviews/reconciliations/PROTOCOL.md
git commit -m "recon: remove stale premortem path refs from prd and add lint guard"
```

---

### Task 3: Add Regression Gate for P0 Prompt/Workflow Invariants

**Files:**
- Create: `plans/recon_prompt_guard.sh`
- Modify: `plans/verify_fork.sh`
- Create: `plans/tests/test_recon_prompt_guard.sh`
- Modify: `plans/tests/test_verify_fork_guardrails.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Write failing guard test**

Create tests that fail when any of these regress:
- surrogate premortem path appears in R1 audit prompts
- read-only R1 prompt is mislabeled as implementation write step
- canonical references drift away from `PROTOCOL.md`/`REFERENCE.md`

Run:
```bash
plans/tests/test_recon_prompt_guard.sh
```
Expected: FAIL until guard script exists.

**Step 2: Implement `recon_prompt_guard.sh`**

Implement deterministic checks using `rg` and fixed patterns with fail-closed exits and clear diagnostics.

**Step 3: Wire guard into verify**

Add `recon_prompt_guard` gate to `plans/verify_fork.sh` quick/full path so workflow edits are self-proving.
Register the new workflow script/test in `plans/workflow_files_allowlist.txt` and
`plans/tests/test_workflow_allowlist_coverage.sh`.

**Step 4: Run tests and verify**

Run:
```bash
plans/tests/test_recon_prompt_guard.sh
plans/tests/test_verify_fork_guardrails.sh
plans/tests/test_workflow_allowlist_coverage.sh
./plans/workflow_verify.sh
```
Expected: all pass.

**Step 5: Commit**

```bash
# Required for significant staged `plans/*.sh` changes:
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/code_review_expert_attest.sh

git add plans/recon_prompt_guard.sh \
        plans/verify_fork.sh \
        plans/tests/test_recon_prompt_guard.sh \
        plans/tests/test_verify_fork_guardrails.sh \
        plans/workflow_files_allowlist.txt \
        plans/tests/test_workflow_allowlist_coverage.sh
git commit -m "workflow: enforce recon prompt invariants as verify gate"
```

---

### Task 4: Canonicalize Evidence Ledger to JSON-First (Artifact Reduction Phase 1)

**Files:**
- Modify: `plans/recon_evidence_ledger.sh`
- Modify: `plans/wf_step.sh`
- Modify: `plans/step_prompts/recon/cycle1.md`
- Modify: `plans/step_prompts/recon/fix.md`
- Modify: `plans/step_prompts/recon/resolution.md`
- Modify: `plans/tests/test_recon_evidence_ledger.sh`
- Modify: `plans/tests/test_wf_step_path_signal_scan.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Add failing tests for JSON-first pathing**

Add tests that require:
- canonical path: `artifacts/story/<ID>/evidence_ledger.json`
- fail-closed when ledger is scaffold placeholder
- deterministic fallback diagnostics for legacy `.md` ledgers

Run:
```bash
plans/tests/test_recon_evidence_ledger.sh
plans/tests/test_wf_step_path_signal_scan.sh
```
Expected: FAIL before implementation.

**Step 2: Implement JSON-first lookup + compatibility**

Update helper + `wf_step.sh` to:
- prefer JSON ledger
- preserve backward-compatible read of legacy markdown paths
- keep hard-block behavior on missing/placeholder evidence
- update workflow allowlist + coverage test when introducing/tightening workflow-governed files
- enforce evidence completeness: every AT in `enforcing_contract_ats[]` has a ledger verdict
- require non-empty verdict fields, and require evidence citation (`file:line`) for `PROVEN` rows
- fail closed when AT coverage is partial or missing

**Step 3: Align step prompts to canonical ledger path**

Update `cycle1.md`, `fix.md`, `resolution.md` to use JSON-first instructions.

**Step 4: Re-run targeted tests + quick verify**

Run:
```bash
plans/tests/test_recon_evidence_ledger.sh
plans/tests/test_wf_step_path_signal_scan.sh
plans/tests/test_wf_step.sh
plans/tests/test_workflow_allowlist_coverage.sh
./plans/workflow_verify.sh
```
Expected: pass.

**Step 5: Commit**

```bash
# Required for significant staged `plans/*.sh` changes:
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/code_review_expert_attest.sh

git add plans/recon_evidence_ledger.sh \
        plans/wf_step.sh \
        plans/step_prompts/recon/cycle1.md \
        plans/step_prompts/recon/fix.md \
        plans/step_prompts/recon/resolution.md \
        plans/tests/test_recon_evidence_ledger.sh \
        plans/tests/test_wf_step_path_signal_scan.sh \
        plans/workflow_files_allowlist.txt \
        plans/tests/test_workflow_allowlist_coverage.sh
git commit -m "recon: move evidence ledger checks to json-first canonical path"
```

---

### Task 5: Add Process-Docs Budget Gate (Prevent Re-accumulation)

**Files:**
- Create: `plans/recon_doc_budget.sh`
- Modify: `plans/verify_fork.sh`
- Create: `plans/tests/test_recon_doc_budget.sh`
- Modify: `plans/tests/test_verify_fork_guardrails.sh`
- Modify: `reviews/reconciliations/PROTOCOL.md`
- Modify: `WORKFLOW_FRICTION.md`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Write failing budget gate test**

Create test fixtures for pass/fail budgets (line counts + required sources).

Run:
```bash
plans/tests/test_recon_doc_budget.sh
```
Expected: FAIL before script exists.

**Step 2: Implement `recon_doc_budget.sh`**

Implement deterministic checks:
- required docs exist
- total line-count threshold via `RECON_DOC_BUDGET_MAX_LINES` (default `650`)
- fail-closed with explicit per-file counts
- fail-closed on invalid threshold values (empty/non-integer/negative)
- override governance:
  - default CI behavior ignores override attempts (budget is hard-enforced)
  - local override requires explicit owner approval recorded in `plans/progress.txt`
  - override run must log who approved, rationale, and expiry/removal date

**Step 3: Wire gate into verify**

Run the budget gate in `verify_fork.sh` so workflow-doc changes are always validated.
Register the new workflow script/test in `plans/workflow_files_allowlist.txt` and
`plans/tests/test_workflow_allowlist_coverage.sh`.
Extend `plans/tests/test_verify_fork_guardrails.sh` with deterministic assertions for
`recon_doc_budget` gate invocation/order.

**Step 4: Document policy and elevation path**

Update:
- `reviews/reconciliations/PROTOCOL.md` (budget policy)
- `WORKFLOW_FRICTION.md` (what to do when budget is exceeded)

**Step 5: Re-run tests + quick verify and commit**

Run:
```bash
plans/tests/test_recon_doc_budget.sh
plans/tests/test_verify_fork_guardrails.sh
plans/tests/test_workflow_allowlist_coverage.sh
./plans/workflow_verify.sh
```
Then:
```bash
# Required for significant staged `plans/*.sh` changes:
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/code_review_expert_attest.sh

git add plans/recon_doc_budget.sh \
        plans/verify_fork.sh \
        plans/tests/test_recon_doc_budget.sh \
        plans/tests/test_verify_fork_guardrails.sh \
        reviews/reconciliations/PROTOCOL.md \
        WORKFLOW_FRICTION.md \
        plans/workflow_files_allowlist.txt \
        plans/tests/test_workflow_allowlist_coverage.sh
git commit -m "workflow: add recon documentation budget gate"
```

---

### Task 6: Mandatory `code-review-expert` Gate + Final Verification

**Files:**
- Modify: `plans/progress.txt`
- Modify: `reviews/reconciliations/RECON_PROCESS_ACTION_REGISTER_2026-03-04.md`

**Step 1: Run final review loop checkpoints (before full verify)**

```bash
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt enriched
./plans/verify.sh quick
CODEX_MODEL="$CODEX_MODEL" GEMINI_MODEL="$GEMINI_MODEL" plans/parallel_review.sh "$STORY_ID" --tools codex,opus,kimi,gemini --uncommitted --prompt generic
./plans/code_review_expert_attest.sh
./plans/verify.sh quick
```
Expected: review artifacts exist under `artifacts/story/<STORY_ID>/{codex,opus,kimi,gemini}/` for current HEAD and attestation matches staged tree. Pass gating still requires codex/opus evidence.

**Step 2: Prepare final verify run ID and close action register fields**

Set a deterministic final run ID once and use it in proof paths:
```bash
FINAL_VERIFY_RUN_ID="recon_followup_$(date -u +%Y%m%dT%H%M%SZ)"
```
Then close each action-register row with:
- final status
- `baseline_sha`
- `proof_command`
- `proof_artifact_path` (use `artifacts/verify/${FINAL_VERIFY_RUN_ID}/...`)

**Step 3: Commit closure metadata before final full verify**

```bash
git add plans/progress.txt reviews/reconciliations/RECON_PROCESS_ACTION_REGISTER_2026-03-04.md
git commit -m "recon(process): close follow-up batch metadata before final verify"
```

**Step 4: Run workflow contract gate when needed**

If `specs/WORKFLOW_CONTRACT.md` or `plans/workflow_contract_map.json` changed:
```bash
./plans/workflow_contract_gate.sh
```

**Step 5: Run full verification on the closure commit**

```bash
VERIFY_RUN_ID="$FINAL_VERIFY_RUN_ID" ./plans/verify.sh full
```
Expected: all gates green with artifacts bound to the current HEAD (same commit as closure metadata).

**Step 6: Run final-head pre-PR review wrappers (required before PR merge path)**

```bash
./plans/pre_pr_review_gate.sh "$STORY_ID"
./plans/pr_gate.sh --wait --story "$STORY_ID"
```
Expected: final-head review wrapper evidence exists before merge/promotion.

**Step 7: Demonstrate pass-gate preview (dry-run only by default)**

```bash
VERIFY_ARTIFACTS_DIR="artifacts/verify/$FINAL_VERIFY_RUN_ID" \
  ./plans/prd_set_pass.sh "$STORY_ID" true --dry-run
```
Expected: dry-run reports exact gate outcome with zero PRD mutation.

Optional disposable mutation-path demo (never mutate canonical PRD):
```bash
tmp_prd="$(mktemp)"
cp plans/prd.json "$tmp_prd"
PRD_FILE="$tmp_prd" ./plans/prd_set_pass.sh "$STORY_ID" false
rm -f "$tmp_prd"
```

---

### Task 7: Active Workflow-File Stale Reference Sweep

**Files:**
- Modify: active workflow `.sh/.md/.py` files flagged by sweep (excluding archived files and progress logs)
- Modify: `reviews/reconciliations/PROTOCOL.md` (if canonical reference section needs sync)

**Step 1: Run stale-reference scan for active workflow files**

```bash
grep -rn "RUNBOOK_PREMORTEM_RECON\|PREMORTEM_RECON_POLICY\|PREMORTEM_RECON_ANTIPATTERNS\|PREMORTEM_RECON_METRICS\|PREMORTEM_RECONCILIATION_PROCESS" \
  --include="*.md" --include="*.sh" --include="*.py" \
  | grep -v ".archived" | grep -v "plans/progress.txt"
```

**Step 2: Fix actionable hits**

Update active workflow documents/scripts to canonical `reviews/reconciliations/PROTOCOL.md` and `reviews/reconciliations/REFERENCE.md` paths where appropriate.

**Step 3: Verify sweep is clean**

Re-run the sweep command above.
Expected: zero actionable hits in active workflow files.

**Step 4: Commit**

```bash
git add <updated workflow files>
git commit -m "recon: sweep stale premortem doc references in active workflow files"
```

---

## Execution Order and WIP Policy

1. Task 1 (baseline freeze)
2. Task 2 (pass gate dry-run)
3. Task 3 (prompt regression gate)
4. Task 4 (ledger canonicalization)
5. Task 5 (doc budget gate)
6. Task 6 (closure metadata + final verify + pre-PR wrappers)
7. Task 7 (stale-reference sweep for active workflow files)

WIP constraints:
- one story/worktree active at a time for workflow edits
- never run concurrent `./plans/verify.sh full` in the same worktree
- do not flip `passes=true` until Task 6 evidence is complete

## Success Metrics

- `./plans/verify.sh full` passes on HEAD.
- `plans/prd_set_pass.sh --dry-run` exists and is tested.
- `code-review-expert` checkpoint + `./plans/code_review_expert_attest.sh` run before final verify/merge.
- `./plans/pre_pr_review_gate.sh <STORY_ID>` and `./plans/pr_gate.sh --wait --story <STORY_ID>` run on final HEAD before merge path.
- Prompt regression guard exists and is part of verify.
- Evidence ledger gating is JSON-first with backward compatibility.
- Reconciliation docs budget has an enforceable verify gate.
- Stale premortem doc references in `plans/prd.json` are cleaned and guarded by fail-closed lint/check.
- Evidence ledger check validates AT completeness (not just presence).
- New workflow gate scripts/tests are registered in `plans/workflow_files_allowlist.txt`, and `plans/tests/test_workflow_allowlist_coverage.sh` is executed in task verification steps.
- Active workflow-file stale-reference sweep reports zero actionable hits.
- Action register rows include `baseline_sha`, `proof_command`, and `proof_artifact_path`.
