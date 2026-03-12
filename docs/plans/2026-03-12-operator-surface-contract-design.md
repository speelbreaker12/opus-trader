# Operator Surface Contract Design

Date: 2026-03-12

## Summary

This design adds an explicit operator-surface model to the contract without changing the runtime trading authority model. The patch formalizes how dashboards, replicated status stores, and explicitly derived operator-state documents consume canonical runtime status, while preserving `/api/v1/status` as the only authoritative runtime surface after foundation mode.

P0 owner scaffolding remains a separate bootstrap category already defined by P0-E. This patch does not reclassify those CLI/local owner surfaces.

The design is intentionally narrow:
- no bot lifecycle semantics
- no multi-exchange semantics
- no writable HTTP endpoints
- no expansion of canonical trading authority beyond existing PolicyGuard and latch rules

## Problem

The current contract already distinguishes:
- P0 owner scaffolding
- foundation `/api/v1/status` status-lite
- CSP minimum `/api/v1/status`

But it does not yet define a general class for downstream non-authoritative operator presentation surfaces. That leaves a drift risk:
- dashboards can present stale summaries as if they were authoritative
- convenience fields can conflict with canonical `/api/v1/status`
- replicated status views can blur the boundary between source-of-truth and presentation state
- derived publisher inputs such as `runtime_state.v1` can blur the boundary unless their derivation contract is explicit

This is especially important because the repo already has a dashboard/publisher pipeline and freshness model outside the core runtime contract.

## Goals

- Make the runtime authority boundary explicit.
- Allow operator-facing dashboards and summaries to exist as first-class contract consumers.
- Force presentation surfaces to fail closed when their source status is stale, missing, or invalid.
- Prevent operator surfaces from contradicting canonical runtime authority fields.
- Preserve the existing P0 owner scaffolding carve-out.
- Keep the patch small enough to land in the existing status/control-plane sections.

## Non-Goals

- Defining bot lifecycle or strategy editing semantics.
- Requiring new write endpoints.
- Replacing the canonical `/api/v1/status` schema.
- Expanding venue scope beyond the existing Deribit-first contract.
- Defining a UI design or screen-level product spec.

## Existing Contract Baseline

The contract already establishes:
- `/api/v1/health` as a minimal liveness surface.
- foundation `/api/v1/status` as status-lite only while `phase == foundation`.
- CSP minimum `/api/v1/status` as the canonical runtime authority after foundation mode exits.
- P0 owner scaffolding as non-authoritative companion output.

The implementation baseline also already includes a dashboard/publisher pipeline with a separate `runtime_state.v1` document. The new design must treat that path as either:
- an explicitly derived operator-state document that preserves canonical status conclusions, or
- out of scope for this patch

The design here chooses the first option while keeping runtime authority unchanged.

## Proposed Contract Changes

### 1. Extend the status authority matrix

Add `Operator Presentation Surfaces` to the existing status authority matrix near the P0-E clarifications, without folding P0 owner scaffolding into this new row.

Definition:
- Any dashboard, exported JSON summary, replicated status store, or derived operator-state document such as `runtime_state.v1` that is mechanically produced from canonical runtime status for humans or downstream tooling.
- P0 owner scaffolding CLI/local status surfaces remain governed by P0-E and stay outside this row.

Authority boundary:
- Non-authoritative.
- Must derive from canonical runtime status or foundation status-lite, depending on phase, either directly or through an explicitly defined derived operator-state schema.
- May rename or reshape fields only if the resulting semantics remain equivalent and non-contradictory.
- Must not redefine canonical runtime authority.

### 2. Add a new subsection in Section 7.0

Add a small normative subsection immediately after the current status surface split. Suggested title:
- `7.0.1 Runtime Authority vs Operator Presentation Surfaces`

This subsection should define:
- canonical source precedence
- direct-vs-derived source rules
- freshness semantics
- fail-closed presentation rules
- semantic-equivalence requirements for renamed or reshaped fields
- conflict prohibition for canonical field names and meanings

### 3. Keep runtime authority unchanged

The patch must explicitly preserve:
- `GET /api/v1/status` as the only canonical runtime authority after foundation mode
- `GET /api/v1/health` semantics unchanged
- foundation status-lite behavior unchanged
- existing CSP minimum `/status` schema unchanged unless a true gap is later proven

### 4. Do not require new writable endpoints

This patch should not require:
- `POST /api/v1/*`
- mutable operator-control HTTP endpoints
- bot or strategy management APIs

Future owner control surfaces may be defined later as transport-agnostic request channels, but that is out of scope for this patch.

## Normative Rules To Add

### Runtime authority

- After foundation mode exits, `GET /api/v1/status` remains the only canonical runtime authority surface for dispatch/readiness semantics.

### Operator presentation surface definition

- An operator presentation surface is a non-authoritative consumer of canonical runtime status.
- It may add history, annotations, freshness summaries, and UX-specific convenience fields.
- It may consume canonical status directly or through an explicitly defined derived operator-state document such as `runtime_state.v1`.
- P0 owner scaffolding remains a separate P0-E surface and is not reclassified by this patch.

### Source precedence and derivation

- After foundation mode exits, operator presentation surfaces must derive dispatch/readiness semantics from canonical `GET /api/v1/status`.
- While `phase == foundation`, operator presentation surfaces must derive only from the foundation status-lite surface.
- A derived operator-state document remains non-authoritative and must preserve the same blocked/open conclusions as the canonical status it was derived from.

### Conflict prohibition

- If an operator presentation surface reuses canonical field names such as `trading_mode`, `opens_globally_permitted`, `mode_reasons`, or `open_permission_*`, the value and meaning must match the canonical source exactly.
- If it renames or reshapes canonical information, the derived field must remain semantically equivalent and must not contradict the canonical blocked/allowed conclusion.
- Presentation-specific convenience fields must not reuse canonical names with altered meanings.

### Freshness and fail-closed presentation

- If canonical source status is stale, unreadable, missing, or invalid, the presentation surface must degrade to `UNKNOWN` or `STALE` semantics.
- A presentation surface must not imply OPEN eligibility from stale or missing canonical status.
- A presentation surface must not synthesize "safe to trade" conclusions when canonical authority cannot be verified.

### Foundation-mode boundary preservation

- While `phase == foundation`, operator presentation surfaces must preserve the status-lite authority boundary and must not synthesize CSP authority fields.

## Acceptance Tests

Add four new acceptance tests in the contract:

- `AT-OP1`
  - Given: a presentation surface or derived operator-state document backed by fresh canonical `/api/v1/status`.
  - When: it republishes canonical authority fields or derives convenience summaries from them.
  - Then: reused canonical field names match exactly, and renamed or reshaped fields remain semantically equivalent and non-contradictory.

- `AT-OP2`
  - Given: canonical source status is stale, unreadable, or missing.
  - When: the presentation surface renders operator-facing status.
  - Then: it reports `UNKNOWN` or `STALE` semantics and does not imply OPEN eligibility.

- `AT-OP3`
  - Given: runtime is in foundation mode.
  - When: a presentation surface or derived operator-state document is rendered.
  - Then: it preserves the foundation status-lite authority boundary and does not synthesize CSP authority fields.

- `AT-OP4`
  - Given: canonical runtime state blocks OPEN through mode or latch state.
  - When: a presentation surface computes convenience summaries.
  - Then: no derived field contradicts the canonical blocked state.

## Verification Strategy

The patch should be self-proving through existing status-contract and publisher tests, not just prose.

Expected implementation follow-through:
- contract text and change ledger update
- direct `/status` validator coverage for source precedence and foundation-mode boundary
- tests covering stale or missing source behavior for operator-facing summaries
- tests covering foundation-mode non-authority preservation
- tests proving any `runtime_state.v1` / publisher path is explicitly treated as derived operator state and preserves canonical blocked/open conclusions without requiring wire-format identity
- cross-reference and contract validation scripts green

## Risks

### Risk: accidental schema expansion

If this patch adds too many canonical `/status` fields, it becomes a runtime-schema change instead of an authority-boundary clarification.

Mitigation:
- prefer semantic rules over schema growth
- add fields only if a real enforcement gap is proven

### Risk: operator UI semantics drift from runtime semantics

If dashboards compute their own "trading allowed" interpretations, the system can fail open in human operations.

Mitigation:
- prohibit conflicting canonical field meanings
- require stale or unreadable inputs to degrade to `UNKNOWN` or `STALE`

### Risk: implicit derived-state authority

If a publisher input such as `runtime_state.v1` is treated as authoritative without an explicit derivation contract, downstream tooling can accidentally bypass the canonical `/status` boundary.

Mitigation:
- define derived operator-state documents as non-authoritative
- require tests to prove they preserve canonical blocked/open conclusions

## Rollout Notes

- Land the contract clarification first.
- Then align tests and status-contract tooling.
- If `runtime_state.v1` remains in scope, define it explicitly as derived operator state before changing publisher/dashboard tests.
- Defer any write-capable control-plane work to a later patch once runtime request handling is explicitly designed.

## Proposed Files For The Patch

- Modify: `specs/CONTRACT.md`
- Optional modify if traceability needs alignment: `specs/IMPLEMENTATION_PLAN.md`
- Modify/add tests in:
  - `tests/test_status_contract_model.py`
  - `tests/test_publisher_contract.py`
  - `tests/fixtures/status/**`
  - `tests/fixtures/runtime_state/**`
- If `runtime_state.v1` derivation rules need explicit proof, also review:
  - `python/schemas/runtime_state_v1.schema.json`
  - `dashboard/publisher/transform.py`
  - `dashboard/convex/status_contract.ts`

## Execution Constraint

This work should execute in a clean worktree when local verification is required. If the local tree is dirty, follow the workflow contract's clean-tree or CI-clean-checkout path rather than baking branch-local state into the contract patch.
