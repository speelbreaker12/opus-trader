---
project: "[[Execution Facade Refactor]]"
date: "2026-03-17"
status: active
---

## Why This Exists
- Session completed the remaining Upgrade 2A risk leaves (`pending exposure` and `exposure budget`) so seam behavior now matches the established 2A event-sink rollout pattern.

## Current Pointer
- Branch: `project/execution-facade-refactor`
- Commit: `pending` (working-tree checkpoint)
- Scope: `risk/pending_exposure.rs` and `risk/exposure_budget.rs` are now pass-complete in the Upgrade 2A checklist; next scope is `execution/group.rs` and `execution/build_order_intent.rs` for Upgrade 2B.

## Must Read
- [[Execution Facade Refactor]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Seam]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Risk Exposure Seams]]
- [[Execution Facade Refactor 2026-03-17 Upgrade 2A Margin Gate Handoff]]
- [docs/codebase/upgrade2_graybox_telemetry_checklist.md](../../docs/codebase/upgrade2_graybox_telemetry_checklist.md)

## Next Steps
1. Start Upgrade 2B by applying the same event-seam plus graybox/parity pattern to `execution/group.rs` and `execution/build_order_intent.rs`.
2. Keep the next checkpoint focused on one seam-at-a-time to preserve low-risk handoff granularity.
3. Re-run `./plans/verify.sh full` on a clean checkout before any pass flip in Upgrade 2B.

## Resume Command
```bash
git status --short
rg -n "pending exposure|exposure budget|2B|Upgrade 2" docs/codebase/upgrade2_graybox_telemetry_checklist.md
```

## Notes
- Verification evidence captured in this session: `cargo test -p soldier_core --lib` (`688 passed`).
- This handoff complements `plans/pause.md` and the project note for all workflow-required tracking context.
