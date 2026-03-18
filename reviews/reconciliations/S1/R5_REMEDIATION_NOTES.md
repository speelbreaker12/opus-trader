# R5 Remediation Notes — Slice 1

- Generated: 2026-02-24
- Baseline head before edits: `f653516`
- Prior P0 fix reference: `efecb6c`

## GAP to Change Mapping

| GAP ID | Severity | Status | Change | File refs | Commit ref |
|---|---|---|---|---|---|
| GAP-S1-005-001 | P0 | VERIFIED | Confirmed `test-helpers` feature wiring already merged; no new code changes required. | `crates/soldier_core/Cargo.toml` | `efecb6c` |
| GAP-S1-005-002 | P1 | REMEDIATED | Added negative-amount regression test for `InvalidAmount` fail-closed guard. | `crates/soldier_core/tests/test_dispatch_map.rs` | uncommitted (working tree on `f653516`) |
| GAP-S1-007-002 | P1 | REMEDIATED | Introduced production-safe `DispatchConsistencyProof::failed()` and gated `unchecked()` behind `#[cfg(any(test, feature = "test-helpers"))]`; migrated production callsites. | `crates/soldier_core/src/execution/dispatch_map.rs`, `crates/soldier_core/src/execution/intent_assembly.rs`, `crates/soldier_core/src/execution/open_runtime.rs` | uncommitted (working tree on `f653516`) |
| GAP-S1-007-001 | P1 | DEFERRED-WITH-DEBT | Kept `build_open_intent_with_assembly()` as public S2 wiring target; updated docs/TODO and registered debt entry `DEBT-S1-007-001`. | `crates/soldier_core/src/execution/open_runtime.rs`, `reviews/reconciliations/S1/DEBT_REGISTER.json` | uncommitted (working tree on `f653516`) |
| GAP-S1-010-001 | P1 | DEFERRED-WITH-DEBT | Registered `AT-040` WEAK_PROOF follow-up as debt `DEBT-S1-010-001`. | `reviews/reconciliations/S1/DEBT_REGISTER.json` | uncommitted (working tree on `f653516`) |

## P2 Gap Disposition

The following P2 gaps were not remediated in R5 code changes and are now explicitly tracked as deferred debt in `reviews/reconciliations/S1/DEBT_REGISTER.json` and sidecar `reviews/reconciliations/S1/R5_REMEDIATION_NOTES.json`:

- `GAP-S1-002-001` -> `DEBT-S1-002-001`
- `GAP-S1-003-001` -> `DEBT-S1-003-003`
- `GAP-S1-004-001` -> `DEBT-S1-004-001`
- `GAP-S1-005-003` -> `DEBT-S1-005-003`
- `GAP-S1-010-002` -> `DEBT-S1-010-002`
- `GAP-S1-012-001` -> `DEBT-S1-012-001`

## Verification Log

Executed verification commands and outcomes:

1. `cargo test -p soldier_core` — PASS
2. `cargo test -p soldier_core -- test_dispatch_map_negative_amount` — PASS (`test_dispatch_map_negative_amount_returns_err`)
3. `cargo check -p soldier_core` — PASS
4. `rg -n "DispatchConsistencyProof::unchecked\(true\)" crates/soldier_core/src crates/soldier_core/tests` — PASS (matches only in test files)
5. `rg -n "DispatchConsistencyProof::unchecked\(false\)" crates/soldier_core/src crates/soldier_core/tests` — PASS (matches only in test files)
6. `./plans/verify.sh quick` — FAIL (pre-existing preflight failure: README/CI parity guard cannot parse `copilot-gate` job)
7. `./plans/verify.sh full` — FAIL (same README/CI parity failure plus pre-existing `plans/tests/test_prd_set_pass.sh` failure under bash 3.2)

Verify artifacts:

- `artifacts/verify/20260224_115929`
- `artifacts/verify/20260224_120032`

## R5 Artifacts

- Sidecar mapping: `reviews/reconciliations/S1/R5_REMEDIATION_NOTES.json`
- Proof graphs:
  - `artifacts/story/S1-005/proof_graph.json`
  - `artifacts/story/S1-007/proof_graph.json`
  - `artifacts/story/S1-010/proof_graph.json`
- Receipt chain (implement step):
  - `.wf/receipts/S1-005/01_implement.json`
  - `.wf/receipts/S1-007/01_implement.json`
  - `.wf/receipts/S1-010/01_implement.json`
