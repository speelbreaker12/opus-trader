---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
status: active
---

## Why This Exists
- Session ended after converting the Upgrade 2A post-only seam, while the broader execution-facade refactor project remains in flight.

## Current Pointer
- Branch: `project/execution-facade-refactor`
- Commit: `5c6f972c`
- Scope: `execution/post_only_guard.rs` is now on the leaf event-sink pattern, the Upgrade 2A checklist marks `post-only` as `PASS`, and the next likely 2A targets are `execution/inventory_skew.rs` or `execution/preflight.rs`.

## Must Read
- [[Execution Facade Refactor]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Post-Only Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Pricer Seam]]
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)

## Next Steps
1. Convert `crates/soldier_core/src/execution/inventory_skew.rs` using the same crate-private event seam plus graybox/wrapper parity pattern.
2. Convert `crates/soldier_core/src/execution/preflight.rs` after that, keeping the same leaf-only 2A boundary and not pulling 2B orchestration telemetry forward.
3. Keep the next Obsidian note touch focused on the next 2A leaf instead of reopening already-anchored commit history.

## Resume Command
```bash
git status --short
cargo test -p soldier_core --lib post_only_guard
rg -n "inventory skew|preflight|FAIL" docs/codebase/upgrade2_graybox_telemetry_checklist.md crates/soldier_core/src/execution crates/soldier_core/src/risk
```

## Notes
- Verification completed for this slice so far: `cargo fmt --all -- --check` and `cargo test -p soldier_core --lib post_only_guard`.
- `./plans/verify.sh quick` reached `artifacts/verify/20260317_121242` and stopped on the unrelated `docs/contract_kernel.json` drift, not on the post-only seam itself.
- This Obsidian handoff complements, but does not replace, `plans/pause.md` or workflow-specific handoff artifacts when those are required.
