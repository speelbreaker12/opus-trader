---
project: "[[Execution Facade Refactor]]"
date: "2026-03-18"
status: complete
---

## What Was Done
- Fixed P0 duplicate `tracing::warn!` in WAL nonblocking bump path
- Removed dead `build_order_intent_internal` function
- Added 3 graybox tests for `build_order_intent_internal_with_events`
- Fixed 15x `needless_return` clippy lints across all EventSink seam bump functions
- Fixed `items_after_test_module` in `exposure_budget.rs`
- Fixed pre-existing test deadlock: 4 engine decision tests used raw `METRICS_TEST_LOCK.lock()` instead of `begin_metrics_test()`, causing deadlock under parallel test execution
- Flipped Upgrade 2 checklist status FAIL→PASS
- Closed stale Risk Exposure Seams handoff

## Verification
- `verify.sh full` passes clean
- All 694 lib tests pass
- Zero clippy warnings
