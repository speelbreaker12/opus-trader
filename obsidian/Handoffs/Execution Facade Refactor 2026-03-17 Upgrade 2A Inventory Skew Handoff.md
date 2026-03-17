---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
status: active
---

## Why This Exists
- Session paused after converting the Upgrade 2A inventory-skew seam, and the broader execution-facade refactor project remains in flight.

## Current Pointer
- Branch: `project/execution-facade-refactor`
- Commit: `pending`
- Scope: `execution/inventory_skew.rs` now uses the leaf event-sink pattern, the Upgrade 2A checklist marks `inventory skew` as `PASS`, and the next likely 2A target is `execution/preflight.rs`.

## Must Read
- [[Execution Facade Refactor]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Inventory Skew Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Post-Only Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Pricer Seam]]
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)

## Next Steps
1. Convert `crates/soldier_core/src/execution/preflight.rs` using the same crate-private event seam plus graybox/wrapper parity pattern.
2. Convert `crates/soldier_core/src/risk/margin_gate.rs` after preflight, keeping the same leaf-only 2A boundary and not pulling 2B orchestration telemetry forward.
3. Backfill this handoff/project/debrief commit field from `pending` to the landed hash on the next project-note touch.

## Resume Command
```bash
git status --short
cargo test -p soldier_core --lib inventory_skew
rg -n "preflight|margin|pending exposure|exposure budget|FAIL" docs/codebase/upgrade2_graybox_telemetry_checklist.md crates/soldier_core/src/execution crates/soldier_core/src/risk
```

## Notes
- Verification completed for this slice: `cargo test -p soldier_core --lib inventory_skew`, `cargo fmt --all`, `cargo fmt --all -- --check`, and `git diff --check`.
- `./plans/verify.sh quick` was not rerun in this session because the repo still has the previously noted unrelated contract-kernel drift outside this slice.
- This Obsidian handoff complements, but does not replace, `plans/pause.md` or workflow-specific handoff artifacts when those are required.
