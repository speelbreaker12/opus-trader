---
phase: quick-01
plan: 01
type: execute
wave: 1
depends_on: []
files_modified:
  - plans/phase_drift_closure_plan.md
  - specs/CONTRACT.md
  - specs/IMPLEMENTATION_PLAN.md
  - docs/health_endpoint.md
  - docs/phase1_acceptance.md
  - docs/launch_policy.md
  - plans/verify_fork.sh
  - plans/check_contract_change_ledger.sh
  - plans/tests/test_contract_change_ledger.sh
autonomous: true
must_haves:
    truths:
      - "Phase 0 gating language is enforceable and non-ambiguous"
      - "Health/status authority boundaries are explicit across contract/docs"
      - "Every future CONTRACT mutation is fail-closed checked by verify"
    artifacts:
      - path: plans/check_contract_change_ledger.sh
        provides: CONTRACT change ledger fail-closed check
      - path: plans/tests/test_contract_change_ledger.sh
        provides: Deterministic checker coverage for pass/fail paths
      - path: plans/verify_fork.sh
        provides: Verify gate integration for contract-change checker
    key_links:
      - from: plans/phase_drift_closure_plan.md
        to: specs/CONTRACT.md
        via: PR1 scope definition references contract updates
        pattern: specs/CONTRACT\.md
      - from: plans/phase_drift_closure_plan.md
        to: plans/verify_fork.sh
        via: PR1 scope requires verify gate wiring
        pattern: plans/verify_fork\.sh
---

# Quick Task 1: PR1 Drift Closure Plan and Checker-First Gate

## Objective
- **What:** Execute PR1 planning/checker pass for contract/doc/verify alignment and contract-change ledger enforcement.
- **Why:** Remove drift before implementation to minimize rework and keep verification fail-closed.
- **Output:** A checker-validated execution plan for PR1 with explicit files, tests, and gate commands.

## Context
@.planning/PROJECT.md
@.planning/ROADMAP.md
@.planning/STATE.md
@plans/phase_drift_closure_plan.md
@specs/CONTRACT.md

## Tasks

<task type="auto">
  <name>Task 1: Finalize PR1 scope boundaries and source-of-truth matrix</name>
  <files>plans/phase_drift_closure_plan.md, specs/CONTRACT.md, specs/IMPLEMENTATION_PLAN.md, docs/health_endpoint.md, docs/phase1_acceptance.md</files>
  <action>Lock PR1 changes to enforceable Phase 0 wording, Phase 1 artifact parity, and explicit authority matrix for foundation status-lite vs CSP minimum vs Phase 0 owner-status scaffolding. Ensure references are canonical and no split-brain wording remains.</action>
  <verify>rg -n "before any code implementation begins|foundation status-lite|CSP minimum|phase1_meta_test|restart_loop" specs/CONTRACT.md specs/IMPLEMENTATION_PLAN.md docs/health_endpoint.md docs/phase1_acceptance.md</verify>
  <done>All targeted docs consistently encode PR1 authority and acceptance boundaries with no contradictory wording.</done>
</task>

<task type="auto">
  <name>Task 2: Implement contract-change ledger checker and wire verify gate</name>
  <files>plans/check_contract_change_ledger.sh, plans/tests/test_contract_change_ledger.sh, plans/verify_fork.sh</files>
  <action>Create deterministic fail-closed checker that requires a new ledger row when CONTRACT.md changes, add test coverage for changed/missing-row FAIL and changed/valid-row PASS, then wire checker into quick/full verify flow.</action>
  <verify>bash plans/tests/test_contract_change_ledger.sh && ./plans/verify.sh quick</verify>
  <done>Checker and tests are green and verify runs checker in both quick and full modes.</done>
</task>

<task type="auto">
  <name>Task 3: Complete PR1 metadata cleanup and final validation pass</name>
  <files>docs/launch_policy.md, plans/phase_drift_closure_plan.md</files>
  <action>Fill launch policy metadata placeholders (`owner`, `prepared_by`), run required verification commands, and update plan verification section with concrete evidence commands for PR1 readiness.</action>
  <verify>./plans/verify.sh quick && ./plans/verify.sh full</verify>
  <done>PR1 checklist is implementation-ready with metadata complete and full verification path documented.</done>
</task>

## Verification
- `node /Users/admin/.codex/get-shit-done/bin/gsd-tools.cjs verify plan-structure .planning/quick/1-pr1-drift-closure-contract-doc-verify/1-PLAN.md --raw`
- `node /Users/admin/.codex/get-shit-done/bin/gsd-tools.cjs verify references .planning/quick/1-pr1-drift-closure-contract-doc-verify/1-PLAN.md --raw`

## Success Criteria
- [ ] Plan checker reports valid structure with required frontmatter and task fields.
- [ ] All file references resolve and key links are explicit.
- [ ] PR1 execution can start without additional scope clarification.
