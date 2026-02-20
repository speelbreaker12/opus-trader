# WORKFLOW_CONTRACT (Fork)

This fork intentionally removes the **Ralph loop** and **workflow acceptance**. The workflow is **manual PRD execution** with **contract-first enforcement** and **verify as the only gate**.

If you want the legacy Ralph contract, keep it archived as `specs/WORKFLOW_CONTRACT_RALPH.md`.

---

## 1. Source of truth (priority order)

1) `specs/CONTRACT.md` (behavioral contract)  
2) `specs/IMPLEMENTATION_PLAN.md` (how the contract is realized)  
3) `plans/prd.json` (stories + acceptance criteria)  
4) Code (implementation)

If code conflicts with the contract, the code is wrong.

---

## 2. Non-negotiable invariants

- **Contract-first**: every story must satisfy CONTRACT + PRD acceptance criteria.
- **Isolation**: never modify a worktree that is running `verify full`.
- **One full verify at a time per machine** (human enforced; optional lock file allowed).
- **WIP limit = 2**:
  - 1 story in `VERIFYING` (full verify running)
  - 1 story in `IMPLEMENTING/REVIEW`
- **No “complete” without green `verify full`** for that story branch/worktree.
- **Traceability**: every change maps to exactly one Story ID (branch name + commit message).

---

## 3. Required workflow files

These files must exist in the fork and remain functional:

- `plans/prd.json`
- `plans/prd_schema_check.sh`
- `plans/verify.sh` (stable entrypoint; referenced by PRD `verify[]`)
- `plans/verify_fork.sh` (canonical verify implementation)
- `plans/lib/verify_utils.sh` (artifacts + logging convention)
- `plans/self_review_logged.sh` (self-review artifact logger)
- `plans/story_review_gate.sh` (HEAD-tied review evidence gate)
- `plans/codex_review_logged.sh` (Codex review artifact logger)
- `plans/kimi_review_logged.sh` (Kimi review artifact logger)
- `plans/code_review_expert_logged.sh` (findings review artifact logger)
- `plans/wf_step.sh` (Receipt-chain workflow step executor — enforces step ordering, HMAC signing)
- `plans/wf_ci_guard.sh` (CI guard — blocks passes=true flips without valid receipt chains)
- `plans/opus_review_logged.sh` (Opus review artifact logger — fallback when Codex unavailable)
- `plans/supervisor_check.sh` (Sonnet-based supervisor agent — verifies builder work at 3 checkpoints)
- `plans/thinking_review_logged.sh` (slice-close thinking review artifact logger)
- `plans/slice_completion_enforce.sh` (verify-full slice-close enforcement bridge)
- `plans/slice_review_gate.sh` (slice-close thinking review evidence gate)
- Contract/spec validators (kept as-is unless explicitly changed):
  - `scripts/check_contract_crossrefs.py`
  - `scripts/check_arch_flows.py`
  - `scripts/check_state_machines.py`
  - `scripts/check_global_invariants.py`
  - `scripts/check_time_freshness.py`
  - `scripts/check_crash_matrix.py`
  - `scripts/check_crash_replay_idempotency.py`
  - `scripts/check_reconciliation_matrix.py`
  - `scripts/check_csp_trace.py`
- Status validation:
  - `tools/validate_status.py`
  - `python/schemas/status_*.schema.json`
  - `tests/fixtures/status/**` (if present, must validate)

Optional but recommended:
- `plans/preflight.sh` (cheap early failure detector)
- `plans/story_postmortem_logged.sh` (story-level postmortem artifact logger)
- `plans/codex_review_digest.sh` (concise Codex digest artifact generator)
- `reviews/REVIEW_CHECKLIST.md`
- `SKILLS/failure-mode-review.md`, `SKILLS/strategic-failure-review.md`

---

## 4. Work model (branches + worktrees)

### 4.1 Naming
- Branch: `slice1/<STORY_ID>-<slug>`
- Worktree dir: `../wt_<STORY_ID>`

### 4.2 Setup (per story)
From a clean integration branch (example: `run/slice1-clean`):
1) Create story branch from integration branch.
2) Create worktree for the story branch.
3) Work only inside that worktree for that story.

### 4.3 Two worktrees in flight (WIP=2)
At any moment:
- WT-A runs `verify full` → **frozen** until it finishes.
- WT-B is the only place you edit code.

---

## 5. Story lifecycle (simple state machine)

States are tracked by convention (notes, progress.txt, or dashboard output). PRD `passes` is the only “official” flag.

- `PENDING` → worktree exists, story started  
- `IMPLEMENTING` → coding  
- `REVIEW` → self-review + Kimi/Codex reviews  
- `VERIFYING` → `verify full` running (worktree frozen)  
- `FIX_VERIFY` → verify failed; stop-ship; fix in same worktree  
- `COMPLETE` → verify full green + PRD passes flipped + merged to integration

---

## 6. Story loop (minimal, mandatory)

This is the only approved execution loop.

1) Implement in story worktree (single Story ID).
2) Capture `REVIEW_SHA="$(git rev-parse HEAD)"` and write self-review for that SHA using:
   - `SKILLS/failure-mode-review.md`
   - `SKILLS/strategic-failure-review.md`
3) Run `./plans/verify.sh quick`.
4) Codex review for `REVIEW_SHA` (`codex review --commit "$REVIEW_SHA" ...`), fix all blocking.
4.1) **Supervisor checkpoint**: `plans/supervisor_check.sh <STORY_ID> post-cycle1` — Sonnet verifies cycle 1 findings are real and match actual code. If FAIL → redo cycle 1 review.
5) Kimi K2.5 review for `REVIEW_SHA` (`kimi ...` via `plans/kimi_review_logged.sh --commit "$REVIEW_SHA"`), fix all blocking.
6) Fix all cycle 1 findings (P0/P1/P2). Run `./plans/verify.sh quick` again (after review fixes).
6.0) **Supervisor checkpoint**: `plans/supervisor_check.sh <STORY_ID> post-fix` — Sonnet verifies the fix diff actually addresses cycle 1 findings. If FAIL → builder must re-fix.
6.1) Second Codex review for `REVIEW_SHA` (`codex review --commit "$REVIEW_SHA" ...`), fix all blocking.
6.2) Run `./plans/verify.sh quick` again (after second Codex fixes).
6.3) Run findings review using `~/.agents/skills/code-review-expert/SKILL.md` for `REVIEW_SHA`.
   - Save artifact using `plans/code_review_expert_logged.sh <STORY_ID> --head "$REVIEW_SHA" --status COMPLETE`.
   - Artifact path: `artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md`.
6.4) Turn top findings into failing tests first (red phase).
6.5) Fix until those tests pass (green phase).
6.6) Run `./plans/verify.sh quick` again after fixes.
6.7) **Supervisor checkpoint**: `plans/supervisor_check.sh <STORY_ID> post-cycle2` — Sonnet verifies cycle 2 is a legitimate re-review and findings are genuinely resolved. If FAIL → builder must redo cycle 2.
  - Sequence-bound equivalent is `plans/workflow_quick_step.sh <STORY_ID> <checkpoint>`; it must execute `./plans/verify.sh quick`.
7) Sync with integration branch (merge/rebase `run/slice1-clean` into story branch).
   - If this changed anything, run `./plans/verify.sh quick` again.
8) Freeze the story worktree and run `./plans/verify.sh full` (nohup allowed).
9) If full is green, set `passes=true` using `plans/prd_set_pass.sh` (must validate artifacts).
10) Merge story branch into integration branch.

Notes:
- WIP=2: while step (8) is running for Story A, you may execute steps (1-7) for Story B in a different worktree.
- Never edit a worktree while it is running `full`.
- Story review evidence MUST be SHA-consistent: self review, Kimi review, both Codex reviews, code-review-expert review, resolution file, and `story_review_gate` must all target the same `REVIEW_SHA`.
- If `HEAD` changes after review starts, discard partial review artifacts for the old/new mix and regenerate the full review set for the chosen SHA.
- **Supervisor enforcement**: The 3 supervisor checkpoints (steps 4.1, 6.0, 6.7) use an independent Sonnet agent to verify the builder's work semantically. Supervisor artifacts are required by `story_review_gate.sh` at pass-flip time. Set `REQUIRE_SUPERVISOR=0` to disable (not recommended for production).

### Recommended (non-blocking)
- Keep a single commit per story (use `--amend` until full is green) to keep review/merge simple.
- Write a 60-second "Story Brief" (contract refs + acceptance criteria summary) before coding.

---

## 6.1 Receipt chain (progressive chokepoints)

The receipt chain prevents out-of-order execution and provides tamper-evident step tracking.

### 6.1.1 Receipt system

Each workflow step produces a JSON receipt in `.wf/receipts/<STORY_ID>/`:

```
00_preflight.json
01_implement.json
02_self_review.json
03_cycle1.json
04_fix.json
05_cycle2.json
06_resolution.json
07_verify_full.json
```

Each receipt contains:
- `story_id`, `step_name`, `step_index`
- `head_sha` — git HEAD at time of receipt
- `timestamp_utc`
- `inputs_hash` — SHA256 of step-specific evidence files
- `prev_receipt_hash` — SHA256 of the previous receipt (or `GENESIS` for the first)
- `receipt_hash` — SHA256 of the receipt content itself
- `tainted` — true if `--force` was used (skipped prerequisites)

### 6.1.2 Ordering enforcement

Each step validates:
1. All previous receipts exist (progressive chokepoint)
2. The hash chain is valid (`prev_receipt_hash` matches actual hash of previous receipt)
3. Step-specific inputs are ready (e.g., review artifacts exist, resolution has required fields)

If any check fails, the step is **blocked immediately** — not deferred to pass-flip time.

### 6.1.3 Step input validation

| Step | Validates |
|------|-----------|
| `preflight` | First step, records HEAD as BASE_HEAD for all subsequent diffs |
| `implement` | Code changed since preflight BASE_HEAD (full story diff, not single commit) |
| `self_review` | Self-review artifacts exist in `artifacts/story/<ID>/self_review/` |
| `cycle1` | At least 1 review artifact in `codex/` or `opus/`; hashes ALL artifacts (sorted) |
| `fix` | Non-artifact code changed since cycle1 receipt (or cycle1 had 0 findings) |
| `cycle2` | At least 2 review artifacts (cycle 1 + cycle 2); hashes ALL artifacts (sorted) |
| `resolution` | `review_resolution.md` exists with `Blocking addressed: YES` and `BLOCKING=0` |
| `verify_full` | `verify.meta.json` exists with `mode=full` and matching HEAD |
| `pass` | Full chain valid; tainted receipts → **hard fail (exit 4)** |

**BASE_HEAD principle**: The `preflight` step records HEAD as the baseline. All subsequent diffs use `BASE_HEAD..HEAD` (the full story change), never `HEAD~1..HEAD` (single commit). This prevents hiding changes behind cosmetic follow-up commits.

**Fix step safeguards**:
- Must change at least one non-artifact file (excludes `artifacts/`, `.wf/`, `plans/prd.json`, `plans/progress*`)
- Exception: if cycle1 review had 0 findings, fix step passes with an empty diff (no deadlock on perfect reviews)

**Review artifact hashing**: `cycle1` and `cycle2` hash ALL matching review artifacts (sorted), not just the first/last. This prevents swapping reviews.

### 6.1.4 Usage

```bash
# Execute a step (validates prerequisites, writes receipt)
plans/wf_step.sh <STORY_ID> <step>

# Check chain status
plans/wf_step.sh <STORY_ID> --status

# Reset chain (start over — requires confirmation)
plans/wf_step.sh <STORY_ID> --reset --yes

# Dry run (validate without writing)
plans/wf_step.sh <STORY_ID> <step> --dry-run

# Force (skip prereqs, taints receipt — recovery only)
plans/wf_step.sh <STORY_ID> <step> --force

# Sign receipts with HMAC (set key in CI only)
WF_HMAC_KEY="<secret>" plans/wf_step.sh <STORY_ID> <step>

# Verify HMAC signatures on all receipts
WF_HMAC_KEY="<secret>" plans/wf_step.sh <STORY_ID> --verify-sigs
```

### 6.1.5 Tamper detection and safety

- Modifying any receipt breaks the hash chain — all subsequent steps are blocked
- Tainted receipts (from `--force`) cause the `pass` step to **hard fail (exit 4)** — not just warn
- `prd_set_pass.sh` independently rejects tainted receipts (defense in depth)
- The chain must be rebuilt from the tampered/tainted point onward
- `--reset` requires `--yes` confirmation (prevents accidental chain deletion)

### 6.1.6 HMAC signing (optional, recommended for CI)

If `WF_HMAC_KEY` is set, each receipt includes an HMAC-SHA256 signature computed over the canonical (sorted, unsigned) receipt JSON. This prevents agents from forging receipts — only processes with the key can produce valid signatures.

- Set `WF_HMAC_KEY` in CI environment only (not in agent environment)
- `prd_set_pass.sh` validates signatures when `WF_HMAC_KEY` is set
- `--verify-sigs` mode checks all receipts in a story's chain
- Unsigned receipts are flagged but not rejected (allows gradual adoption)

### 6.1.7 CI guard

`plans/wf_ci_guard.sh` detects `passes=true` flips in `prd.json` diffs and validates receipt chains. This catches direct PRD edits that bypass `prd_set_pass.sh`.

```bash
# Basic CI guard
plans/wf_ci_guard.sh

# With HMAC signature verification
WF_HMAC_KEY="$SECRET" plans/wf_ci_guard.sh --require-sigs
```

Environment:
- `WF_BASE_REF` — base ref to diff against (default: `origin/main`)
- `WF_HMAC_KEY` — required with `--require-sigs`

### 6.1.8 Integration with prd_set_pass.sh

`prd_set_pass.sh` requires the full receipt chain before allowing `passes=true`:
- All steps must have receipts (preflight through verify_full)
- Hash chain must be intact
- No tainted receipts
- verify_full receipt HEAD must match current HEAD
- HMAC signatures validated when `WF_HMAC_KEY` is set

Controlled by `REQUIRE_RECEIPT_CHAIN` env var (default=1, set to 0 to skip).

### 6.1.9 Anti-fabrication hardening (story_review_gate.sh)

`story_review_gate.sh` enforces review quality beyond structural checks:

- **Duration Seconds**: Required field in review artifacts. Missing this field is a **hard fail** (not skippable). Prevents 1-second fabricated reviews.
- **Diff cross-reference**: Review transcripts must mention at least one file from the BASE_HEAD..HEAD diff (full story diff, using preflight receipt if available). Prevents rubber-stamp reviews that don't engage with actual code changes.
- **Disposition whitespace tolerance**: Finding disposition rows (`| F-N | PN |`) use a whitespace-tolerant regex to handle LLM formatting inconsistencies.
- **Transcript quality**: Minimum byte threshold, file path references, severity markers all enforced with `die()` (not `warn()`).

---

## 7. Verify contract (the only gate)

### 7.1 Entrypoints
- Stable entrypoint (must exist): `./plans/verify.sh [quick|full]`
- Canonical implementation: `./plans/verify_fork.sh [quick|full]`

`plans/verify.sh` MUST be a thin wrapper that execs `verify_fork.sh` so PRD does not need rewriting.

### 7.2 Verify is read-only w.r.t. PRD
Verify MUST NOT modify `plans/prd.json` or any story state.

### 7.3 Verify artifacts (required)
Every gate produces artifacts in `artifacts/verify/<run_id>/`:

- `<gate>.log`
- `<gate>.rc`
- `<gate>.time`
- `FAILED_GATE` (written for first failing gate)

This is required so a detached run (nohup) can be debugged without reruns.

### 7.4 Gate sets

#### QUICK (developer iteration)
Goal: fast, repeatable, contract-first.

QUICK must run:
1) `preflight` (if present; no postmortem enforcement)
2) Contract/spec validators (the “spec_validators_group”):
   - contract_profiles
   - at_profile_parity
   - at_coverage_report
   - crossref_invariants
   - contract_crossrefs
   - arch_flows
   - state_machines
   - global_invariants
   - time_freshness
   - crash_matrix
   - crash_replay_idempotency
   - reconciliation_matrix
   - csp_trace
3) Status fixtures validation (if `tests/fixtures/status/**` exists): `status_fixture_*`
4) Doc sync validation: `doc_sync_check`
5) Stack tests (language-gated by repo contents):
   - Rust: `rust_fmt`, `rust_tests_quick`
   - Python: `python_ruff_check`, `python_pytest_quick`
   - Node: `node_lint`, `node_typecheck`, `node_test`

Notes:
- QUICK may warn on optional heuristics (e.g., endpoint gate), but must not block unless explicitly enabled.

#### FULL (story completion)
Goal: “mergeable green” for marking PRD pass.

FULL must run:
- Everything in QUICK, plus:
  - `crossref_gate` (marker-based evidence gate in CI mode; strictness controlled by sentinel/env)
  - `contract_coverage`
  - Rust: `rust_clippy`, `rust_tests_full`
  - Python: `python_mypy`, `python_pytest_full`, optional `python_ruff_format`
  - Node: (same as quick unless you have a distinct full)
  - `vendor_docs_lint_rust` (if supported)

FULL is the only gate allowed to justify `passes=true`.

### 7.5 Local full is allowed
In this fork, `verify full` MUST be runnable locally without special allow flags.

---

## 8. PRD pass protocol (simple + enforceable)

### 8.1 Rule
A story’s `passes` may be set to `true` only when:
- `./plans/verify.sh full` exited 0 **in that story worktree**, AND
- `verify.meta.json.head_sha` equals the current story branch `HEAD` at pass-flip time, AND
- verify artifacts show no failing gate (`FAILED_GATE` absent and all `*.rc` are 0), AND
- review evidence exists for the same `HEAD`:
  - self review is present and marked `Decision: PASS` with failure-mode + strategic reviews marked `DONE`,
  - Kimi review artifact exists for the same `HEAD`, includes required metadata (`Artifact Provenance`, `Generator Script`, `Command Exit Code: 0`), and has a valid transcript SHA256 over content between `<<<REVIEW_TRANSCRIPT_BEGIN>>>` and `<<<REVIEW_TRANSCRIPT_END>>>`,
  - at least two Codex review artifacts exist for the same `HEAD`; each includes required metadata (`Artifact Provenance`, `Generator Script`, `Command Exit Code: 0`) and has a valid transcript SHA256 over content between `<<<REVIEW_TRANSCRIPT_BEGIN>>>` and `<<<REVIEW_TRANSCRIPT_END>>>`,
  - code-review-expert review artifact exists for the same `HEAD`, is marked `Review Status: COMPLETE`, includes required metadata (`Artifact Provenance`, `Generator Script`, `Content Source`), and has a valid findings SHA256 over content between `<<<FINDINGS_BEGIN>>>` and `<<<FINDINGS_END>>>`,
  - review resolution file asserts `Blocking addressed: YES` and `Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0`, and references Kimi final review + Codex final review + Codex second review + code-review-expert final review files for the same `HEAD`,
  - supervisor evidence: all three supervisor checkpoints (`post-cycle1`, `post-fix`, `post-cycle2`) have PASS verdicts for the same `HEAD`, with artifacts in `artifacts/story/<STORY_ID>/supervisor/` (controlled by `REQUIRE_SUPERVISOR` env var, default=1),
  - receipt chain: all workflow steps (preflight through verify_full) have valid receipts in `.wf/receipts/<STORY_ID>/`, hash chain is intact, no tainted receipts (controlled by `REQUIRE_RECEIPT_CHAIN` env var, default=1).

### 8.2 Mechanism (required)
Create and use a single script to change PRD passes:

- `plans/prd_set_pass.sh <STORY_ID> true|false --artifacts-dir <dir>`

This script must refuse `true` unless the rule in 8.1 is proven via artifacts.
`plans/prd_set_pass.sh` MUST run `plans/story_review_gate.sh` for the current `HEAD`.

Manual PRD edits to flip `passes=true` are forbidden.

---

## 9. Integration rule

### 9.1 Merge discipline
After a story is FULL-green and PRD pass is set:
- Merge the story branch into the integration branch (e.g., `run/slice1-clean`).

### 9.2 Slice completion
After all Slice 1 stories are merged:
- Run `./plans/verify.sh full` on the integration branch.
- Run a slice-close review using `~/.agents/skills/thinking-review-expert/SKILL.md`.
- Save/update the review artifact using `plans/thinking_review_logged.sh <slice_id> --head <integration_head_sha>`.
- Artifact path is fixed: `artifacts/slice_reviews/<slice_id>/thinking_review.md` (include integration `HEAD` + final disposition).
- Start from template: `artifacts/slice_reviews/_template/thinking_review.md`.
- Hard gate the artifact with `plans/slice_review_gate.sh <slice_id> --head <integration_head_sha>`.
- `./plans/verify.sh full` on `run/sliceN-clean` enforces this gate once all PRD stories in that slice are `passes=true` (via `plans/slice_completion_enforce.sh`).
- Only then is the slice considered done.

### 9.3 Fork remediation metadata (merge-path evidence)
- Fork PR remediation metadata is tracked at `plans/review_attestations/fork_remediation/pr_<PR_NUMBER>.json`.
- Metadata must be written by maintainer remediation flow (`plans/fork_attestation_mirror.sh`) and validated with `plans/fork_attestation_remediation_verify.sh`.
- Missing/invalid metadata is fail-closed for fork remediation readiness.

---

## 10. Harness change control (minimal)

Changes to any of these are “harness changes”:
- `plans/**`
- `scripts/check_*.py`
- `tools/validate_status.py`
- `python/schemas/**`

Harness changes require:
- `./plans/verify.sh full` green on a clean worktree before merge.
- `./plans/story_review_equivalence_check.sh` must pass; drift is fail-closed (`STORY_REVIEW_EQUIVALENCE_DRIFT`).
- deterministic toggle-policy validation via `./plans/toggle_policy_check.sh` (invalid values fail closed).

No other process requirements are imposed.

---

## 11. What is explicitly out of scope in this fork

- Ralph loop, `.ralph/**` artifacts
- workflow acceptance (and any CI-forced workflow acceptance routing)
- postmortem gate
- “CI mirrors local behavior” heuristics beyond running `./plans/verify.sh full`

This fork optimizes for: **clarity → throughput → correctness**.
