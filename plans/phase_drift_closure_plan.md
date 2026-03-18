# Phase Drift Closure Plan (Full 1-9, 3 PRs, Agent-First)

## Summary
This plan implements all 9 items in your suggested order, with explicit contract/doc/verify reconciliation first, then TLSM/WAL hardening, then chokepoint proof-depth and ops cleanup.  
Locked choices:
- Scope: Full 1-9
- Delivery: 3 PR sequence
- Health model: HTTP canonical
- Phase1 evidence gate: keep mandatory and contractize
- Contract appendix: inside `specs/CONTRACT.md`, from this PR forward
- Execution mode: use agents always

## Execution Model (Use Agents Always)
1. For each PR, run 3 agents in parallel:
- Agent A (`explorer`): truth-check current state + line refs before edits.
- Agent B (`worker`): implement changes in owned files.
- Agent C (`explorer`): independent post-change review against contract + tests.
2. Coordinator merges outputs, resolves conflicts, and runs verification.
3. After significant behavior changes (PR2, PR3), run `code-review-expert` before final full verify.
4. Never touch root `./verify.sh`; only `plans/verify.sh`/`plans/verify_fork.sh` paths if needed.

## PR1 — Contract/Docs/Verify Constraint Alignment + Contract Change Appendix
## Goal
Eliminate definition-of-done drift in governance documents and verification expectations.

## Files
- `specs/CONTRACT.md`
- `specs/IMPLEMENTATION_PLAN.md`
- `docs/health_endpoint.md`
- `docs/phase1_acceptance.md`
- `docs/launch_policy.md`
- `tools/phase1_meta_test.py` (only if needed for checklist parity)
- `plans/verify_fork.sh`
- `plans/check_contract_change_ledger.sh` (new; mandatory, deterministic fail-closed checker)
- `plans/tests/test_contract_change_ledger.sh` (new; checker coverage)

## Changes
1. Phase 0 wording fix:
- Replace “before any code implementation begins” with enforceable boundary language (“before live-trading enablement / CSP claim / Phase2+ promotion”).
2. Phase 1 scope clarity:
- Keep CSP precedence/phase rule as canonical.
- Add explicit cross-reference in roadmap docs so “Phase 1 milestone” cannot be misread as “CSP minimum subset.”
3. Health/status split resolution (authority + schema boundaries):
- Make `docs/health_endpoint.md` HTTP-canonical and align enum casing to `Active|ReduceOnly|Kill`.
- Add an explicit authority matrix for status surfaces:
  - Foundation status-lite (phase bootstrap): exact allowed key set and invariants.
  - CSP-minimum status: canonical authority keys required only after the legal foundation-exit transition completes; `foundation_exit_condition == true` (`phase != foundation`) is the resulting status predicate.
  - Phase 0 owner-status scaffolding: minimum required fields and alias behavior.
- Reconcile all references to this matrix across `specs/CONTRACT.md`, `specs/IMPLEMENTATION_PLAN.md`, and `docs/health_endpoint.md` so field scope/casing cannot drift.
- Keep CLI as operator convenience surface, not transport authority.
4. Verify contract alignment:
- In normative docs, define `./plans/verify.sh full` as completion/pass-flip gate.
- Keep quick as developer iteration gate.
5. Contractize mandatory Phase1 evidence gate:
- Add explicit acceptance criteria in normative roadmap docs for the currently enforced `phase1_meta_test` artifact set.
- Remove mismatch where `docs/phase1_acceptance.md` requires `restart_loop` while checklist/meta-test treat it as planned future.
6. Launch policy artifact cleanup:
- Fill `owner` and `prepared_by` in `docs/launch_policy.md`.
7. New contract-change appendix:
- Add an appendix section in `specs/CONTRACT.md` with a dated ledger table:
  - `date_utc`, `change_id`, `sections_touched`, `change_type`, `summary`, `rationale`, `AT/VR refs`, `story/pr`.
- Seed first row from this PR date.
- Rule: every future `CONTRACT.md` mutation must add a dated row.
- Enforce this rule with `plans/check_contract_change_ledger.sh` and wire it into `./plans/verify.sh` via `plans/verify_fork.sh` (fail-closed in both quick and full).
- Add deterministic fixture coverage in `plans/tests/test_contract_change_ledger.sh` for:
  - `CONTRACT.md` changed + missing row -> FAIL
  - `CONTRACT.md` changed + valid row -> PASS
  - `CONTRACT.md` unchanged -> PASS

## Public Interface/Type Impact (PR1)
- Documentation semantics only (HTTP authority + status enum canonicalization).
- No runtime API shape change in this PR.

## PR1 Verification
- `bash plans/tests/test_contract_change_ledger.sh`
- `./plans/verify.sh quick`
- `./plans/verify.sh full`
- Confirm contract/doc sync gates pass (crossrefs, coverage, phase1 meta-test, contract-change-ledger checker).

---

## PR2 — TLSM/WAL Drift Hardening + No-Panic Enforcement
## Goal
Remove panic footguns and make TLSM↔WAL coupling self-proving.

## Files
- `specs/CONTRACT.md`
- `specs/IMPLEMENTATION_PLAN.md`
- `crates/soldier_core/src/execution/tlsm.rs`
- `crates/soldier_core/src/execution/open_runtime.rs`
- `crates/soldier_core/src/execution/open_runtime_wiring_tests.rs`
- `crates/soldier_core/src/execution/tlsm_tests.rs`
- `crates/soldier_core/tests/test_tlsm.rs`
- `crates/soldier_infra/src/store/ledger.rs`
- `crates/soldier_infra/tests/test_ledger_replay.rs`

## Changes
1. Path/reference drift fix:
- Update TLSM “Where” path references to actual `crates/soldier_core/src/execution/tlsm.rs`.
2. Vocabulary canonicalization without WAL migration risk:
- Canonical runtime term remains `PartiallyFilled`.
- Document explicit runtime↔WAL mapping to `PartialFill` in contract text.
3. Remove debug panic footguns:
- Replace `debug_assert!(false, ...)` inconsistency branches with explicit error-path handling + metric increments + structured logs.
4. Explicit fail-closed settlement signaling:
- Make terminal reservation settlement return explicit success/error outcome (instead of silent drop behavior).
- On settlement inconsistency, emit error outcome for caller-driven fail-closed downgrade.
5. Strengthen drift proofs:
- Keep existing whitelist sync test.
- Add reverse/coverage test to prove ledger successor whitelist and TLSM accepted transitions remain aligned, with WAL-only exceptions explicitly enumerated.

## Public Interface/Type Impact (PR2)
- Internal Rust API change:
  - TLSM terminal settlement helpers return explicit error/outcome type.
- New/extended observability counters for TLSM invariant violations.

## PR2 Verification
- `cargo test -p soldier_core --test test_tlsm`
- `cargo test -p soldier_core --lib open_runtime_wiring_tests`
- `cargo test -p soldier_infra --test test_ledger_replay`
- `./plans/verify.sh quick`
- `./plans/verify.sh full`
- Run `code-review-expert` before final full verify.

---

## PR3 — Chokepoint Acceptance Proof Expansion + Workflow/Smoke Coverage + Ops Cleanup
## Goal
Close remaining “caller-level proof” gaps and ensure critical behaviors are exercised in integration/smoke paths.

## Files
- `crates/soldier_core/src/execution/pipeline_integration_tests.rs`
- `crates/soldier_core/src/execution/gate_outcome_tests.rs` (if mapping extension needed)
- `crates/soldier_core/src/execution/label_tests.rs` (only if additional causality assertions needed)
- `crates/soldier_infra/tests/test_crash_mid_intent.rs` (reuse/extend existing exact-once scenarios if needed)
- `plans/lib/rust_gates.sh`
- Optional doc sync:
  - `docs/dispatch_chokepoint.md`
  - `docs/intent_gate_invariants.md`

## Changes
1. Add missing chokepoint causality for liquidity slippage variant:
- New integration test proving `ExpectedSlippageTooHigh` at chokepoint with dispatch count `0` and correct reject code.
2. Preserve/confirm existing label and WAL causality:
- Keep existing label-too-long degraded/dispatch=0 evidence.
- Keep existing durable AT-935 exact-once-across-restarts evidence.
3. Promote exact-once behavior into fast signal path:
- Add one targeted `soldier_infra` crash/restart exact-once test to quick smoke execution in `plans/lib/rust_gates.sh` using:
  - `cargo test -p soldier_infra --locked --test test_crash_mid_intent test_crash_mid_intent_no_duplicate_dispatch`
- Keep it selector-scoped (single test only, no heavy suite expansion).
- Runtime budget target for quick mode: <= 45s p95 in CI; if exceeded, treat as regression and tighten selector/fixture cost.
4. Ops artifact cleanup carried here only if not done in PR1:
- Ensure `docs/launch_policy.md` metadata completion is merged.

## Public Interface/Type Impact (PR3)
- No external API changes.
- Verification pipeline behavior change: quick smoke includes one infra exact-once test.

## PR3 Verification
- `cargo test -p soldier_infra --locked --test test_crash_mid_intent test_crash_mid_intent_no_duplicate_dispatch`
- `./plans/verify.sh quick` (ensure new smoke remains stable/fast enough)
- `./plans/verify.sh full`
- Run `code-review-expert` before final full verify.

---

## Test Scenarios and Acceptance Matrix (1-9)
1. Phase 1 definition freeze: docs/contract crossrefs explicitly consistent.
2. Phase 0 gate reality: enforceable boundary language in contract.
3. Health/status split: HTTP authority, enum casing, and foundation-vs-CSP key boundaries aligned.
4. Verify chain contract: full gate defined for completion; quick documented as convenience.
5. Phase1 evidence pack: mandatory gate explicitly represented in normative docs.
6. TLSM drift: path fixed, mapping documented, sync tests strengthened.
7. No-panic footgun: debug asserts removed from inconsistency paths.
8. Chokepoint-level coverage: slippage reason causality added at integration level; exact-once present in smoke path.
9. Artifact theater: launch policy placeholders resolved; lenient mode remains dev-only and non-CI/non-deploy.

## Assumptions and Defaults
- `owner` and `prepared_by` in `docs/launch_policy.md` will be set to repository owner identity currently used in this repo (`admin`) unless you override.
- Contract appendix starts from this PR date forward (no historical backfill).
- We do not relax mandatory gates; we align docs/contracts upward to existing enforcement.
- We do not change root `./verify.sh`.
- We keep WAL naming backward-compatible (`PartialFill`) and avoid storage migration in this tranche.
