# R5B_FIX_PLAN — Slice 1 (tightened)

## Scope and constraints
- Slice: `S1`
- Inputs: all six receipt JSON files in `reviews/reconciliations/S1/receipts/`
- `r5b_validator_audit.json` is explicitly in scope because it contains production-affecting Python validator risk.
- All items in this plan are source-level actions or explicit, logged debt entries.
- No P1 item may be marked fixed without deterministic evidence in `R5B_FIX_LOG.md`.

## Finding inventory
- P1: `PR-1`, `PR-2`, `CR-1`, `CR-2`, `FM-1`, `SF-1`, `SF-2`, `DA-1`, `DA-2`, `VA-1`, `VA-2`
- P2: `PR-3`, `PR-4`, `FM-2`, `FM-3`, `SF-3`, `SF-4`, `DA-3`, `DA-4`, `VA-3`

## Hard ordering rules
1. Any item touching production wiring must first prove its non-test caller chain.
2. Any item with a missing source owner must be deferred via `reviews/reconciliations/S1/DEBT_REGISTER.json`.
3. Any item modifying workflow contract surfaces must run `./plans/workflow_contract_gate.sh`.
4. Completion artifacts must be recorded under `reviews/reconciliations/S1/R5B_FIX_LOG.md`.

## Ordered fix plan

### R5B-01 (P1): Attest production open-order call chain before claiming AT-920 wiring fixes
- Findings: `PR-1`, `PR-2`, `CR-1`, `FM-1`, `SF-1`, `SF-2`, `DA-1`, `DA-2`
- Owner: Runtime owner
- Target files/functions:
  - `crates/soldier_core/src/execution/open_runtime.rs` (`build_open_order_intent_runtime`, `build_open_intent_with_assembly`)
  - `crates/soldier_core/src/execution/intent_assembly.rs` (`assemble_sizing`, `evaluate_assembled_pipeline`)
  - `crates/soldier_core/src/execution/dispatch_map.rs` (`validate_and_dispatch`)
  - `crates/soldier_core/tests/test_open_runtime_wiring.rs`
1. Run call-chain evidence commands and record full output in the log section `R5B-01`:
   - `rg -n --glob '!**/tests/**' "build_open_order_intent_runtime\s*\(" crates/soldier_core/src`
   - `rg -n --glob '!**/tests/**' "assemble_sizing\s*\(|evaluate_assembled_pipeline\s*\(|evaluate_intent_pipeline\s*\(" crates/soldier_core/src`
   - `rg -n --glob '!**/tests/**' "validate_and_dispatch\s*\(" crates/soldier_core/src/execution`
2. Branch decision is required and exclusive:
   - If no non-test callsite exists for these functions, treat as production-entrypoint gap debt. Add `DEBT-S1-007-001` in `reviews/reconciliations/S1/DEBT_REGISTER.json` with owner, date, and prerequisite: "locate/capture verified production caller before runtime claim".
   - If a caller exists, fix only the actual production caller path; do not change `build_open_intent_with_assembly` as if it were live.
3. Optional follow-up hardening in the verified caller path:
   - Ensure AT-920 mismatch handling is enforced before dispatch, using `validate_and_dispatch` from the verified root path.
4. Commands:
   - `cargo test -p soldier_core --test test_open_runtime_wiring test_runtime_wiring_margin_kill_rejects_before_open_dispatch -- --exact --nocapture`
   - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`
5. Completion proof:
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-01`
   - Proof text must include either `DEFER: DEBT-S1-007-001` with timestamp and owner, or explicit diff reference to verified production-root change.

### R5B-02 (P1): Make `DispatchConsistencyProof::unchecked()` non-callable in production code paths
- Findings: `PR-3`, `PR-4`, `FM-2`, `SF-4`, `DA-1`, `DA-4`
- Owner: Runtime owner
- Target files/functions:
  - `crates/soldier_core/src/execution/dispatch_map.rs` (`DispatchConsistencyProof::unchecked`, `from_validated`, `no_contracts`, `failed`)
  - `crates/soldier_core/src/execution/open_runtime.rs`, `crates/soldier_core/src/execution/intent_assembly.rs`
1. Keep `DispatchConsistencyProof::unchecked()` under `#[cfg(test)]` only. Remove any `feature = "test-helpers"` gating for this constructor.
2. Migrate all in-repo callers that currently rely on any test-only exposure to a runtime-safe test helper path:
   - `crates/soldier_core/tests/common/mod.rs`
   - `crates/soldier_core/tests/test_open_runtime_wiring.rs`
   - `crates/soldier_core/tests/test_base_gates.rs`
   - `crates/soldier_core/tests/test_recorded_before_dispatch_gate.rs`
   - `crates/soldier_core/tests/test_intent_id_propagation.rs`
   - `crates/soldier_core/tests/test_gate_ordering.rs`
   - `crates/soldier_core/tests/test_rejection_side_effects.rs`
   - `crates/soldier_core/tests/test_reject_reason.rs`
   - `crates/soldier_core/tests/test_label.rs`
   - `crates/soldier_core/tests/test_missing_config.rs`
   - `crates/soldier_core/tests/test_intent_determinism.rs`
   - `crates/soldier_core/tests/test_dispatch_map.rs`
   - `crates/soldier_core/tests/test_intent_pipeline.rs`
3. Prove non-production reachability with file-level search (commands below).
4. Commands:
   - `if rg -n --glob '!**/tests/**' --glob '!crates/soldier_core/src/execution/dispatch_map.rs' "DispatchConsistencyProof::unchecked\\(" crates/soldier_core/src; then echo "unexpected non-test callsite for DispatchConsistencyProof::unchecked()"; exit 1; fi`
   - `rg -n --glob '!**/tests/**' --glob '*.rs' "DispatchConsistencyProof::from_validated\(|DispatchConsistencyProof::no_contracts\(|DispatchConsistencyProof::failed\(" crates/soldier_core/src`
   - `rg -n -U --glob '*.rs' "\\#\\[cfg\\(test\\)\\]\\s*\\n\\s*pub fn unchecked\\(" crates/soldier_core/src/execution/dispatch_map.rs`
   - `rg -n --glob '*.rs' "DispatchConsistencyProof::unchecked\\(" crates/soldier_core/tests/common/mod.rs crates/soldier_core/tests/test_open_runtime_wiring.rs crates/soldier_core/tests/test_base_gates.rs crates/soldier_core/tests/test_intent_pipeline.rs crates/soldier_core/tests/test_recorded_before_dispatch_gate.rs crates/soldier_core/tests/test_intent_id_propagation.rs crates/soldier_core/tests/test_gate_ordering.rs crates/soldier_core/tests/test_rejection_side_effects.rs crates/soldier_core/tests/test_reject_reason.rs crates/soldier_core/tests/test_label.rs crates/soldier_core/tests/test_missing_config.rs crates/soldier_core/tests/test_intent_determinism.rs crates/soldier_core/tests/test_dispatch_map.rs`
   - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`
   - `if rg -n --glob '*.rs' "test-helpers" crates/soldier_core/src/execution/dispatch_map.rs; then echo "unexpected test-helpers gating still present for dispatch_map"; exit 1; fi`
5. Completion proof:
   - Command 1 must exit successfully only when no non-test callsites are found.
   - Command 3 must show `unchecked` remains cfg(test)-gated.
   - Command 4 must enumerate all remaining test callsites and confirm they are migrated to explicit test-safe builders.
   - Command 5 remains the regression execution command.
   - Command 6 must return no matches for `test-helpers` within `dispatch_map.rs`.
   - Scope note: `build_order_intent.rs` `GateResults::all_passed()` helper has been removed; tests now use `gate_results_all_passing()` from `crates/soldier_core/tests/common`.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-02`.

### R5B-03 (P1): Make AT-040 fail-closed behavior deterministic from production-equivalent config flow
- Findings: `CR-2`, `FM-3`, `DA-3`
- Owner: Runtime/config owner
- Target files/functions:
  - `crates/soldier_infra/src/config.rs` (`resolve_config_value`)
  - `crates/soldier_infra/tests/test_config_defaults.rs`
1. Preserve `SyntheticNoDefault` as test-only and add/keep a production-equivalent path assertion for missing required values.
2. Add/extend tests to cover non-default missing required fields and required-field hard fail under non-test resolver semantics.
3. Commands:
   - `rg -n --glob '*.rs' "SyntheticNoDefault" crates/soldier_infra/src/config.rs crates/soldier_infra/tests/test_config_defaults.rs`
   - `cargo test -p soldier_infra --test test_config_defaults test_all_config_params_fail_closed_when_missing_without_default -- --exact --nocapture`
   - `cargo test -p soldier_infra --test test_config_defaults test_all_params_resolve_through_resolver -- --exact --nocapture`
4. Completion proof:
   - First command must show `SyntheticNoDefault` only in test harnesses.
   - Second and third commands must pass.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-03`.

### R5B-04 (P1): Add hard list-element schema validation for proof-graph list fields
- Findings: `VA-1`
- Owner: Validator owner
- Target files/functions:
  - `python/proof_graph/schema.py` (`story_meta.scope_touch`, `wiring.caller_chain`, `enforcement.evidence` schema fields)
  - `python/proof_graph/tests/test_schema.py`
1. Reject non-string entries in the above list fields with precise location in validation diagnostics.
2. Add/adjust fixtures under `python/proof_graph/tests/fixtures/` that intentionally contain mixed-type list elements.
3. Commands:
   - `python3 -m pytest python/proof_graph/tests/test_schema.py -q`
4. Completion proof:
   - New fixture files included in source diff.
   - Full pytest file passes and includes at least one failing fixture assertion for each affected field.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-04`.

### R5B-05 (P1): Make invalid `causal_proof.mechanism` verdict-aware in `r_024b`
- Findings: `VA-2`
- Owner: Validator owner
- Target files/functions:
  - `python/proof_graph/rules.py` (`r_024b`)
  - `python/proof_graph/tests/test_rules.py`
1. Return `BLOCKING` for invalid `causal_proof.mechanism` when AT verdict is `PROVEN_UNIT` or stronger.
2. Keep `HARDENING` behavior for non-PROVEN ATs unless rule contract changes.
3. Commands:
   - `python3 -m pytest python/proof_graph/tests/test_rules.py -q`
   - `python3 -m pytest python/proof_graph/tests/test_rules.py -q -k mechanism`
4. Completion proof:
   - A test in `test_rules.py` must assert the PROVEN-blocking branch and one non-PROVEN branch.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-05` with command outputs.

### R5B-06 (P2): Enforce stale reconciliation metadata as a hard path where contract requires
- Findings: `VA-3`
- Owner: Validator owner
- Target files/functions:
  - `python/proof_graph/aggregate.py`
  - `python/proof_graph/rules.py`
  - `python/proof_graph/tests/test_aggregate.py`
  - `python/proof_graph/tests/test_rules.py`
1. Add deterministic rule transition for `reconciliation_stale` that escalates severity/metadata according to current contract intent.
2. Add regression tests for reconciled+stale state where failure semantics must be explicit.
3. Commands:
   - `python3 -m pytest python/proof_graph/tests/test_aggregate.py -q`
   - `python3 -m pytest python/proof_graph/tests/test_rules.py -q`
4. Completion proof:
   - Evidence shows stale reconciled cases are no longer advisory-only.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-06`.

### R5B-07 (P2): Remove stale callsite/evidence text and align to actual call graph
- Findings: `SF-3`, `PR-4`, `DA-4`
- Owner: Runtime owner
- Target files/functions:
  - `crates/soldier_core/src/execution/dispatch_map.rs`
  - `crates/soldier_core/tests/test_dispatch_map.rs`
  - `crates/soldier_core/src/execution/open_runtime.rs`
1. Replace outdated text that implies `validate_and_dispatch` is test-only when `intent_assembly.rs` is an active source caller.
2. Update any test-only comment that contradicts runtime evidence; keep debt entries only for genuine unresolved items.
3. Commands:
   - `if rg -n --glob '*.rs' "zero production callsites|currently only called from unit tests|test-only only|only unit tests" crates/soldier_core/src/execution/dispatch_map.rs crates/soldier_core/tests/test_dispatch_map.rs crates/soldier_core/src/execution/open_runtime.rs; then echo "stale production callgraph evidence text still present"; exit 1; fi`
   - `cargo test -p soldier_core --test test_dispatch_map test_at920_no_dispatch_on_mismatch -- --exact --nocapture`
4. Completion proof:
   - Command 1 is the no-match gate for stale claim phrases that contradict live-source callgraph evidence.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-07`.

### R5B-08 (P2): Enforce workflow-contract checks when workflow artifacts are modified
- Findings: `SF-4`
- Owner: Workflow owner
- Target files/functions:
  - `.github/workflows/*`
  - `specs/WORKFLOW_CONTRACT.md`
  - `plans/workflow_contract_map.json`
  - `plans/workflow_verify.sh`
1. If any listed file changes, run mandatory workflow contract gate and verify command.
2. Record exact command outputs in log.
3. Commands:
   - `./plans/workflow_contract_gate.sh`
   - `./plans/verify.sh quick`
   - `./plans/workflow_verify.sh`
4. Completion proof:
   - All three commands must pass.
   - Artifact: `reviews/reconciliations/S1/R5B_FIX_LOG.md` section `R5B-08`.

## Receipt-to-item disposition map
- `PR-1` -> `R5B-01` (attestation/debt) and `R5B-02` (bypass control)
- `PR-2` -> `R5B-01` and `R5B-02`
- `PR-3` -> `R5B-02`
- `PR-4` -> `R5B-01` and `R5B-07`
- `CR-1` -> `R5B-01`
- `CR-2` -> `R5B-03`
- `FM-1` -> `R5B-01`
- `FM-2` -> `R5B-02`
- `FM-3` -> `R5B-03`
- `SF-1` -> `R5B-01`
- `SF-2` -> `R5B-01`
- `SF-3` -> `R5B-07`
- `SF-4` -> `R5B-08`
- `VA-1` -> `R5B-04`
- `VA-2` -> `R5B-05`
- `VA-3` -> `R5B-06`
- `DA-1` -> `R5B-01`
- `DA-2` -> `R5B-02`
- `DA-3` -> `R5B-03`
- `DA-4` -> `R5B-02` and `R5B-07`

## Blast radius
- `crates/soldier_core/src/execution/open_runtime.rs`
- `crates/soldier_core/src/execution/intent_assembly.rs`
- `crates/soldier_core/src/execution/dispatch_map.rs`
- `crates/soldier_core/tests/test_dispatch_map.rs`
- `crates/soldier_core/tests/test_open_runtime_wiring.rs`
- `crates/soldier_infra/src/config.rs`
- `crates/soldier_infra/tests/test_config_defaults.rs`
- `python/proof_graph/schema.py`
- `python/proof_graph/rules.py`
- `python/proof_graph/aggregate.py`
- `python/proof_graph/tests/test_schema.py`
- `python/proof_graph/tests/test_rules.py`
- `python/proof_graph/tests/test_aggregate.py`
- Optional workflow files if changed: `.github/workflows/*`, `specs/WORKFLOW_CONTRACT.md`, `plans/workflow_contract_map.json`, `plans/workflow_verify.sh`
- Revised estimate: up to 14 files touched if Python + workflow surfaces are both modified.

## Slice completion gate
1. `reviews/reconciliations/S1/R5B_FIX_LOG.md` contains one signed section for each item `R5B-01` through `R5B-08` with commands and expected outcomes.
2. All 20 findings are marked as `fixed` or `deferred` with owner/date/reason in the log; deferred items must have matching `DEBT-...` records in `reviews/reconciliations/S1/DEBT_REGISTER.json`.
3. No P1 remains unresolved as `fixed` without deterministic evidence entry in `R5B_FIX_LOG.md`.
