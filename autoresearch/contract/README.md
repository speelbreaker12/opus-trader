# Contract Autoresearch

Manual-promotion-oriented contract autoresearch scaffold.

This tree is intentionally conservative in v1:

- The harness may generate fixture-local proposals and review artifacts.
- The harness must not write `specs/CONTRACT.md`.
- Human review decisions are recorded in `phase2/review/REVIEW_DECISIONS_<run_id>.json`.
- Accepted-only patch rendering is fail-closed and requires explicit review decisions.

The initial executable slice in this repository provides:

- tracked schemas for findings, proposals, and review decisions
- tracked phase directories and results headers
- contract harness commands for `scaffold`, `status`, and `render-review`

Deferred automation remains deferred:

- phase loop execution
- refresh-common / refresh-fixtures regeneration
- auto-apply / promotion-state management
- live contract writes
