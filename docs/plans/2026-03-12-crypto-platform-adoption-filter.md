# Crypto-Platform Adoption Filter

Date: 2026-03-12

## Purpose

This document is the high-level master plan for what `opus-trader` should copy, adapt, ignore, or defer from `tmatic-trading/crypto-platform`.

It is intentionally not a second product roadmap. The existing roadmap remains:
- [IMPLEMENTATION_PLAN.md](../../specs/IMPLEMENTATION_PLAN.md)
- [CONTRACT.md](../../specs/CONTRACT.md)

This document is a decision filter that keeps adoption disciplined and contract-aligned.

## Decision Rule

Adopt only features that:
- improve operator clarity or operational throughput at the current constraint
- do not weaken fail-closed execution semantics
- do not create a second control plane outside canonical `/api/v1/status`
- can be mapped cleanly into the current Deribit-first, contract-first architecture

Reject or defer features that:
- move authority away from PolicyGuard, latch semantics, or canonical status
- broaden venue or product scope before the current engine is trustworthy
- optimize for app convenience over execution correctness

## Source Comparison Summary

`crypto-platform` is strongest in:
- operator-facing UX
- quick onboarding
- multi-exchange breadth
- bot-management convenience
- immediate usability as a trading workstation

`opus-trader` is strongest in:
- contract-backed execution semantics
- replay, reconciliation, and idempotency discipline
- explicit fail-closed runtime safety
- verification and acceptance-test rigor
- canonical status authority and release gating

The right adoption strategy is:
- borrow operator usability
- keep execution authority and runtime semantics local to `opus-trader`

## Master Table

| Area | Decision | Why |
|---|---|---|
| Testnet-first onboarding | Copy | High operator value, low architectural risk |
| Read-only operator visibility | Copy | Fits current dashboard/status pipeline without weakening runtime authority |
| Bot lifecycle UX concepts | Adapt | Useful, but must become governed strategy/runtime units |
| Historical accounting and results views | Adapt | Valuable, but must sit on top of WAL/replay/contract truth, not replace it |
| Manual control semantics (design only) | Adapt | Useful only if routed through contract-compliant control-plane semantics; writable APIs deferred |
| Multi-exchange support | Defer | Too much inventory before Deribit-first runtime is proven |
| Desktop-monolith app architecture | Ignore | Wrong center of gravity for this codebase |
| Editable live script workflow | Ignore | Conflicts with reproducibility and contract-governed change control |
| SQLite as execution truth | Ignore | Conflicts with WAL/replay/reconciliation model |

## Copy

These should be adopted with minimal semantic change.

### 1. Testnet-first onboarding

Adopt:
- clear environment bootstrap flow
- credential setup path
- testnet-first operating guidance
- operator feedback for transport connectivity (connected / disconnected) and authority freshness (`UNKNOWN` / `STALE` per contract vocabulary)

Why:
- high operator leverage
- no need to change runtime semantics
- directly reduces onboarding friction

### 2. Read-only operator visibility

Adopt:
- positions
- balances
- orders
- recent trades
- results summaries

How:
- expose through the status/dashboard path
- do not invent a second authority surface
- keep all runtime authority bound to canonical status and runtime-owned evidence

### 3. Immediate operator clarity

Adopt:
- fast visibility into blocked state
- simple display of why the system is not opening risk
- quick status at startup and reconnect boundaries

Why:
- this complements existing `mode_reasons`, latch semantics, and health/status surfaces

## Adapt

These are worth taking, but only in `opus-trader` form.

### 1. Bot lifecycle UX

Adapt from:
- create / suspend / resume / delete / inspect

Into:
- governed strategy instance lifecycle
- explicit config/version ownership
- contract-aware runtime status
- no live untracked script editing

Guardrail:
- strategy units must remain subordinate to canonical execution and verification rules

### 2. Historical accounting and operator results

Adapt from:
- SQLite-backed trade and funding tracking

Into:
- contract-backed reporting built on WAL, replay, reconciliation, and runtime evidence
- operator views for fills, funding, attribution, and incidents

Guardrail:
- reporting storage must not become execution truth

### 3. Manual control semantics (design only)

Adapt from:
- trader-facing control affordances

Into:
- contract-compliant owner request semantics (cancel, reduce-only, halt, reconcile)
- explicit boundary definitions between request and authority
- no bypass around PolicyGuard or open-permission latches

Scope boundary:
- This item covers *designing* the request/authority semantics only.
- Writable operator control APIs are deferred — see [Defer §2](#2-writable-operator-control-apis) below.

Guardrail:
- request is not authority
- runtime remains authority

### 4. Future venue abstraction

Adapt only later:
- exchange adapter patterns
- normalized market/account views

Guardrail:
- only after Deribit-first runtime, status, and operator plane are stable

## Ignore

These should not guide architecture.

### 1. Desktop-monolith UI

Do not copy:
- Tkinter-centered runtime orchestration
- UI thread as operational center
- app-first trading workstation shape

Reason:
- this repo already has the beginnings of a service + publisher + dashboard direction
- a desktop-first monolith would work against the contract and current stack

### 2. Editable live strategy scripts

Do not copy:
- strategy authoring as ad hoc local script mutation inside the operator app

Reason:
- weak reproducibility
- weak reviewability
- high risk of drift from contract-enforced behavior

### 3. SQLite-centered operational truth

Do not copy:
- treating a local relational store as the primary operational source of execution truth

Reason:
- execution truth here must remain WAL/replay/reconcile-driven

### 4. Multi-exchange-first scope

Do not copy:
- broad connector count as a primary milestone

Reason:
- this increases WIP and rework before the current safety kernel is fully proven

## Defer

These are legitimate future candidates, but they should not enter the near-term contract or roadmap yet.

### 1. Multi-exchange support

Defer until:
- Deribit-first micro-live gate is green
- operator plane is stable
- core runtime and status semantics are not the main constraint

### 2. Writable operator control APIs

Defer until:
- owner request semantics are explicitly contracted
- request/ack/audit model is defined
- stale/duplicate/replay behavior is proven

### 3. Rich strategy-instance management

Defer until:
- versioned strategy packaging model exists
- runtime ownership boundaries are explicit
- configuration promotion and rollback semantics are defined

## Adoption Horizons

This maps adopted items into the existing plan rather than inventing a second roadmap. These horizons are sequenced relative to the existing [IMPLEMENTATION_PLAN.md](../../specs/IMPLEMENTATION_PLAN.md) phases (Phase 1–4, Slices 1–14) and do not replace them.

### Horizon 1 (during or after IMPLEMENTATION_PLAN Phase 1–2)

Focus:
- testnet-first onboarding
- read-only visibility
- startup clarity
- foundation-mode-safe owner surfaces

Candidate outcomes:
- better docs and operator bootstrap
- read-only dashboard/status views
- explicit `STALE` or `UNKNOWN` operator summaries

### Horizon 2 (during or after IMPLEMENTATION_PLAN Phase 2–3)

Focus:
- canonical operator plane
- contract-compliant owner request semantics (design only — writable APIs deferred)
- governed strategy instance lifecycle beginnings

Candidate outcomes:
- authoritative dashboard behavior based on canonical `/api/v1/status`
- halt/reduce-only/reconcile request semantics defined
- first governed runtime-unit lifecycle model

### Horizon 3 (during or after IMPLEMENTATION_PLAN Phase 3–4)

Focus:
- results, attribution, incident visibility
- replay/evidence-backed operator analytics

Candidate outcomes:
- reporting views
- evidence-linked incident timelines
- richer operator diagnostics

### Horizon 4 (after IMPLEMENTATION_PLAN Phase 4)

Focus:
- governance surfaces
- promotion and canary visibility
- only then evaluate broader platform expansion

Candidate outcomes:
- operator governance dashboards
- rollout/rollback visibility
- multi-strategy fleet views

## Guardrails

These are the hard “do not dilute the engine” rules.

### Guardrail 1

Operator convenience must not create an alternate authority path.

Enforcement:
- canonical runtime truth remains `/api/v1/status`
- presentation layers are non-authoritative

Planned traceability: CONTRACT.md §7.0 status authority matrix; pending AT-OP1 (semantic equivalence), AT-OP4 (no contradiction of canonical blocked state) once landed

### Guardrail 2

No adopted feature may bypass fail-closed execution gates.

Enforcement:
- PolicyGuard
- open-permission latch
- runtime binding and status authority rules

Planned traceability: CONTRACT.md §Acceptance Test Isolation Requirements (all TRIP/NON-TRIP pairs); pending AT-OP2 (stale source degrades) once landed

### Guardrail 3

Adoption must be Deribit-first until the current kernel is proven.

Enforcement:
- no multi-exchange-first roadmap entries
- no connector-driven widening before stability evidence exists

Traceability: IMPLEMENTATION_PLAN.md Deribit-first scope constraint

### Guardrail 4

Usability features must reduce operator ambiguity, not hide it.

Enforcement:
- stale or missing source data must surface as `UNKNOWN` or `STALE`
- no convenience summary may imply opens are allowed when canonical status cannot prove that

Planned traceability: CONTRACT.md §7.0 freshness semantics; pending AT-OP2 (`UNKNOWN`/`STALE` degradation), AT-OP3 (foundation-mode boundary) once landed

## Trigger Conditions For Revisit

Revisit deferred items only when the corresponding constraint changes.

### Revisit multi-exchange

Only when:
- Deribit-first operations are stable
- operator plane is no longer the main bottleneck
- additional venue breadth has a concrete business case

### Revisit writable controls

Only when:
- operator request semantics are contracted
- audit and replay behavior are specified
- request handling cannot weaken safety semantics

### Revisit richer strategy management

Only when:
- strategy packaging/versioning is explicit
- runtime promotion and rollback model exists
- contract and PRD flow can absorb the additional surface cleanly

## Recommended Next Documents

In order:
1. [Operator surface contract design](2026-03-12-operator-surface-contract-design.md)
2. [Operator surface implementation plan](2026-03-12-operator-surface-contract.md)
3. Contract-aligned owner/dashboard surface spec (not yet written)
4. Governed strategy instance model (not yet written)

## Execution Note

This adoption filter should guide future contract and PRD changes. It should not be used to bypass the existing roadmap or to justify broad scope expansion without contract support.
