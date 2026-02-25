# R5B_FIX_LOG — Slice 1

Status date: 2026-02-24
Scope: all six S1 receipts (`reviews/reconciliations/S1/receipts/*.json`)

## R5B-01 (P1): Attest production open-order call chain before claiming AT-920 wiring fixes
- status: FIXED
- disposition: fixed
- owner: Runtime owner (2026-02-24)
- commands and outputs:
  - `rg -n --glob '!**/tests/**' "build_open_order_intent_runtime\\s*\\(" crates/soldier_core/src`
  - `rg -n --glob '!**/tests/**' "assemble_sizing\\s*\\(|evaluate_assembled_pipeline\\s*\\(|evaluate_intent_pipeline\\s*\\(" crates/soldier_core/src`
  - `rg -n --glob '!**/tests/**' "validate_and_dispatch\\s*\\(" crates/soldier_core/src/execution`
  - `cargo test -p soldier_core --test test_open_runtime_wiring test_runtime_wiring_margin_kill_rejects_before_open_dispatch -- --exact --nocapture`
  - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`
- proof:
  - Open-order runtime path is live: `build_open_order_intent_runtime` in `open_runtime.rs` is called from production flow.
  - The open-order call chain enters `assemble_sizing`/`evaluate_assembled_pipeline` in `intent_assembly.rs`, which eventually calls `validate_and_dispatch` in `dispatch_map.rs`.
  - Both required regression tests passed.
- selected output:
  - `rg` shows non-test callsites including `open_runtime::build_open_order_intent_runtime`, `pipeline::evaluate_intent_pipeline`, and `dispatch_map::validate_and_dispatch`.
  - `cargo test ...test_runtime_wiring_margin_kill_rejects_before_open_dispatch`: `1 passed; 0 failed`.
  - `cargo test ...test_at920_no_dispatch_on_mismatch`: `1 passed; 0 failed`.

## R5B-02 (P1): Make `DispatchConsistencyProof::unchecked()` non-callable in production code paths
- status: FIXED
- disposition: fixed
- owner: Runtime owner (2026-02-24)
- commands and outputs:
  - `if rg -n --glob '!**/tests/**' --glob '!crates/soldier_core/src/execution/dispatch_map.rs' "DispatchConsistencyProof::unchecked\\(" crates/soldier_core/src; then echo \"unexpected non-test callsite for DispatchConsistencyProof::unchecked()\"; exit 1; fi`  
    output: no matches
  - `rg -n --glob '!**/tests/**' --glob '*.rs' "DispatchConsistencyProof::from_validated\\(|DispatchConsistencyProof::no_contracts\\(|DispatchConsistencyProof::failed\\(" crates/soldier_core/src`  
    output: 8 matches in production modules
  - `rg -n -U --glob '*.rs' "\\#\\[cfg\\(test\\)\\]\\s*\\n\\s*pub fn unchecked\\(" crates/soldier_core/src/execution/dispatch_map.rs`  
    output: one match at `dispatch_map.rs:133-134`
  - `rg -n --glob '*.rs' "DispatchConsistencyProof::unchecked\\(" crates/soldier_core/tests/common/mod.rs crates/soldier_core/tests/test_open_runtime_wiring.rs crates/soldier_core/tests/test_base_gates.rs crates/soldier_core/tests/test_intent_pipeline.rs crates/soldier_core/tests/test_recorded_before_dispatch_gate.rs crates/soldier_core/tests/test_intent_id_propagation.rs crates/soldier_core/tests/test_gate_ordering.rs crates/soldier_core/tests/test_rejection_side_effects.rs crates/soldier_core/tests/test_reject_reason.rs crates/soldier_core/tests/test_label.rs crates/soldier_core/tests/test_missing_config.rs crates/soldier_core/tests/test_intent_determinism.rs crates/soldier_core/tests/test_dispatch_map.rs`  
    output: no matches (all callsites migrated)
  - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`  
    output: `1 passed; 0 failed`
  - `if rg -n --glob '!**/tests/**' --glob '*.rs' "test-helpers|all_passed\\(" crates/soldier_core/src crates/soldier_core/tests crates/soldier_core/Cargo.toml; then echo \"unexpected all_passed/test-helpers production-path remnants remain\"; exit 1; fi`  
    output: no matches
  - `rg -n "gate_results_all_passing\\(" crates/soldier_core/tests/test_recorded_before_dispatch_gate.rs crates/soldier_core/tests/test_intent_id_propagation.rs crates/soldier_core/tests/test_gate_ordering.rs crates/soldier_core/tests/test_rejection_side_effects.rs crates/soldier_core/tests/test_reject_reason.rs crates/soldier_core/tests/test_label.rs crates/soldier_core/tests/test_missing_config.rs crates/soldier_core/tests/test_intent_determinism.rs crates/soldier_core/tests/test_dispatch_map.rs`  
    output: 87 matches across listed tests
  - `cargo test -p soldier_core --no-run --tests`  
    output: test compilation succeeded; all relevant test binaries built (warnings only)
- proof:
  - In-tree production callsites now use `from_validated`, `no_contracts`, or `failed` constructors.
  - `unchecked()` is now `#[cfg(test)]` only at source.
  - `GateResults::all_passed()` no longer exists; integration tests now consume `gate_results_all_passing()` from `crates/soldier_core/tests/common/mod.rs`.

## R5B-03 (P1): Make AT-040 fail-closed behavior deterministic from production-equivalent config flow
- status: FIXED
- disposition: fixed
- owner: Runtime/config owner (2026-02-24)
- commands and outputs:
  - `rg -n --glob '*.rs' "SyntheticNoDefault" crates/soldier_infra/src/config.rs crates/soldier_infra/tests/test_config_defaults.rs`  
    output: 5 matches including source variant and test fixture uses
  - `cargo test -p soldier_infra --test test_config_defaults test_all_config_params_fail_closed_when_missing_without_default -- --exact --nocapture`  
    output: `1 passed; 0 failed`
  - `cargo test -p soldier_infra --test test_config_defaults test_all_params_resolve_through_resolver -- --exact --nocapture`  
    output: `1 passed; 0 failed`

## R5B-04 (P1): Add hard list-element schema validation for proof-graph list fields
- status: FIXED
- disposition: fixed
- owner: Validator owner (2026-02-24)
- commands and outputs:
  - `python3 -m pytest python/proof_graph/tests/test_schema.py -q`  
    output: `39 passed, 4 subtests passed`

## R5B-05 (P1): Make invalid `causal_proof.mechanism` verdict-aware in `r_024b`
- status: FIXED
- disposition: fixed
- owner: Validator owner (2026-02-24)
- commands and outputs:
  - `python3 -m pytest python/proof_graph/tests/test_rules.py -q`  
    output: `209 passed`
  - `python3 -m pytest python/proof_graph/tests/test_rules.py -q -k mechanism`  
    output: `11 passed, 198 deselected`

## R5B-06 (P2): Enforce stale reconciliation metadata as a hard path where contract requires
- status: FIXED
- disposition: fixed
- owner: Validator owner (2026-02-24)
- commands and outputs:
  - `python3 -m pytest python/proof_graph/tests/test_aggregate.py -q`  
    output: `31 passed`
  - `python3 -m pytest python/proof_graph/tests/test_rules.py -q`  
    output: `209 passed`

## R5B-07 (P2): Remove stale callsite/evidence text and align to actual call graph
- status: FIXED
- disposition: fixed
- owner: Runtime owner (2026-02-24)
- commands and outputs:
  - `if rg -n --glob '*.rs' "zero production callsites|currently only called from unit tests|test-only only|only unit tests" crates/soldier_core/src/execution/dispatch_map.rs crates/soldier_core/tests/test_dispatch_map.rs crates/soldier_core/src/execution/open_runtime.rs; then echo \"stale production callgraph evidence text still present\"; exit 1; fi`  
    output: no matches
  - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`  
    output: `1 passed; 0 failed`

## R5B-08 (P2): Enforce workflow-contract checks when workflow artifacts are modified
- status: DEFERRED
- disposition: deferred — deterministic blockers outside this slice
- owner: Workflow owner (2026-02-24)
- debt_id: `DEBT-S1-013-002`
- commands and outputs:
  - `./plans/workflow_contract_gate.sh`  
    output: `workflow contract gate: OK`
  - `./plans/verify.sh quick`  
    output: `preflight: 15 passed, 1 failed, 1 warnings` and `[FAIL] PRD schema validation failed`
  - `./plans/workflow_verify.sh`  
    output: same preflight failure (`PRD schema validation failed`)
  - `./plans/prd_schema_check.sh`  
    output: `PRD schema violations: S0-004: enforcement_point must be a known enforcement point when set`

## Completion readiness snapshot
- P1 findings fixed: `PR-1`, `PR-2`, `CR-1`, `CR-2`, `FM-1`, `FM-2`, `FM-3`, `DA-1`, `DA-2`, `DA-3`, `SF-1`, `SF-2`, `SF-3`, `VA-1`, `VA-2`, and `VA-3`.
- P2 finding status:
  - fixed: `PR-3`, `PR-4`, `SF-3`, `DA-3`, `DA-4` (via `R5B-02`, `R5B-03`, `R5B-06`, `R5B-07`)
  - deferred: `SF-4` and `DEBT-S1-013-002` for workflow-contract preflight blocker.
- No P1 is marked fixed without command evidence in this log.
