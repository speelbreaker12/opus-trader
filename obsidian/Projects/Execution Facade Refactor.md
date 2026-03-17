---
status: in-progress
priority: P3
branch:
pr:
started: "2026-03-05"
---

## Current State
PR1-PR4 done. Internal telemetry sink seam landed in `soldier_core`; typed leaf-event pilots still pending. Orchestration consolidation and 1C (risk/venue/infra) remain open.

## Key Files
- crates/soldier_core/src/execution/
- obsidian/Upgrades for AI/1/Status 2026-03-05.md

## Log
### 2026-03-17
- Added a crate-private `soldier_core::telemetry` module with `EventSink`, `NoopEvents`, and `Vec<E>` support to create a minimal sink seam for graybox gate tests.
- Wired the telemetry module into `crates/soldier_core/src/lib.rs` without any public re-export or public API churn.
- Added a focused unit test proving the internal sink contract and verified it with a red-green loop before commit.

### 2026-03-05
- PR1-PR4 status documented
- PR4 cleanup landed, behavior consolidation follow-up pending
