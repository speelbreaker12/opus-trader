---
status: in-progress
priority: P1
branch: hotfix/facade-boundary-doc-blocks-lockdown
base: main
pr:
started: "2026-03-21"
worktree: $WORKTREES/wt_facade_boundary_doc_blocks_lockdown
aliases:
  - Facade Boundary + Docs Hotfix
keywords:
  - facade
  - boundary
  - docs
  - execution
  - soldier_core
  - soldier_infra
scope_paths:
  - crates/soldier_core/src/execution/mod.rs
  - crates/soldier_core/src/risk/**
  - crates/soldier_core/src/venue/**
  - crates/soldier_core/tests/**
  - crates/soldier_infra/src/**
  - crates/soldier_infra/tests/**
  - plans/soldier_infra_facade_symbols.txt
  - obsidian/Projects/Facade Boundary Doc Blocks Lockdown.md
  - obsidian/Debriefs/Facade Boundary Doc Blocks Lockdown *.md
---

## Current State

In progress on branch `hotfix/facade-boundary-doc-blocks-lockdown` in worktree `$WORKTREES/wt_facade_boundary_doc_blocks_lockdown`. The facade/doc-block cleanup is implemented: `infra_bootstrapped()` now routes through the `soldier_infra` facade, the root doc blocks are normalized, and the new structure proof passes. Local quick verification is blocked only by the pre-existing workflow test `plans/tests/test_pr_review_gate_hook.sh`, which also fails unchanged on clean `main`.

## Commits
- `pending` — 2026-03-21 — bootstrap the broader facade/doc-block hotfix lane and finish the remaining facade-boundary cleanup from fresh `main`.

## Key Files
- crates/soldier_core/src/execution/mod.rs
- crates/soldier_core/src/risk/mod.rs
- crates/soldier_core/src/venue/mod.rs
- crates/soldier_infra/src/api.rs
- crates/soldier_infra/src/lib.rs
- crates/soldier_infra/tests/test_soldier_infra_facade_public.rs
- plans/soldier_infra_facade_symbols.txt

## Debriefs
- [[Facade Boundary Doc Blocks Lockdown 2026-03-21]]

## Log
### 2026-03-21
- Created a dedicated Obsidian owner for the broadened facade-boundary hotfix after the user chose to normalize the adjacent `execution/mod.rs` doc block in the same lane.
- Scoped this branch to the target facade/doc-block files, related tests, and this project's tracking docs before implementation.
- Expanded the scope to include `plans/soldier_infra_facade_symbols.txt` after live quick verification proved the new public facade export must update the checked allowlist in the same atomic fix.
- Added a red-green proof for `infra_bootstrapped()` so `soldier_infra/src/lib.rs` stays a pure facade root while `api.rs` re-exports the symbol.
- Moved `infra_bootstrapped()` into `bootstrap.rs`, re-exported it from `api.rs`, normalized the `execution` / `risk` / `venue` / `soldier_infra` facade-root doc blocks, and updated the infra facade allowlist.
- Verified targeted Rust/facade checks successfully; `./plans/verify.sh quick` now fails only on the unrelated `plans/tests/test_pr_review_gate_hook.sh` workflow test, and that same test fails on clean `main`.
