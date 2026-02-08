# PR Postmortem (Agent-Filled)

Governing contract: workflow (specs/WORKFLOW_CONTRACT.md)

## 0) What shipped
- Feature/behavior: Added a fail-closed legacy layout guard (`plans/legacy_layout_guard.sh`) and a verify gate contract parity checker (`plans/verify_gate_contract_check.sh`), then wired both into `preflight`, `verify_fork`, and workflow allowlist/coverage checks.
- What value it has (what problem it solves, upgrade provides): Prevents legacy harness/doc drift from silently re-entering active workflow paths and blocks quick/full semantics drift between workflow contract text and actual verify gates.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Legacy terminology remained in historical docs; quick/full semantics can diverge between contract text and scripts without a deterministic check; layout enforcement was inline instead of centrally reusable.
- Time/token drain it caused: Repeated manual validation and ambiguity triage during workflow maintenance PRs.
- Workaround I used this PR (exploit): Implemented single-source guard scripts and promoted them into enforced gates.
- Next-agent default behavior (subordinate): Run `./plans/preflight.sh` and `./plans/verify.sh full`; rely on guard failures instead of manual grep checks.
- Permanent fix proposal (elevate): Keep all workflow-surface invariants codified as dedicated gate scripts and covered by allowlist tests.
- Smallest increment: Add one guard per invariant and wire it into verify/preflight.
- Validation (proof it got better): `./plans/verify.sh full` passed with both new gates active and artifacted.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Best follow-up is adding a deterministic CI check that root-level workflow references (docs/scripts) never point to removed legacy commands. Upgrades: 1) enforce README/CI entrypoint parity with a script; 2) add postmortem archival marker check to workflow_verify tests; 3) emit a machine-readable quick/full gate manifest from verify for contract-map traceability. Validate by intentional fixture mismatches that fail fail-closed.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: 1) Require a dedicated guard script for any new workflow invariant (no inline one-off checks). 2) Require one deterministic test/allowlist assertion for every new workflow script. 3) Require postmortem archival markers when touching legacy-referencing postmortems during workflow migrations.

## 4) Architectural Risk Lens (required)
1. Architectural-level failure modes (not just implementation bugs)
- Failure mode: Contract says one quick/full gate set while verify runs another.
- Trigger: Script edits without contract parity checks.
- Blast radius: False confidence in completion gates and pass eligibility decisions.
- Detection signal: `verify_gate_contract_check` failing.
- Containment: Fail closed in verify before stack gates run.

2. Systemic risks and emergent behaviors
- Cross-component interaction: Workflow contract docs, verify scripts, and allowlist tests.
- Emergent behavior risk: Small script edits silently changing operational policy.
- Propagation path: Script drift -> CI drift -> operator confusion.
- Containment: Enforced parity and allowlist coverage checks.

3. Compounding failure scenarios
- Chain: Legacy reference drift -> wrong command usage -> skipped canonical verify path.
- Escalation condition: Legacy files/paths reappear in active harness/docs.
- Breakpoints/guards that stop compounding: `legacy_layout_guard.sh` in preflight + full verify.
- Evidence (test/log/validation): `artifacts/verify/20260208_142926/preflight.log`, `artifacts/verify/20260208_142926/verify_gate_contract.log`.

4. Hidden assumptions that could be violated
- Assumption: Historical postmortems are treated as archival when containing removed workflow references.
- How it can be violated: Legacy terms reused as active guidance.
- Detection: Archival marker scan in `legacy_layout_guard.sh`.
- Handling/fail-closed behavior: Preflight fails until marker is present.

5. Long-term maintenance hazards
- Hazard: Workflow checks split across many scripts without explicit ownership.
- Why it compounds over time: Each migration adds drift surface.
- Owner: Workflow maintainers.
- Smallest follow-up: Add an ownership block in each guard script header.
- Validation plan: Review checklist item requiring owner+scope on new guard scripts.
