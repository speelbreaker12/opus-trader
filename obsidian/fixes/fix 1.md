# Fix 1 - Contract Kernel Drift Diagnostics

## Context

This note captures the operational lesson from early quick/full verify failures in a dirty tree: reproduce the failing gate directly before changing code, then improve the diagnosis instead of trusting partial streamed preflight output.

## Verified Repo State

- `plans/verify_fork.sh` already runs a dedicated `contract_kernel` gate when `docs/contract_kernel.json` is present.
- `scripts/check_contract_kernel.py` and `scripts/build_contract_kernel.py` already exist, so the gap is diagnosis quality rather than missing tooling.

## Proposed Improvement

Add a small preflight diagnostic in `plans/verify_fork.sh` that recognizes stale `docs/contract_kernel.json` versus `specs/CONTRACT.md` and emits one explicit remediation command before the broader verify run.

## Smallest Validation

Add a fixture that mutates `specs/CONTRACT.md`, leaves `docs/contract_kernel.json` stale, and asserts the gate suggests:

`python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`

## Expected Benefit

A stale-kernel failure becomes a one-step diagnosis instead of a manual investigation through noisy preflight output.

## Best Follow-up Story

Add deterministic kernel-drift diagnostics to verify/preflight so stale contract metadata is called out immediately and consistently.

## Upgrade Candidates

1. Add a smoke test for the remediation message in `plans/tests/test_contract_kernel_drift_message.sh`.
2. Add a narrow Rust test for `BuildCreatedIntentRecordError::UnsupportedLifecycleIntent` so the error contract is asserted directly instead of through `Debug` output.
3. Convert the remaining streamed preflight guard failures into direct artifact-backed gate results so quick verify shows stable per-guard pass/fail status.
