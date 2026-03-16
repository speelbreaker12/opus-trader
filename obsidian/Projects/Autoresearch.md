---
status: in-progress
priority: P1
branch: story/remediation-order-v4/r01-r05-contract-fixes
pr: 207
started: 2026-03-16
---

## Current State

Refreshing PR 207 calibration blockers in the autoresearch workflow.

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
