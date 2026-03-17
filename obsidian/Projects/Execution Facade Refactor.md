---
status: in-progress
priority: P3
branch:
pr:
started: "2026-03-05"
---

## Current State
PR1-PR4 done. Internal telemetry sink seam landed in `soldier_core`; typed leaf-event pilots still pending. Orchestration consolidation and 1C (risk/venue/infra) remain open. PR #205 review fixes committed — facade lint parser safety guards restored, fixture profile conflicts resolved.

## Key Files
- crates/soldier_core/src/execution/
- obsidian/Upgrades for AI/1/Status 2026-03-05.md

## Debriefs
- [[Execution Facade Refactor 2026-03-17 PR205 Review Fixes]]

## Log
### 2026-03-17
- PR #205 review: fixed facade lint parser safety gaps (nested-brace/module/wildcard guards), removed wrong routing-boundary exclusion for base_gates.rs/intent_assembly.rs, resolved smoke/gate-test fixture conflict

### 2026-03-05
- PR1-PR4 status documented
- PR4 cleanup landed, behavior consolidation follow-up pending
