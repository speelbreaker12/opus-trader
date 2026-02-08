# PR Postmortem (Agent-Filled)

> ARCHIVAL NOTE (Legacy Workflow): This postmortem contains historical references to removed Ralph/workflow-acceptance components. Treat these references as archival context only.

## 0) What shipped
- Feature/behavior: PRD lint corrections: scope.create/touch fixes, added missing observability metrics, normalized refs, and added parent evidence directories to satisfy create-parent requirements.
- What value it has (what problem it solves, upgrade provides): PRD gate passes again so workflow acceptance/verify can run; removes false failures from scope mismatches.
- Governing contract: specs/WORKFLOW_CONTRACT.md (workflow maintenance)

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): prd_gate failed on CREATE_PATH_EXISTS/MISSING_PATH; prd_ref_check failed on unresolved refs; workflow acceptance test 0k blocked verify.
- Time/token drain it caused: repeated verify failures and inability to run workflow acceptance.
- Workaround I used this PR (exploit): corrected PRD scope entries and refs; added evidence parent dirs for create-parent rules.
- Next-agent default behavior (subordinate): run ./plans/prd_gate.sh after PRD edits and fix scope/create parent rules before verify.
- Permanent fix proposal (elevate): add a small PRD lint fixer for create/touch mismatches and missing parent dirs (dry-run + patch).
- Smallest increment: a helper that rewrites scope.create→touch when file exists and reports parent dir gaps.
- Validation (proof it got better): ./plans/prd_gate.sh plans/prd.json passes (warnings only).

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a PRD lint autofix step for create/touch mismatches and missing parent dirs; validate by running ./plans/prd_gate.sh on a clean checkout.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response:
  - SHOULD run ./plans/prd_gate.sh after any PRD edit (Trigger: plans/prd.json changed; Prevents: late ref/lint failures; Enforce: include gate output in evidence).
