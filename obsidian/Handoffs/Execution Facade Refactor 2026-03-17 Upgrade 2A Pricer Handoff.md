---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
status: active
---

## Why This Exists
- Explicit user-requested handoff after the Upgrade 2A pricer seam batch.

## Current Pointer
- Branch: `main`
- Commit: `pending`
- Scope: `execution/pricer.rs` is now on the leaf event-sink pattern, the Upgrade 2A checklist marks `pricer` as `PASS`, and the next likely 2A targets are `execution/post_only_guard.rs` or `execution/inventory_skew.rs`.

## Must Read
- [[Execution Facade Refactor]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Pricer Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Quantize Seam]]
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)

## Next Steps
1. Replace the `pending` commit reference in the project/debrief/handoff notes with the actual hash from this batch the next time the tracking notes are touched.
2. Convert `crates/soldier_core/src/execution/post_only_guard.rs` using the same crate-private event seam plus graybox/wrapper parity pattern.
3. Keep `execution/group.rs` and orchestration `build_order_intent.rs` telemetry in Upgrade 2B; do not pull them back into 2A.

## Resume Command
```bash
git status --short
cargo test -p soldier_core --lib pricer
rg -n "post-only|inventory skew|FAIL" docs/codebase/upgrade2_graybox_telemetry_checklist.md crates/soldier_core/src/execution
```

## Notes
- Verification completed for this slice: `cargo fmt --all -- --check` and `cargo test -p soldier_core --lib pricer`.
- This Obsidian handoff complements, but does not replace, `plans/pause.md` or workflow-specific handoff artifacts when those are required.
