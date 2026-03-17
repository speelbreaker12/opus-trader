---
status: in-progress
priority: P1
branch: story/remediation-order-v4/r01-r05-contract-fixes
pr: 207
started: 2026-03-16
---

## Current State

PR 207 rebased onto main. Duplicate AT-1239 fixed. Autoresearch tests next, then PR-gate evidence path.

## Key Files
- `autoresearch/contract/render_review.py`
- `autoresearch/skills/harness.sh`
- `autoresearch/tests/test_contract_render_review.py`
- `autoresearch/tests/test_contract_harness_cli.py`

## Debriefs
- None yet.

## Log
### 2026-03-16
- Fixed accepted-only contract patch rendering to fail closed when the live `specs/CONTRACT.md` hash drifts from recorded batch provenance.
- Fixed baseline scoring so valid JSON from `evaluate.py --json` is recorded even when the evaluator exits non-zero for an imperfect score.
- Added regression coverage for both failure modes in the autoresearch contract and harness tests.
- Folded PR #208 render_review.py IndexError guard into #207 branch (cherry-pick, harness.sh conflict resolved — HEAD's tmpfile pattern already had the set-e fix).
- Rebased PR #207 onto main (10 commits, 17 conflicts resolved, 0 markers remaining).
- Reviewed CONTRACT.md/prd.json/contract_kernel.json as contract set. Found and fixed duplicate AT-1239 in S7-002.
- contract_kernel.json line numbers are stale — needs regeneration post-merge.

