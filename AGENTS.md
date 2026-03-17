# AGENTS.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Commands

### Rust

```bash
# Build
cargo build --workspace

# Format check (CI gate) / fix
cargo fmt --all -- --check
cargo fmt --all

# Clippy — quick (lib targets only, used in quick verify)
cargo clippy --workspace --lib -- -D warnings

# Clippy — full (all targets, used in CI/full verify)
cargo clippy --workspace --all-targets --all-features -- -D warnings

# All tests (full verify)
cargo test --workspace --all-features --locked

# Tests — quick (lib only)
cargo test --workspace --lib --locked

# Single test by name
cargo test -p soldier_core --lib <test_name>
cargo test -p soldier_core --lib <test_name> -- --nocapture

# Facade contract tests (integration layer)
cargo test -p soldier_core --locked \
  --test test_execution_facade_public \
  --test test_risk_facade_public \
  --test test_venue_facade_public \
  --test test_tlsm
```

### Verification gates

```bash
./plans/verify.sh quick   # Fast iteration: fmt + lib clippy + lib tests + fast schema checks
./plans/verify.sh full    # CI completion gate: all targets, all tests, crossref, coverage, proof graph
./plans/workflow_verify.sh  # Workflow-file-only changes; run before full verify
```

### Python

```bash
# Python gates are invoked by verify.sh via plans/lib/python_gates.sh
# To run manually:
python3 -m pytest tests/         # repo integration tests
python3 python/proof_graph/validate.py <path>  # proof graph validation
```

## Architecture

### Crate layout

The Rust workspace has two crates (`Cargo.toml`):

- **`soldier_core`** — pure domain logic; no network I/O, no async runtime. Dependencies: `serde`, `tracing`, `xxhash-rust` only. `#![forbid(unsafe_code)]`.
- **`soldier_infra`** — exchange adapters and infra. Depends on `soldier_core`. Houses Deribit types, WAL, config/store bootstrap. All modules are private; only `pub use api::*` is exported.

### soldier_core module breakdown

| Module | Responsibility |
|--------|----------------|
| `execution` | Full order execution pipeline: intent assembly → gate chain → WAL gate → dispatch chokepoint → `build_order_intent` |
| `risk` | Risk gates: exposure budget, fee staleness, margin headroom, pending exposure tracking, `RiskState` |
| `venue` | `InstrumentKind` derivation, instrument cache with TTL (staleness → `RiskState::Degraded`) |
| `idempotency` | Intent idempotency hashing |
| `recovery` | Label matching for intent recovery/reconciliation |
| `status_codes` | Generated and hand-authored status/reject reason codes |

**Phase-1 facade lockdown:** every sub-module is `pub(crate)` / `#[cfg_attr(not(test), allow(dead_code))]`; external consumers MUST use the `api.rs` facade only. Test files `facade_completeness_contract_tests.rs` enforce this boundary.

### Execution pipeline (soldier_core::execution)

An `ExecutionInput` flows through a sequential gate chain inside `engine.rs`:

```
preflight → liquidity gate → net-edge gate → pricer → quantize →
inventory-skew → post-only guard → fee staleness → margin gate →
pending exposure → exposure budget → WAL gate (RecordedBeforeDispatchGate) →
dispatch chokepoint (build_order_intent) → dispatch
```

Any gate can return an `ExecutionRejection` with a `RejectReasonCode`. All reject reason codes are registered in `reject_reason_registry()` and referenced in `specs/CONTRACT.md` ATs. The pipeline is synchronous (no async).

Atomic group execution (`group.rs`, `GroupLock`) ensures multi-leg orders are dispatched atomically or rolled back — all legs succeed or none are dispatched.

### Safety model

Two independent layers:

1. **RiskState** (`Healthy | Degraded | Maintenance | Kill`) — health/cause layer, set by instrument cache TTL misses, fee staleness, etc.
2. **TradingMode** (`Active | ReduceOnly | Kill`) — enforcement layer, resolved by `PolicyGuard` each tick from RiskState + policy staleness + watchdog + exchange health + Cortex overrides.

Fail-closed rule: any uncertain or missing input → `TradingMode::ReduceOnly`, never `Active`.

The **Open Permission Latch** (`CP-001`) independently blocks OPEN intents after restart, WS gaps, or session kill until explicit reconciliation clears it.

### Contract traceability

`specs/CONTRACT.md` (v5.2) is the behavioral source of truth. Every gate has paired AT (acceptance test) IDs. PRD stories in `plans/prd.json` reference these ATs. The `plans/crossref_gate.sh` enforces that contract clauses have matching implementation traces in `specs/TRACE.yaml`.

Two contracts, do not mix:
- `specs/CONTRACT.md` — trading engine runtime behavior
- `specs/WORKFLOW_CONTRACT.md` — coding workflow rules (story loop, verify gates)

<!-- AGENTS_STUB_V2 -->
<!-- INPUT_GUARD_V1 -->
<!-- FOLLOWUP_NO_PREFLIGHT_V1 -->
<!-- VERIFY_CI_SATISFIES_V1 -->

# Agent Guide (High-Signal)

Read this first. It is the shortest, enforceable workflow summary.

## Rust Skills (Mandatory for any Rust work)

This is a Rust trading-engine codebase. Before writing or reviewing Rust code, you MUST apply:

| Skill | When |
|-------|------|
| `domain-fintech` | Any order/price/quantity/decimal/currency logic — no float arithmetic, use Decimal |
| `m01-ownership` | Borrow/lifetime/move errors (E0382, E0597, E0506) |
| `m07-concurrency` | async/await, Arc/Mutex, Send+Sync, thread safety |

If you are a Claude agent: invoke `Skill(domain-fintech)`, `Skill(m01-ownership)`, `Skill(m07-concurrency)` via the Skill tool before writing Rust.
If you are a non-Claude agent (Codex, Gemini, Kimi): apply the three-layer pattern — Layer 1 (language mechanics) → Layer 2 (design choice) → Layer 3 (fintech domain constraint) before proposing any Rust change.

Key fintech rules:
- Never use `f32`/`f64` for prices, quantities, or fees — use `Decimal` or newtypes
- Fail-closed: if uncertain, choose `TradingMode::ReduceOnly`, never `Active`
- No `unwrap()` in production paths — use `?` or explicit error handling

## Obsidian Project Tracking (Mandatory)

Every agent session must track work in `obsidian/Projects/`.

**On session start:** Read all `obsidian/Projects/*.md` files to understand active work, priorities, and current state.
If the Obsidian router hook points to `/obsidian-workflow`, use it as the project-page/debrief checklist companion.
Project notes may include optional frontmatter `aliases` and `keywords` to improve first-prompt router matching; keep them current when they materially help rediscovery.
Project notes should record a dedicated `worktree` path and keep `branch` aligned with that worktree. Keep `worktree_obsidian` aligned to the project-local Obsidian folder path so dashboard links can open that workspace directly.
For no-mirror viewing, treat `worktree_obsidian` as authoritative and avoid copying worktree notes into main.
When a project is matched, use that worktree for commands/edits in the session; if it is missing, create one at `.worktrees/<project-slug>` and update the project note before substantive work.
Refresh the local project dashboard when worktree references change:
- Run `python3 .claude/scripts/refresh_active_projects_index.py --repo-root .`
- Commit updates to `obsidian/Active Projects.md` as part of the same Obsidian-scoped commit.
If work is paused mid-stream, blocked, or the user explicitly asks for a handoff, write it to `obsidian/Handoffs/<Project> <date> <Short Title>.md` from `obsidian/Templates/Handoff.md` and link it from the project note. This does not replace `plans/pause.md` or any workflow-specific required handoff artifact.

**Before every commit:** Update or create the relevant project file in `obsidian/Projects/`:
1. Add a dated entry under `## Log` describing what changed
2. Update `## Current State` if the project status shifted
3. Update the `## Commits` section near the top of the note with date + hash (or `pending`) + short description for each project batch
4. Update frontmatter (`status`, `priority`, `branch`, `pr`) if needed
5. Write or update a matching debrief in `obsidian/Debriefs/` and link it from the project's `## Debriefs` section

**If no existing project matches your work:** Create a new one by copying `obsidian/Templates/Project.md` to `obsidian/Projects/<Project Name>.md` and filling in the fields.

**The git pre-commit hook will block commits** that don't include staged changes to both `obsidian/Projects/*.md` and `obsidian/Debriefs/*.md`, it requires the staged project note to link at least one staged debrief, and all staged Obsidian project/debrief files in that commit must belong to exactly one project.

**At end of session:** Write a debrief in `obsidian/Debriefs/<Project> <date>.md` using the template in `obsidian/Templates/Debrief.md`. Include a `## Commits` section with the relevant commit hash(es); if the debrief is written before the commit exists, record `pending` and replace it once the commit is known. Keep the project note's `## Commits` section near the top in the same date/hash/summary format, and link the debrief from the project's `## Debriefs` section before committing.

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
- After each significant implementation change (behavior changes, multi-file refactors, or workflow/harness logic updates), MUST run the `code-review-expert` skill by default before final verify/merge.

### Default Review Output Format

When asked to "review" a PR/change, default to this compact format:
1. Severity + short title
2. File(s)
3. Problem
4. Expected fix
5. Impact

Rules:
- Keep entries short and scan-friendly.
- Do not use absolute filesystem paths by default.
- Use repo-relative file references with line numbers (e.g., `plans/wf_step.sh:520`).
- Put findings first, ordered by severity (P0 → P1 → P2), then optional test gaps/notes.
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
- Follow the contract story loop: implement -> self review -> quick verify -> Codex review -> Kimi K2.5 review -> quick verify -> second Codex review -> quick verify -> sync branch -> full verify -> `prd_set_pass` -> merge.
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

## /reconcil — Premortem + Reconciliation Orchestrator

Run to audit already-passing stories or start a fresh reconciliation session. Full spec: `SKILLS/reconcil.md`.

1. Check for active handoff: `ls reviews/reconciliations/*/HANDOFF.md 2>/dev/null`
2. **No HANDOFF found → Fresh start**: read `reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md`, ask which slice/stories, copy template, begin.
3. **HANDOFF found → Update first, then act**:
   - Fill unfilled `{{...}}` placeholders in completed/in-progress steps.
   - Update the status matrix (symbols: `·` `→` `✓` `✗`).
   - Rewrite the HANDOFF section (stopped-at · what happened · must-read artifacts · next steps · resume command).
   - Continue if context healthy; stop after writing HANDOFF if context is nearly full.

Hard rules: R1 (preflight) is read-only. No Cycle 2 without `R5B_SELF_REVIEW_PROVEN` gate. No fake citations. No DEFERRED without a schema-validated debt register entry.

---

## /toc — Theory of Constraints Commit

Run after completing any unit of work. Full spec: `SKILLS/toc.md`.

1. Commit current changes with project conventions.
2. Answer four sections in chat:
   - **§0 What shipped** — feature/behavior + value (one sentence each)
   - **§1 Constraint (ONE)** — symptoms · token drain · exploit (workaround used) · subordinate (next-agent default) · elevate (permanent fix) · smallest increment · validation metric
   - **§2 Next story** — single best follow-up + 1–3 upgrade candidates, each with increment + validation
   - **§3 Enforceable rules** — 1–3 rules in `rule / trigger / prevents / enforce` format for the next agent

Hard rule: §1 must name exactly ONE constraint. §3 rules must each name a specific `enforce:` target.

---

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
