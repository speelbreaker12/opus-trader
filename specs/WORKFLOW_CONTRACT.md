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
- `REVIEW` → self-review + Codex review  
- `VERIFYING` → `verify full` running (worktree frozen)  
- `FIX_VERIFY` → verify failed; stop-ship; fix in same worktree  
- `COMPLETE` → verify full green + PRD passes flipped + merged to integration

---

## 6. Story loop (minimal, mandatory)

This is the only approved execution loop.

1) Implement in story worktree (single Story ID).
2) Self-review (failure-mode + strategic).
3) Run `./plans/verify.sh quick`.
4) Codex review (`codex review --commit HEAD ...`), fix all blocking.
5) Run `./plans/verify.sh quick` again (after Codex fixes).
6) Sync with integration branch (merge/rebase `run/slice1-clean` into story branch).
   - If this changed anything, run `./plans/verify.sh quick` again.
7) Freeze the story worktree and run `./plans/verify.sh full` (nohup allowed).
8) If full is green, set `passes=true` using `plans/prd_set_pass.sh` (must validate artifacts).
9) Merge story branch into integration branch.

Notes:
- WIP=2: while step (7) is running for Story A, you may execute steps (1-6) for Story B in a different worktree.
- Never edit a worktree while it is running `full`.

### Recommended (non-blocking)
- Keep a single commit per story (use `--amend` until full is green) to keep review/merge simple.
- Write a 60-second "Story Brief" (contract refs + acceptance criteria summary) before coding.

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
4) Stack tests (language-gated by repo contents):
   - Rust: `rust_fmt`, `rust_tests_quick`
   - Python: `python_ruff_check`, `python_pytest_quick`
   - Node: `node_lint`, `node_typecheck`, `node_test`

Notes:
- QUICK may warn on optional heuristics (e.g., endpoint gate), but must not block unless explicitly enabled.

#### FULL (story completion)
Goal: “mergeable green” for marking PRD pass.

FULL must run:
- Everything in QUICK, plus:
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
- verify artifacts show no failing gate (`FAILED_GATE` absent and all `*.rc` are 0).

### 8.2 Mechanism (required)
Create and use a single script to change PRD passes:

- `plans/prd_set_pass.sh <STORY_ID> true|false --artifacts <dir>`

This script must refuse `true` unless the rule in 8.1 is proven via artifacts.

Manual PRD edits to flip `passes=true` are forbidden.

---

## 9. Integration rule

### 9.1 Merge discipline
After a story is FULL-green and PRD pass is set:
- Merge the story branch into the integration branch (e.g., `run/slice1-clean`).

### 9.2 Slice completion
After all Slice 1 stories are merged:
- Run `./plans/verify.sh full` on the integration branch.
- Only then is the slice considered done.

---

## 10. Harness change control (minimal)

Changes to any of these are “harness changes”:
- `plans/**`
- `scripts/check_*.py`
- `tools/validate_status.py`
- `python/schemas/**`

Harness changes require:
- `./plans/verify.sh full` green on a clean worktree before merge.

No other process requirements are imposed.

---

## 11. What is explicitly out of scope in this fork

- Ralph loop, `.ralph/**` artifacts
- workflow acceptance (and any CI-forced workflow acceptance routing)
- postmortem gate
- “CI mirrors local behavior” heuristics beyond running `./plans/verify.sh full`

This fork optimizes for: **clarity → throughput → correctness**.
