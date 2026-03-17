---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
status: completed
---

## Why This Exists
- Completed `risk/margin_gate.rs` as the Upgrade 2A margin checkpoint and handed off next risk leaves.

## Current Pointer
- Branch: `project/execution-facade-refactor`
- Commit: working-tree checkpoint at time of handoff
- Scope: 2A margin gate leaf now uses the event-seam pattern and passes by checklist.

## Must Read
- [[Execution Facade Refactor]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Seam]]
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)

## Next Steps
1. Convert `crates/soldier_core/src/risk/pending_exposure.rs`.
2. Convert `crates/soldier_core/src/risk/exposure_budget.rs`.

## Resume Command
```bash
git status --short
rg -n "margin|pending exposure|exposure budget" docs/codebase/upgrade2_graybox_telemetry_checklist.md
```

## Notes
- This checkpoint was followed by the Upgrade 2A risk exposure seam handoff.
