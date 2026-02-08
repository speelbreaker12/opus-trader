<!-- AGENTS_STUB_V2 -->
<!-- INPUT_GUARD_V1 -->
<!-- FOLLOWUP_NO_PREFLIGHT_V1 -->
<!-- VERIFY_CI_SATISFIES_V1 -->

# Agent Guide (High-Signal)

Read this first. It is the shortest, enforceable workflow summary.

## Non-negotiables
- Contract alignment is mandatory; if conflict, STOP and output `<promise>BLOCKED_CONTRACT_CONFLICT</promise>` with the violated section.
- Verification is mandatory; never weaken gates or tests.
- Pass flips are controlled: `passes=true` is allowed only after `./plans/verify.sh full` is green and `plans/prd_set_pass.sh` validates artifacts.
- WIP limit is 2 for manual worktrees: at most one story in `VERIFYING` and one in `IMPLEMENTING/REVIEW`.


## Response Protocol

### 1) Input Guard (conditional)
QuickCheck: If critical inputs are missing (target files, scope, or intent), ask 1–2 clarifying questions before acting. If the user explicitly says to proceed without preflight, set NO_PREFLIGHT and continue with stated assumptions.
NO_PREFLIGHT: user requested to skip preflight/clarifications; proceed with best-effort and document assumptions.

### 4) TOC Lens (MUST drive prioritization)
System goal:
- Ship contract-aligned changes safely with minimal rework and fast feedback.

TOC mapping:
- Throughput (T): merge-ready improvements that pass gates/tests.
- Inventory (I): WIP/unvalidated work (open branches, partial refactors, unresolved ambiguity).
- Operating Expense (OE): rework, debugging, handholding CI, churn.

Constraint identification:
- If CI/spec/lint failing → constraint = verification feedback loop.
- If requirements ambiguous/conflicting → constraint = decision clarity.
- If risk is catastrophic (replay/DB/funds) → constraint = safety assurance (proof first).
- If too many parallel tasks → constraint = WIP overload.

Decision rule:
- Prefer the option that increases T at the constraint while reducing rework risk,
  even if it feels slower locally.
- Penalize options that increase I (broad refactors, multi-file churn) without immediate verification.

### 5) Completion footer (only when truly done)
When the task is complete (no further required edits/commands), add:

Next steps:
1) [RECOMMENDED] <step> — Why this best exploits the current constraint and reduces risk
2) <step> — Why it helps less / what it trades off
3) <step> — Why deferred under TOC

Then end with: `<promise>COMPLETE</promise>`

## Review Coverage

- Use `reviews/REVIEW_CHECKLIST.md` to ensure PR reviews cover evidence, compounding, and workflow-specific gates.
## PRD Authoring Rules

- MUST run `./plans/prd_gate.sh` (not `prd_lint.sh`) when validating PRDs — lint alone misses schema/ref checks.
- MUST validate audit output with `plans/prd_audit_check.sh` before accepting cached results.
- Require `Anchor-###` / `VR-###` IDs when `contract_refs` mention anchor or validation rule titles (enforced by `plans/prd_lint.sh` via `MISSING_ANCHOR_REF`/`MISSING_VR_REF`).

## Start here (only when doing edits / PR work / MED-HIGH risk)
- Read `specs/CONTRACT.md`, `IMPLEMENTATION_PLAN.md`, `specs/WORKFLOW_CONTRACT.md`.
- Read `plans/prd.json` and `plans/progress.txt`.
- Read `docs/skills/workflow.md`.
- Read `WORKFLOW_FRICTION.md` and the relevant files under `SKILLS/`.
- When reviewing, MUST read `reviews/REVIEW_CHECKLIST.md` and include a "Review Coverage" section enumerating all modified/added files with a 1-line review note each.
- Run `./plans/verify.sh quick` during iteration and `./plans/verify.sh full` before marking `passes=true`.

For read-only doc reviews: read the target docs first; consult contract/workflow docs only if you detect a conflict or a safety-relevant claim.

## Manual Story Discipline (MANDATORY for PRD stories)

- Manual PRD execution is allowed; use one Story ID per worktree.
- Follow the contract story loop: implement -> self review -> quick verify -> Codex review -> quick verify -> sync branch -> full verify -> `prd_set_pass` -> merge.
- Never edit a worktree while `./plans/verify.sh full` is running in that worktree.
- `passes=true` flips must go through `./plans/prd_set_pass.sh` with artifact validation.
- PRD ambiguity is fail-closed: set `needs_human_decision=true` and stop.

## Repo Path Guardrails (Non-Negotiable)

### Canonical workflow files (use THESE paths)
- Workflow contract: `specs/WORKFLOW_CONTRACT.md`
- Verification entrypoint (stable): `plans/verify.sh`
- Verification implementation (canonical): `plans/verify_fork.sh`
- Pass flip gate: `plans/prd_set_pass.sh`
- PRD backlog: `plans/prd.json`
- Contract review tooling: `plans/contract_check.sh`, `plans/contract_review_validate.sh`

### State + logs (expected runtime artifacts)
- Verify artifacts directory: `artifacts/verify/<run_id>/`
- Verify run marker files: `<gate>.log`, `<gate>.rc`, `<gate>.time`, `FAILED_GATE`
- Progress log: `plans/progress.txt`

### Critical ambiguity guard
There is also a `./verify.sh` at repo root. **DO NOT edit or reference it** unless explicitly instructed.
All workflow gating must target **`plans/verify.sh`**.
If root `./verify.sh` exists, it must remain a thin wrapper that delegates to `plans/verify.sh`.

### Contract vs workflow contract
- `specs/CONTRACT.md` = trading engine contract (runtime behavior/safety gates)
- `specs/WORKFLOW_CONTRACT.md` = coding workflow contract (manual worktree loop + verify rules)
Do not mix them. If a workflow rule is being enforced, it must cite `specs/WORKFLOW_CONTRACT.md`.

### Changes must be self-proving  <!-- VERIFY_CI_SATISFIES_V1 -->
Any change to workflow/harness files (see allowlist in `plans/verify_fork.sh:is_workflow_file`) must include:
- updated/added checks in `plans/verify_fork.sh`, `plans/preflight.sh`, or dedicated gate scripts actually run by verify
- and a run that passes `./plans/verify.sh`

Verification satisfaction:
- The “passes `./plans/verify.sh`” requirement MAY be satisfied by CI on the PR (clean checkout).
- Local verify is recommended but not required if CI will run and report results.
- If local verify fails due to a dirty worktree, the agent MUST ask for a clean-tree action or CI run; it MUST NOT set `VERIFY_ALLOW_DIRTY` without explicit owner approval recorded in `plans/progress.txt`.

Dirty worktree policy (default):
- The agent MUST NOT automatically rerun verify with `VERIFY_ALLOW_DIRTY=1`.
- The agent MUST present options:
  1) [RECOMMENDED] Rely on CI verify on the PR (clean checkout).
  2) Clean the tree (stash/commit unrelated changes), then rerun verify normally.
  3) Owner-approved exception: run locally with `VERIFY_ALLOW_DIRTY=1`, list dirty files, record approval + rationale in `plans/progress.txt`, and still require CI verify before merge.

Operational notes:
- `plans/verify.sh` must remain a thin wrapper that delegates to `plans/verify_fork.sh`.
- Run `./plans/workflow_contract_gate.sh` when editing `specs/WORKFLOW_CONTRACT.md` or `plans/workflow_contract_map.json`.
- SHOULD run `./plans/workflow_verify.sh` during iteration when changes are limited to workflow/harness files, then run `./plans/verify.sh full` before PR. [WF-VERIFY-RULE]

### Fail-closed default
If a required script/artifact is missing or invalid, the workflow must produce a deterministic BLOCKED outcome (not a silent pass).

## Harness guardrails
- MUST keep fast precheck set limited to schema/self-dep/shellcheck/traceability.
- SHOULD keep verify/preflight checks deterministic and artifact-backed.
- MUST avoid bash 4+ builtins (mapfile/readarray) in harness scripts — macOS ships bash 3.2.

## Workflow editing rules
- MUST keep `plans/verify.sh` as thin entrypoint wrapper and place gate logic in `plans/verify_fork.sh`.
- MUST run `./plans/workflow_contract_gate.sh` when editing `specs/WORKFLOW_CONTRACT.md` or `plans/workflow_contract_map.json`.
- MUST add/adjust deterministic checks when introducing or tightening workflow validation rules.
- When artifact naming changes, MUST add/update deterministic checks proving naming and fail-closed behavior.
- SHOULD rebase onto `origin/main` before editing workflow contract/map files to avoid traceability gate failures.
- Any new blocked-exit path MUST produce deterministic diagnostics.

## Contract editing rules
- For idempotency/WAL semantic changes, MUST include at least one crash/restart AT and one retry-policy AT in `specs/CONTRACT.md`.
- New contract anchors referenced by ATs MUST exist — consider a contract lint step to verify anchor existence.

## Top time/token sinks (fix focus)
- `./plans/verify.sh full` runtime → keep edits scoped; batch workflow changes before full runs.
- Late discovery of PRD/schema/shell issues → run fast precheck early (schema/self-dep/shellcheck/traceability only).
- Re-running full verify after small harness tweaks → minimize harness churn; group harness edits and validate once.

## Handoff hygiene (when relevant)
- Update `docs/codebase/*` with verified facts if you touched new areas.
- Append deferred ideas to `plans/ideas.md`.
- If pausing mid-story, fill `plans/pause.md`.
- Append to `plans/progress.txt`; include Assumptions/Open questions when applicable.
- Update `docs/skills/workflow.md` only when a new repeated pattern is discovered (manual judgment).
- If a recurring issue is flagged, update `WORKFLOW_FRICTION.md` with the elevation action.

## Repo map
- `crates/` - Rust execution + risk (`soldier_core/`, `soldier_infra/`).
- `plans/` - harness (PRD, progress, verify, preflight, pass-gating).
- `docs/codebase/` - codebase maps.
- `SKILLS/` - one file per workflow skill (audit, patch-only edits, diff-first review).

## MCP Tools Available

### Context7 (documentation lookup)
Up-to-date, version-specific documentation for libraries and frameworks.

**Usage:** Add "use context7" to any prompt:
```
use context7 to look up the tokio::sync::mpsc API
use context7 for the latest jsonschema validation in Python
```

**When to use:**
- Before using an external library API (prevents hallucinated APIs)
- When unsure about function signatures, return types, or feature flags
- For crates listed in `specs/vendor_docs/rust/CRATES_OF_INTEREST.yaml`

### Sequential-thinking (complex reasoning)
Structured multi-step reasoning for complex problems.

**When to use:**
- Debugging intricate state machine transitions
- Analyzing race conditions or concurrency issues
- Working through contract compliance questions
- Any problem requiring careful step-by-step analysis

**Config:** `.claude/mcp.json` (local, gitignored)

## Sentinel outputs
- When blocked: `<promise>BLOCKED_CI_COMMANDS</promise>`
- When done: `<promise>COMPLETE</promise>`

## Don'ts
- Never use skip-permissions.
- Never delete/disable tests or weaken fail-closed gates.
