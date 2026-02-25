# R5 Remediation Notes - Slice 0

- Generated: 2026-02-24
- Working head: `f653516a57427f52dbeabed6779053896562c472`

## GAP to Change Mapping

| GAP ID | Severity | Status | Change | File refs |
|---|---|---|---|---|
| GAP-S0-003-001 | P0 | FIXED | Runtime state load now fails closed (`KILL`) when state file is missing after prior initialization, with explicit error reason. | `stoic-cli:163-169`, `stoic-cli:205-216`, `stoic-cli:301-325` |
| GAP-S0-003-002 | P1 | FIXED | Added deletion regression test proving kill latch remains fail-closed when runtime state file disappears mid-session. | `crates/soldier_infra/tests/test_phase0_runtime.rs:845-903` |
| GAP-S0-002-001 | P1 | FIXED | Closed scope bypass by rejecting forbidden scopes (`all`, `transfer`, `withdraw`, `margin`) and rejecting successful withdraw probe results. Added dedicated `scopes=["all"]` test. | `stoic-cli:996-1012`, `crates/soldier_infra/tests/test_phase0_runtime.rs:309-368` |
| GAP-S0-004-002 | P1 | FIXED | Status test now asserts `contract_version` value. | `crates/soldier_infra/tests/test_phase0_runtime.rs:537-540`, `crates/soldier_infra/tests/test_phase0_runtime.rs:610-613` |
| GAP-S0-004-003 | P1 | FIXED | Status test now asserts `build_id` value propagation. | `crates/soldier_infra/tests/test_phase0_runtime.rs:533-536`, `crates/soldier_infra/tests/test_phase0_runtime.rs:606-609` |
| GAP-S0-004-004 | P1 | FIXED | Added health command runtime test (healthy and unhealthy). | `crates/soldier_infra/tests/test_phase0_runtime.rs:632-696` |
| GAP-S0-004-005 | P1 | FIXED | Added REDUCE_ONLY coverage asserting `is_trading_allowed=false`. | `crates/soldier_infra/tests/test_phase0_runtime.rs:547-588` |

## Verification Log

1. `python3 -m py_compile stoic-cli` - PASS
2. `cargo test -p soldier_infra --test test_phase0_runtime` - PASS (20 passed)
3. `./plans/verify.sh quick` - FAIL (pre-existing preflight guard failure in README/CI parity parser)

Verify artifact:

- `artifacts/verify/20260224_122958`

## R5 Artifacts

- Sidecar mapping: `reviews/reconciliations/S0/R5_REMEDIATION_NOTES.json`
- Updated ledgers:
  - `reviews/reconciliations/S0/S0-002_reconciliation.md`
  - `reviews/reconciliations/S0/S0-003_reconciliation.md`
  - `reviews/reconciliations/S0/S0-004_reconciliation.md`
- Proof graph:
  - `artifacts/story/S0-003/proof_graph.json`
