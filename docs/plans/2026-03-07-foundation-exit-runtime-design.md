# Foundation Exit Runtime Design

**Date:** 2026-03-07  
**Status:** Approved design  
**Scope:** Runtime-only fix
**Supersedes:** `docs/plans/2026-03-07-foundation-status-authority-transition.md` (withdrawn; do not implement)

## Goal

Close the unresolved foundation-exit blocker by defining when runtime is allowed and required to leave foundation mode, without mixing workflow artifacts or release evidence into the runtime contract.

## Problem

The current schema-selection cleanup only says that `/api/v1/status` is status-lite when `phase == foundation` and CSP-minimum otherwise. That removes wording ambiguity, but it does not define when runtime may stop reporting `phase == foundation`, so two bad paths remain:

- **Fail-open:** an implementation flips `phase` early and starts serving CSP authority keys before PolicyGuard and startup reconciliation are authoritative.
- **Permanent freeze:** runtime is ready, but nothing requires it to exit foundation mode.

## Non-Goals

- Do not make P0 artifacts, preflight gates, PRD state, or AT pass state part of the runtime predicate.
- Do not expand the public `/status` schema with a new `status_mode` field unless a later change proves it is necessary.
- Do not use `/api/v1/status` itself as evidence that foundation exit is legal.

## Approaches Considered

### 1. Docs/tests only

Keep the current `phase != foundation` wording and add validator proof.

**Why not enough:** this is the patch that already landed. It proves schema selection, but not legal transition.

### 2. Runtime-native boot transition

Define foundation exit from internal runtime state only and make `/status` switch surfaces atomically.

**Recommendation:** use this approach.

### 3. New public mode/phase enum

Add a new public status field or an expanded post-foundation phase model.

**Why deferred:** this is broader than needed and increases contract churn before the core transition rule is correct.

## Recommended Design

### Core rule

`foundation_exit_condition` is an internal runtime predicate. It MUST be derived from runtime state and MUST NOT be inferred from `/api/v1/status`.

### Operational definition of PolicyGuard authority

For foundation exit, "PolicyGuard is authoritative" means all of the following:

- Runtime can execute the canonical PolicyGuard mode computation from one coherent input snapshot.
- Missing or stale critical inputs fail closed through the PolicyGuard resolver rather than bypassing it.
- Runtime can populate the PolicyGuard-owned §7.0 status fields from that canonical result.

This condition does **not** require `TradingMode == Active`. Foundation exit may occur into `Active`, `ReduceOnly`, or `Kill` as long as the CSP surface is authoritative and complete.

### Predicate

`foundation_exit_condition` becomes true only when all of the following are true:

- PolicyGuard is initialized and authoritative for `TradingMode`.
- Startup reconciliation has completed successfully.
- The startup open-permission latch has cleared as a result of successful reconciliation.

### While the predicate is false

- `/api/v1/status` MUST remain status-lite.
- `dispatch_enabled` MUST remain `false`.
- `phase` MUST remain `foundation`.
- CSP authority keys MUST NOT be emitted.

### When the predicate becomes true

- `/api/v1/status` MUST atomically switch to the full §7.0 CSP minimum schema.
- No `/api/v1/status` response may expose a mixed status-lite/CSP payload during the switch.
- That surface becomes the canonical authority for dispatch/readiness semantics.
- P0 owner scaffolding remains non-authoritative.

### One-way transition

Foundation exit is a startup/bootstrap boundary, not a general degraded-mode toggle.

After exit:

- WS gaps
- session termination
- stale inputs
- open-permission latch reassertion

must be expressed on the CSP surface using `trading_mode`, `open_permission_blocked_latch`, and related reason codes. They MUST NOT force a return to foundation mode.

## Contract Shape

The contract should say the equivalent of:

1. `foundation_exit_condition` is satisfied only when PolicyGuard is authoritative, startup reconciliation has succeeded, and the startup open-permission latch has cleared as a result of that successful reconciliation.
2. While it is false, `/api/v1/status` MUST remain status-lite and `phase` MUST remain `foundation`.
3. When it becomes true, `/api/v1/status` MUST satisfy the full §7.0 CSP minimum schema.
4. The transition MUST be atomic, and no mixed status-lite/CSP payload may be emitted during the switch.
5. `foundation_exit_condition` MUST be derived from internal runtime state and MUST NOT be inferred from `/api/v1/status`.
6. After exit, later degraded/latch conditions remain on the CSP surface and MUST NOT re-enter foundation mode.

## Proposed Acceptance Coverage

### Existing proof to keep

- Non-foundation status-lite payloads are rejected by `tools/validate_status.py`.
- Foundation payloads containing CSP authority keys are rejected.

### New proof required

- Runtime cannot leave foundation while PolicyGuard is not yet authoritative.
- Runtime cannot leave foundation while startup reconciliation has not yet succeeded.
- Runtime cannot leave foundation while the startup open-permission latch remains set.
- Runtime leaves foundation only after PolicyGuard is authoritative, reconciliation has succeeded, and latch clear is observed.
- No `/api/v1/status` response can expose a mixed status-lite/CSP payload during the transition.
- Once runtime has left foundation, later latch/degraded events do not force re-entry to foundation mode.

## Likely Implementation Seams

- `specs/CONTRACT.md`
- `specs/IMPLEMENTATION_PLAN.md`
- `docs/health_endpoint.md`
- `docs/plans/2026-03-07-foundation-status-authority-transition.md` (replace with a superseded note or rewrite to match this design)
- `tools/validate_status.py`
- `tests/test_validate_status_manifest_override.py`
- `crates/soldier_infra/src/bootstrap.rs`
- `crates/soldier_infra/tests/test_phase0_runtime.rs`
- `plans/prd.json` via a follow-up story or explicit traceability update

## Verification

Minimum verification for the eventual fix:

- `python3 -m pytest tests/test_validate_status_manifest_override.py -q`
- targeted Rust tests for the runtime transition helper/boot path
- `./plans/prd_gate.sh`
- `./plans/prd_audit_check.sh`
- `./plans/verify.sh quick`

## Open Questions

- Whether this should get a new AT identifier or extend existing status-transition coverage.
- Whether the follow-up should stay under `S0-004` or be tracked as a new story. If it remains under `S0-004`, PRD acceptance must be expanded explicitly first because the current story only covers foundation status-lite scope.

## Recommendation

Implement the runtime-native boot transition rule. Retire the withdrawn validator-only `phase != foundation` plan, and do not accept that cleanup as a full fix for the blocker.
