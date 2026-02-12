# PR Postmortem: Smoke PR Gate Validation

## 0) What shipped
- Feature/behavior: Added a tiny smoke marker file to create a controlled PR.
- What value it has (what problem it solves, upgrade provides): It validates that branch protection and required checks block unsafe merges.
- Governing contract: specs/WORKFLOW_CONTRACT.md

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): We needed a low-risk way to test merge blocking without touching production logic.
- Time/token drain it caused: Repeated uncertainty about whether policy was enforced at repository level.
- Workaround I used this PR (exploit): Isolated a single-file smoke branch and ran merge attempts directly.
- Next-agent default behavior (subordinate): Use tiny PR smoke tests when changing merge policy.
- Permanent fix proposal (elevate): Keep required checks and gates configured in branch protection.
- Smallest increment: One marker file commit plus one merge attempt before checks complete.
- Validation (proof it got better): Merge command is rejected until required checks and gate conditions pass.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add automated periodic policy smoke checks and alert on missing required status checks.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: Require policy changes to include one real smoke PR merge attempt and evidence output.

## 4) Architectural Risk Lens (required)

1. Architectural-level failure modes (not just implementation bugs)
- Failure mode: Merge protection configuration could drift and silently allow unsafe merges.
- Trigger: Branch protection rules modified or removed without corresponding CI job updates.
- Blast radius: Any PR could merge without proper validation, bypassing safety checks.
- Detection signal: Smoke test merge attempts succeed when they should be blocked.
- Containment: Periodic automated smoke tests to verify merge blocking remains active.

2. Systemic risks and emergent behaviors
- Cross-component interaction: CI status checks and GitHub branch rules can disagree if job names change.
- Emergent behavior risk: Renaming CI jobs can silently disable merge protection.
- Propagation path: Job rename → branch protection rule no longer matches → merge blocking fails.
- Containment: Maintain explicit mapping between CI job names and required status check names.

3. Compounding failure scenarios
- Chain: Missing required check → early merge → bypassed review feedback.
- Escalation condition: Multiple required checks missing simultaneously.
- Breakpoints/guards that stop compounding: GitHub branch protection blocks merge if ANY required check is missing.
- Evidence (test/log/validation): This smoke PR demonstrates merge blocking when checks are pending.

4. Hidden assumptions that could be violated
- Assumption: Copilot review appears automatically on every PR head update.
- How it can be violated: GitHub Apps can be disabled, rate-limited, or have permissions revoked.
- Detection: PR remains in pending state without any Copilot review comments.
- Handling/fail-closed behavior: Branch protection requires the Copilot check status to pass before merge.

5. Long-term maintenance hazards
- Hazard: Gate scripts evolve while branch protection contexts are left stale.
- Why it compounds over time: Each script change increases divergence between actual checks and protected contexts.
- Owner: Workflow maintainer should audit branch protection settings quarterly.
- Smallest follow-up: Document current required status check names in workflow contract.
- Validation plan: Automated test that compares branch protection API response against documented list.

## Evidence
- Command: This PR is a smoke test only.
- Key output: Merge blocking is demonstrated by attempting merge before checks pass.
- Artifact/log path: N/A for smoke marker change.
