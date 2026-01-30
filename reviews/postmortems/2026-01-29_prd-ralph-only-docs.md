# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Tightened Ralph-only PRD enforcement docs, fixed PRD jq paths, aligned Ralph skill guidance, and added workflow acceptance check for the Ralph-only sentinel.
- What value it has (what problem it solves, upgrade provides): Prevents manual implementation of pending PRD stories and removes misleading instructions that bypassed enforcement.
- Governing contract: Workflow (specs/WORKFLOW_CONTRACT.md)

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Agents implementing pending PRD stories manually; jq examples returned empty due to .stories[]; Ralph-only sentinel not enforced.
- Time/token drain it caused: Rework and verification churn when manual changes bypassed harness gates.
- Workaround I used this PR (exploit): Documented Ralph-only rule and added acceptance assertion for the sentinel.
- Next-agent default behavior (subordinate): Check PRD status via .items[] and block manual implementation when passes=false.
- Permanent fix proposal (elevate): Consider an explicit runtime guard that blocks agent execution unless Ralph is running or a manual override is declared.
- Smallest increment: Documentation + acceptance assertion (this change).
- Validation (proof it got better): ./plans/verify.sh full

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add an optional agent guard wrapper with an explicit manual override flag; validate by running ./plans/ralph.sh and a manual override case.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: Require a PRD status check (jq .items[]) before any PRD story implementation request.
