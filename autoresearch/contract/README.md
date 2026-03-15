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
- contract harness commands for `scaffold`, `status`, `phase1 run|baseline|eval`, `phase2 run|baseline|eval`, `refresh-common|refresh-fixtures|refresh-all`, and `render-review`
- fail-closed Phase 2 validation for cross-file integrity, weak-normative evidence presence, mechanical span resolution, contradiction heuristics, and review-package rendering
- deterministic refresh of shared context, snapshot fixtures, and manifest hashes
- `results.tsv` records execution-check rows for `run` and scored rows for `baseline`; `eval` scores existing output directories without mutating results history

Deferred automation remains deferred:

- richer structural scoring beyond the current contract-specific evaluator rules
- auto-apply / promotion-state management
- live contract writes
