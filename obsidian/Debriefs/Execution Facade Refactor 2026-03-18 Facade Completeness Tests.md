---
project: "[[Execution Facade Refactor]]"
date: "2026-03-18"
---

## Commits
- `pending` — add facade completeness tests for `idempotency`, `recovery`, and `status_codes`.

## What Changed
- Added `facade_completeness_contract_tests.rs` for idempotency (4 symbols) and recovery (5 symbols).
- Added inline `facade_completeness_contract_tests` module in `status_codes.rs` (11 symbols).
- All 7 soldier_core subsystems + soldier_infra crate root now have compile-time facade reachability proof.

## Decisions
- `status_codes` test is inline (single-file module, no directory to put a separate file in).
- `store` and `deribit` do not need separate tests — covered by soldier_infra crate-root facade test.
- Facade doc block design spec written: C-split rule (mod.rs overview + api.rs contract), non-brittle test patterns, conceptual Public groups.
