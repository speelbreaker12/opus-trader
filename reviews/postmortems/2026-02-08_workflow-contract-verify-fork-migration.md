# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Replaced canonical workflow contract with a verify-fork/manual-WIP model, archived Ralph-era contract, rewired workflow contract map, added `plans/prd_set_pass.sh`, added `plans/verify_fork.sh`, and updated PRD schema rule semantics.
- What value it has (what problem it solves, upgrade provides): Removes contract split-brain between fork workflow intent and Ralph-era enforcement assumptions; adds explicit fail-closed pass-flip checks based on verify artifacts.
- Governing contract: specs/WORKFLOW_CONTRACT.md

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Existing contract/map enforced Ralph-only artifacts and pass-flip authority; PRD schema encoded Ralph-era rule keys; workflow acceptance assertions hard-coded old WF IDs.
- Time/token drain it caused: High rework risk from touching contract without synchronized map/assertion updates.
- Workaround I used this PR (exploit): Rebuilt contract and map together, then patched targeted acceptance assertions (`Test 12*`) to validate the new IDs and required artifacts.
- Next-agent default behavior (subordinate): When changing workflow governance, always update `specs/WORKFLOW_CONTRACT.md`, `plans/workflow_contract_map.json`, and `plans/workflow_acceptance.sh` in the same PR.
- Permanent fix proposal (elevate): Add a dedicated workflow contract migration test group that validates archived contract presence + key fork invariants independent of Ralph tests.
- Smallest increment: Keep `Test 12*` as the migration chokepoint and extend with one test per newly introduced workflow validator path.
- Validation (proof it got better): `./plans/workflow_contract_gate.sh` passes on new IDs; `./plans/prd_schema_check.sh plans/prd.json` passes with fork rule keys; direct `prd_set_pass.sh` fail-closed checks pass.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Best follow-up PR is to align `AGENTS.md`, `ENTRYPOINTS.md`, and `plans/PRD_WORKFLOW.md` with the new canonical workflow contract, then remove stale Ralph-only language. Upgrades: (1) implement a true non-recursive verify-fork execution path and wire CI shadow comparison; validate with CI artifacts comparing gate outcomes. (2) add `plans/tests/test_prd_set_pass.sh` and invoke from a workflow gate; validate via deterministic pass/fail fixtures. (3) define `verify.meta.json` generation in `plans/verify.sh`; validate with artifact existence/asserted fields.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response:
  - MUST treat workflow contract rewrites as three-file atomic updates (`specs/WORKFLOW_CONTRACT.md`, `plans/workflow_contract_map.json`, `plans/workflow_acceptance.sh`) — Trigger: any WF-* edit — Prevents: traceability drift.
  - SHOULD keep `plans/prd_schema_check.sh` backward-compatible for one migration window when changing `rules` keys — Trigger: PRD rules schema change — Prevents: fixture/test blast radius.
  - MUST add or update fail-closed acceptance checks when introducing new pass-flip tooling (`plans/prd_set_pass.sh`) — Trigger: pass mutation path changes — Prevents: false-green promotions.
