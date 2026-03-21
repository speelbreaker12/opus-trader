# Phase 1 Remediation Roadmap Design

## Goal

Design a mergeable remediation roadmap for the audited Phase 1 regressions in the trading engine while respecting the repo's workflow constraints and contract-first verification model.

The roadmap must:

- treat the current workflow baseline red state as a precondition, not background noise
- sequence work by risk and proof burden rather than by audit section order
- keep each implementation story small enough to land independently
- keep CONDITIONAL_PASS cleanup separate from core regression remediation
- preserve the audit branch as evidence and planning, not implementation scope

## Context

This design is based on:

- `reviews/subsystem_audit_2026-03-21.md`
- `obsidian/Projects/Subsystem Audit Phase 1 Revalidation.md`
- the current `specs/CONTRACT.md` and `plans/prd.json`

The audit identifies these shipped Phase 1 regressions:

- `EMCLOSE-001`
- `MARGIN-001` through `MARGIN-006`
- `RSI-001`, `RSI-002`
- `WAL-001`, `WAL-002`, `WAL-004`, `WAL-005`
- `EMCLOSE-006`

The audit also records a workflow precondition: current `main` is not considered landable for follow-on work until the `wf_test_pr_review_gate_hook` baseline issue is inherited from, or fixed on, the chosen integration base.

The audit's WAL verdict matters to sequencing. `RecordedBeforeDispatch / WAL` is marked `CONDITIONAL_PASS`, production dispatch uses the adapter path, and `WAL-002` is recorded as an operational monitoring concern rather than a must-fix blocker. Those findings remain valid cleanup targets, but they should not sit on the core remediation critical path ahead of real Phase 1 regressions.

## Approaches Considered

### 1. Safety-first mergeable stories

Treat the workflow baseline fix as a hard prerequisite, then land a sequence of small remediation stories in risk order.

Pros:

- best fit for the repo's verify and branch discipline
- minimizes mixed-risk diffs
- keeps contract proof local to one defect family at a time

Cons:

- more planning overhead
- more branch and worktree churn

### 2. Subsystem sweeps

Create one story per subsystem such as Emergency Close, Margin Gate, WAL, and type drift.

Pros:

- easier to explain at a subsystem level
- fewer branches than a fine-grained sequence

Cons:

- each story becomes wider
- mixes semantic fixes with cleanup
- harder to attribute failures to one contract delta

### 3. Single remediation batch

Fix every Phase 1 regression after the workflow baseline is green.

Pros:

- lowest upfront planning cost

Cons:

- highest integration risk
- weakest mergeability
- worst fit for strict receipt and verification discipline

## Recommendation

Use the safety-first mergeable-stories approach, with a narrow critical path and an explicit cleanup lane.

This is the best match for the repo's actual constraint: mergeable, contract-proven increments matter more than minimizing branch count. Each core story should change one behavioral surface or one tightly coupled defect family, with explicit proof tied back to the audit item and contract expectation. Cleanup from a CONDITIONAL_PASS subsystem should stay optional unless new evidence shows it has become a true landing blocker.

## Roadmap Structure

The roadmap has two lanes, but only one is on the critical path.

### Lane A: workflow precondition

Before any remediation story is considered landable, the chosen integration base must have the workflow baseline fixed or inherited:

- `plans/tests/test_pr_review_gate_hook.sh`
- any directly coupled workflow wrapper checks

This precondition should be treated as story zero or as a branch-base requirement. It must not be mixed into the Phase 1 remediation stories.

### Lane B: Core Phase 1 remediation

Once the base is green enough to land work, Phase 1 remediation proceeds as independent stories in risk order.

### Lane C: Optional cleanup

Conditional-pass cleanup that does not block safe landing belongs after the core remediation lane. It can be scheduled once the real Phase 1 regressions are closed or pulled forward only if fresh evidence shows it has become a release blocker.

## Proposed Story Sequence

### Story 0: Workflow Baseline Green

Purpose:

- make the branch base landable by clearing the known PR-review-gate workflow red state

Scope:

- workflow and harness files only

Exit criteria:

- `plans/tests/test_pr_review_gate_hook.sh` passes on the chosen integration base
- coupled workflow wrapper checks remain green

Out of scope:

- any Phase 1 trading-engine remediation

### Story 1: Emergency Close Fail-open Removal

Audit items:

- `EMCLOSE-001`
- `EMCLOSE-006`

Purpose:

- ensure stale fee state cannot block risk-reducing intents

Scope:

- `execution/base_gates.rs`
- emergency-close tests and chokepoint coverage

Exit criteria:

- `Close`, `Hedge`, and `Cancel` cannot be blocked by stale fee gating
- explicit regression proof exists for `Close/Hedge` under `RiskState::Kill`

Out of scope:

- full emergency close algorithm work from Phase 2

### Story 2: Margin Gate Input Semantics

Audit items:

- `MARGIN-001`
- `MARGIN-002`
- `MARGIN-003`
- `MARGIN-004`

Purpose:

- make missing, stale, or diagnostically incomplete margin inputs fail closed with the correct contract-visible behavior

Scope:

- `MarginHeadroomInputMissing` across the runtime enum, manifests, and generated/codegen-facing surfaces
- NaN and missing-input handling
- `account_summary_max_age_ms` wiring
- required observability counters and logs

Exit criteria:

- `MarginHeadroomInputMissing` exists and is emitted where required
- the reject-code registry and generated/codegen-facing surfaces agree with the runtime behavior
- NaN or missing inputs degrade as required instead of escalating to `Kill`
- account-summary freshness enforcement uses the contract value
- required observability is present and test-covered

Out of scope:

- arithmetic cleanup that does not change missing or stale input semantics

### Story 3: Margin Gate Interface, Wiring, and Math Correctness

Audit items:

- `MARGIN-005`
- `MARGIN-006`

Purpose:

- align the margin gate's required inputs, caller wiring, and numerical behavior with the audited contract expectations without mixing it into the fail-closed semantic story

Scope:

- `initial_margin` field addition or restoration on `MarginGateInput` and its callers
- `initial_margin` validation and consumption
- `mm_util` denominator rule

Exit criteria:

- `MarginGateInput` exposes the contract-required `initial_margin` input through the relevant wiring surfaces
- `initial_margin` is used or validated as required by the contract
- `mm_util` uses the contract-safe denominator rule such as `max(equity, epsilon)`

Out of scope:

- freshness and reject-reason semantics already handled in Story 2

### Story 4: Type and Registry Alignment

Audit items:

- `RSI-001`
- `RSI-002`

Purpose:

- remove duplicated or drifting safety-type definitions that can invalidate later PolicyGuard work and contract reasoning

Scope:

- authoritative `RiskState`
- generated vs. runtime `ModeReasonCode` alignment

Exit criteria:

- one authoritative `RiskState` shape is used across the relevant surfaces
- generated or exported `ModeReasonCode` values align with the contract registry

Out of scope:

- implementing PolicyGuard itself

## Optional Cleanup Lane

### Cleanup Story: WAL Phase 1 Cleanup

Audit items:

- `WAL-001`
- `WAL-002`
- `WAL-004`
- `WAL-005`

Purpose:

- remove residual WAL cleanup findings that remain after the core regression lane is complete

Why this is not on the critical path:

- the audit verdict for `RecordedBeforeDispatch / WAL` is `CONDITIONAL_PASS`
- production uses the adapter path
- `WAL-002` is recorded as an operational monitoring concern, not a mandatory code-change blocker

Scope:

- deprecated bypass path
- `NoGateConfiguredWalGate` false-success behavior
- dead `WalBarrierConfig` path
- `GateResults::new(true)` pre-approval semantics

Exit criteria:

- no production path claims safe approval without real gating or recording
- dead or deprecated safety-shaping paths are removed or proven unreachable

Out of scope:

- Phase 3 EvidenceGuard or TruthCapsule work

## Verification Strategy

Every remediation story should produce the same evidence shape:

1. Targeted failing tests for the audited behavior before the fix.
2. Smallest implementation that addresses the specific defect family.
3. Story-local proof tied to the contract expectation and audit item.
4. Quick verification on the touched surface.
5. No unrelated workflow-harness repairs in the same story.

Per-story proof should include:

- audit item reference
- contract or PRD reference
- focused command output
- final green targeted tests

Recommended commands vary by story, but should stay scoped. Example families:

- targeted Rust tests in `soldier_core`
- focused facade or execution/risk tests
- story-local quick verify where the repo process requires it

## Branch and Worktree Strategy

- Keep the audit note branch doc-only.
- Do not widen `project/subsystem-audit-phase1-revalidation` to own remediation code.
- Base each remediation branch on the clean integration branch that already contains Story 0.
- Schedule WAL cleanup from the post-remediation base only if it still justifies a dedicated branch.
- Use one worktree per remediation story.
- Keep stories mergeable and independently reviewable.

This avoids mixing planning evidence, workflow fixes, and trading-engine remediation into one branch.

## Error Handling and Constraints

### If Story 0 is still red

No remediation story should be treated as commit-ready. The workflow baseline remains the current constraint.

### If a story needs contract clarification

Fail closed. Capture the ambiguity explicitly rather than bundling speculative implementation into the story.

### If a defect family expands during implementation

Prefer a new follow-on story over widening the current one unless the added work is inseparable from the same contract surface.

## Out of Scope

This roadmap does not include:

- PolicyGuard implementation
- Open Permission Latch implementation
- Phase 2 emergency-close algorithm work
- Phase 3 evidence pipeline work
- audit-note publication mechanics beyond acknowledging the workflow precondition

## Design Summary

The recommended plan is:

1. clear or inherit the workflow baseline fix first
2. land four core Phase 1 remediation stories in risk order
3. treat WAL cleanup as an optional post-remediation lane unless fresh evidence promotes it
4. keep the audit branch as evidence and planning only
5. demand contract-proven exits for each story instead of one large remediation batch

This provides the narrowest path to reducing real Phase 1 risk while preserving the repo's verification discipline.
