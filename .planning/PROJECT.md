# Opus Trader

## What This Is

Opus Trader is a contract-first automated trading engine focused on structural arbitrage safety and deterministic execution. This repo contains the Rust execution/risk kernel, infrastructure durability layers (WAL/TLSM), and workflow verification harness that must stay aligned with the normative contract before any live-trading claims.

## Core Value

Every OPEN-risk decision must be fail-closed, deterministic, and provable with tests and artifacts.

## Requirements

### Validated

- [x] Phase-0 operational baseline artifacts and checks are present and enforced by verify gates.

### Active

- [ ] REQ-1: All exchange dispatch routes through the single dispatch chokepoint.
- [ ] REQ-2: WAL/intent ledger prevents duplicates across crash/restart/reconnect with deterministic evidence.
- [ ] Close phase-drift gaps across contract/docs/verify/TLSM/smoke (items 1-9 in `plans/phase_drift_closure_plan.md`).

### Out of Scope

- Strategy alpha tuning and optimization loops before foundation safety/durability proofs are complete.
- UI/dashboard expansion beyond required owner/operator status surfaces in current contract phases.
- Broad storage migrations that break WAL backward compatibility in this tranche.

## Context

- Canonical runtime contract is `specs/CONTRACT.md` (v5.2) with fail-closed safety rules.
- Active roadmap source is `docs/ROADMAP.md` (via `.planning/ROADMAP.md` symlink), currently Phase 1 Foundation.
- Current planning inventory under `.planning/phases/01-foundation/` has 2 execution plans and 0 summaries.
- Current implementation priority is phase-drift closure before broader feature expansion.

## Constraints

- **Contract**: `specs/CONTRACT.md` is normative for behavior and safety acceptance.
- **Safety**: No weakening of fail-closed guards, gates, or tests.
- **Verification**: Changes must stay compatible with `./plans/verify.sh quick` and `./plans/verify.sh full`.
- **Compatibility**: Preserve runtime/WAL semantic compatibility unless an explicit migration plan is included.

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Use `.planning/` as the GSD control plane for this repo | Enables structured planning/execution with durable state | ✓ Good |
| Keep `docs/ROADMAP.md` as canonical roadmap via `.planning/ROADMAP.md` symlink | Avoids split-brain roadmap sources | ✓ Good |
| Prioritize drift-closure sequence before new breadth features | Reduces rework and contract divergence | ✓ Good |

---
*Last updated: 2026-03-04 after GSD bootstrap for repository planning state*
