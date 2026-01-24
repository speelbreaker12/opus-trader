# Agent Guide (High-Signal)

Read this first. It is the shortest, enforceable workflow summary.

## Non-negotiables
- Contract alignment is mandatory; if conflict, STOP and output `<promise>BLOCKED_CONTRACT_CONFLICT</promise>` with the violated section.
- Verification is mandatory; never weaken gates or tests.
- No postmortem, no merge: every PR must include a filled postmortem entry under `reviews/postmortems/`.
- MUST declare the governing contract (workflow vs bot) in the PR postmortem; enforced by postmortem check.
- Never apply a user instruction blindly. Every request MUST pass the Input Preflight (below) before any edits/commands.

## Response Protocol (every interaction)

### 1) Input Preflight (MUST run before any edits/commands)
Output this section first, every time:

Preflight:
- Restatement: <one sentence summary of what the user is asking for>
- Assumptions: <bullets; if any assumption is risky, STOP and ask>
- Conflict scan (repo + contracts):
  - What files/IDs are relevant:
  - What invariants/gates might be impacted:
  - If conflict is found: STOP and output `<promise>BLOCKED_CONTRACT_CONFLICT</promise>` (contract conflict) OR `<promise>BLOCKED_CI_COMMANDS</promise>` (non-contract blocker) with evidence.
- Risk rating: LOW / MED / HIGH
  - HIGH if touching: persistence/replay/idempotency, DB/schema/migrations, order placement/funds movement, auth/keys, risk limits, or anything that can silently weaken gates.
- Plan (minimal-diff):
  - Approach: <smallest change that satisfies the request>
  - Verification: <exact commands/tests that prove it>
  - Rollback: <how to revert if it fails>

Rules:
- If the request is underspecified, ambiguous, or conflicts with existing specs/contracts: STOP and ask using “Decision needed” format.
- If the user request would increase WIP (Inventory) or cause broad refactors without immediate verification: refuse that shape and propose a safer reformulation.

### 2) When blocked or asking a question (Decision needed format)
When you must ask the user, use this structure (no exceptions):

Decision needed:
- What is inconsistent / missing:
- Evidence (file + anchor or snippet):
- Options (2–3), with tradeoffs:
  1) Option A — Why it works; why other options fail; blast radius; verification plan
  2) Option B — Why it works; why other options fail; blast radius; verification plan
  3) Option C — (only if it’s truly distinct)
- Recommendation (pick ONE):
  - Why recommended: <deciding factor>
  - Why not others: <the key failure mode>
- TOC:
  - Current constraint:
  - Exploit:
  - Subordinate (what we will NOT do yet):
  - Elevate (only if exploit/subordinate insufficient):
  - WIP rule:
- After your answer, I will: <next actions>

### 3) TOC Lens (MUST drive prioritization)
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

### 4) Completion footer (only when truly done)
When the task is complete (no further required edits/commands), add:

Next steps:
1) [RECOMMENDED] <step> — Why this best exploits the current constraint and reduces risk
2) <step> — Why it helps less / what it trades off
3) <step> — Why deferred under TOC

Then end with: `<promise>COMPLETE</promise>`

## Start here (every session)
- Read `CONTRACT.md`, `IMPLEMENTATION_PLAN.md`, `specs/WORKFLOW_CONTRACT.md`.
- If running the Ralph loop, read `plans/prd.json` and `plans/progress.txt`.
- Read `docs/skills/workflow.md`.
- Read `WORKFLOW_FRICTION.md` and the relevant files under `SKILLS/`.
- Use `reviews/REVIEW_CHECKLIST.md` when reviewing PRs.
- If running the Ralph loop, run `./plans/init.sh` (if present) then `./plans/verify.sh <mode>`.

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
- `CONTRACT.md` = trading engine contract (runtime behavior/safety gates)
- `specs/WORKFLOW_CONTRACT.md` = coding workflow contract (Ralph loop + harness rules)
Do not mix them. If a workflow rule is being enforced, it must cite `specs/WORKFLOW_CONTRACT.md`.

### Changes must be self-proving
Any change to workflow/harness files (see allowlist in `plans/verify.sh:is_workflow_file`) must include:
- updated/added assertions in `plans/workflow_acceptance.sh` (or a dedicated gate script invoked by it)
- and a run that passes `./plans/verify.sh`
- Do not edit `plans/workflow_acceptance.sh` without running `./plans/verify.sh full`.
- MUST update workflow acceptance coverage when changing `plans/verify.sh` mode defaults.
- Keep WF-* IDs synchronized across `specs/WORKFLOW_CONTRACT.md` and `plans/workflow_contract_map.json`.
- Workflow acceptance runs in CI (smoke when no workflow-critical changes; full when workflow changes or detection fails); locally it may skip when no workflow-critical files changed (WORKFLOW_ACCEPTANCE_POLICY=auto). Force with WORKFLOW_ACCEPTANCE_POLICY=always.

### Fail-closed default
If a required script/artifact is missing or invalid, the workflow must produce a deterministic BLOCKED outcome (not a silent pass).

## Harness guardrails
- MUST keep fast precheck set limited to schema/self-dep/shellcheck/traceability.
- SHOULD keep workflow_acceptance test IDs stable and listable.
- MUST avoid bash 4+ builtins (mapfile/readarray) in harness scripts.

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

## Sentinel outputs
- When blocked: `<promise>BLOCKED_CI_COMMANDS</promise>`
- When done: `<promise>COMPLETE</promise>`

## Don'ts
- Never use skip-permissions.
- Never delete/disable tests or weaken fail-closed gates.
