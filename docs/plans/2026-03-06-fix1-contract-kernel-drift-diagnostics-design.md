# Fix 1 Contract Kernel Drift Diagnostics Design

**Date:** 2026-03-06
**Status:** Approved

## Goal

Make stale `docs/contract_kernel.json` failures deterministic and self-remediating so the first failing verify artifact tells the operator exactly how to recover.

## Scope

- Improve the `contract_kernel` failure surface used by `plans/verify_fork.sh`
- Add one regression fixture test for the stale-kernel path
- Keep gate ordering unchanged

## Context

`plans/verify_fork.sh` already runs `scripts/check_contract_kernel.py` as gate `02) contract kernel`. The problem is not missing validation. The problem is that a stale contract hash currently fails with a generic mismatch message that still forces the operator to infer the right rebuild command.

## Approaches Considered

### 1. Shell-only pre-check in `verify_fork.sh`

Add a shell-side comparison for `sources.contract_sha256` before invoking the existing checker.

- Pros: very local change
- Cons: duplicates kernel validation logic in shell and only addresses one drift shape

### 2. Checker-centered diagnosis with verify unchanged

Teach `scripts/check_contract_kernel.py` to recognize stale contract-hash drift and print a specific remediation command while keeping `plans/verify_fork.sh` as the gate entrypoint.

- Pros: keeps logic in one place, preserves gate order, matches the requested minimal scope
- Cons: still narrow; does not generalize to all other preflight ambiguity cases

### 3. New helper or artifact-backed gate result

Add a separate helper or structured artifact surface for contract-kernel remediation.

- Pros: better long-term extensibility
- Cons: broader than the requested fix and higher change risk

## Chosen Design

Use approach 2.

1. Leave the gate order in `plans/verify_fork.sh` unchanged.
2. Update `scripts/check_contract_kernel.py` so that when `sources.contract_sha256` mismatches the current `specs/CONTRACT.md`, it emits the explicit remediation command:

`python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json`

3. Preserve existing validation behavior for non-contract drift cases unless the same explicit remediation can be stated safely.
4. Add one regression shell test under `plans/tests/` that creates a stale-kernel fixture and proves the actionable message is emitted on failure.

## Testing Plan

- Write the new regression test first and verify it fails for the current implementation
- Re-run the new regression test after the checker change and confirm it passes
- Re-run the existing narrow baseline:
  - `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`
  - `bash plans/tests/test_verify_fork_guardrails.sh`

## Non-Goals

- Reordering verify gates
- Introducing a new artifact schema for kernel drift
- Converting unrelated preflight failures into artifact-backed results in this change
