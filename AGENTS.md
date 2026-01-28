<!-- AGENTS_STUB_V2 -->
<!-- INPUT_GUARD_V1 -->
<!-- FOLLOWUP_NO_PREFLIGHT_V1 -->
<!-- VERIFY_CI_SATISFIES_V1 -->

# Agent Guide (High-Signal)

Read this first. It is the shortest, enforceable workflow summary.

## Non-negotiables
- Contract alignment is mandatory; if conflict, STOP and output `<promise>BLOCKED_CONTRACT_CONFLICT</promise>` with the violated section.
- Verification is mandatory; never weaken gates or tests.
- No postmortem, no merge: every PR must include a filled postmortem entry under `reviews/postmortems/`.
- MUST declare the governing contract (workflow vs bot) in the PR postmortem; enforced by postmortem check.


## Response Protocol


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

## Start here (only when doing edits / PR work / MED-HIGH risk)
- Read `specs/CONTRACT.md`, `IMPLEMENTATION_PLAN.md`, `specs/WORKFLOW_CONTRACT.md`.
- If running the Ralph loop, read `plans/prd.json` and `plans/progress.txt`.
- Read `docs/skills/workflow.md`.
- Read `WORKFLOW_FRICTION.md` and the relevant files under `SKILLS/`.
- Use `reviews/REVIEW_CHECKLIST.md` when reviewing PRs.
- If running the Ralph loop, run `./plans/init.sh` (if present) then `./plans/verify.sh <mode>`.

For read-only doc reviews: read the target docs first; consult contract/workflow docs only if you detect a conflict or a safety-relevant claim.

## Ralph loop only (PRD iterations)
- WIP=1: exactly one PRD item and one commit per iteration.
- Work only the selected PRD item.
- Fail closed on PRD ambiguity; set needs_human_decision=true and stop.

## Repo Path Guardrails (Non-Negotiable)

### Canonical workflow files (use THESE paths)
- Workflow contract: `specs/WORKFLOW_CONTRACT.md`
- Ralph orchestrator: `plans/ralph.sh`
- Verification gate (canonical): `plans/verify.sh`
- Acceptance harness: `plans/workflow_acceptance.sh`
- Initializer: `plans/init.sh`
- PRD backlog: `plans/prd.json`
- Contract review tooling: `plans/contract_check.sh`, `plans/contract_review_validate.sh`

### State + logs (expected runtime artifacts)
- Ralph state directory: `.ralph/`
- Canonical state file: `.ralph/state.json`
- Run logs directory: `plans/logs/`

### Critical ambiguity guard
There is also a `./verify.sh` at repo root. **DO NOT edit or reference it** unless explicitly instructed.
All workflow gating must target **`plans/verify.sh`**.
If root `./verify.sh` exists, it must remain a thin wrapper that delegates to `plans/verify.sh`.

### Contract vs workflow contract
- `specs/CONTRACT.md` = trading engine contract (runtime behavior/safety gates)
- `specs/WORKFLOW_CONTRACT.md` = coding workflow contract (Ralph loop + harness rules)
Do not mix them. If a workflow rule is being enforced, it must cite `specs/WORKFLOW_CONTRACT.md`.

### Changes must be self-proving  <!-- VERIFY_CI_SATISFIES_V1 -->
Any change to workflow/harness files (see allowlist in `plans/verify.sh:is_workflow_file`) must include:
- updated/added assertions in `plans/workflow_acceptance.sh` (or a dedicated gate script invoked by it)
- and a run that passes `./plans/verify.sh`

Verification satisfaction:
- The “passes `./plans/verify.sh`” requirement MAY be satisfied by CI on the PR (clean checkout).
- Local verify is recommended but not required if CI will run and report results.
- If local verify fails due to a dirty worktree, the agent MUST ask for a clean-tree action or CI run; it MUST NOT set `VERIFY_ALLOW_DIRTY` without explicit owner approval recorded in the postmortem.

Dirty worktree policy (default):
- The agent MUST NOT automatically rerun verify with `VERIFY_ALLOW_DIRTY=1`.
- The agent MUST present options:
  1) [RECOMMENDED] Rely on CI verify on the PR (clean checkout).
  2) Clean the tree (stash/commit unrelated changes), then rerun verify normally.
  3) Owner-approved exception: run locally with `VERIFY_ALLOW_DIRTY=1`, list dirty files, record approval + rationale in postmortem, and still require CI verify before merge.

Operational notes:
- Do not edit `plans/workflow_acceptance.sh` without running `./plans/verify.sh full` OR relying on CI verify for proof.
- MUST update workflow acceptance coverage when changing `plans/verify.sh` mode defaults.
- Keep WF-* IDs synchronized across `specs/WORKFLOW_CONTRACT.md` and `plans/workflow_contract_map.json`.
- Workflow acceptance runs in CI (smoke when no workflow-critical changes; full when workflow changes or detection fails); locally it may skip when no workflow-critical files changed (WORKFLOW_ACCEPTANCE_POLICY=auto). Force with WORKFLOW_ACCEPTANCE_POLICY=always.

### Fail-closed default
If a required script/artifact is missing or invalid, the workflow must produce a deterministic BLOCKED outcome (not a silent pass).

## Harness guardrails
- MUST keep fast precheck set limited to schema/self-dep/shellcheck/traceability.
- SHOULD keep workflow_acceptance test IDs stable and listable.
- MUST avoid brittle acceptance checks that grep long prose sentences; prefer stable markers (the HTML comments at top) and short headers.

## Top time/token sinks (fix focus)
- `plans/workflow_acceptance.sh` full runtime → keep acceptance tests targeted; avoid unnecessary workflow file edits; batch changes before full runs.
- Late discovery of PRD/schema/shell issues → run fast precheck early (schema/self-dep/shellcheck/traceability only).
- Re-running full verify after small harness tweaks → minimize harness churn; group harness edits and validate once.

## Handoff hygiene (when relevant)
- Update `docs/codebase/*` with verified facts if you touched new areas.
- Append deferred ideas to `plans/ideas.md`.
- If pausing mid-story, fill `plans/pause.md`.
- Append to `plans/progress.txt`; include Assumptions/Open questions when applicable.
- Update `docs/skills/workflow.md` only when a new repeated pattern is discovered (manual judgment).
- Add a PR postmortem entry using `reviews/postmortems/PR_POSTMORTEM_TEMPLATE.md`.
- If a recurring issue is flagged, update `WORKFLOW_FRICTION.md` with the elevation action.

## Repo map
- `crates/` - Rust execution + risk (`soldier_core/`, `soldier_infra/`).
- `plans/` - harness (PRD, progress, verify, ralph).
- `docs/codebase/` - codebase maps.
- `SKILLS/` - one file per workflow skill (audit, patch-only edits, diff-first review).
- `reviews/postmortems/` - PR postmortem entries (agent-filled).

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
