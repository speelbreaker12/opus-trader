# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Require PR reviews to enumerate file coverage; expand review checklist sections for coverage, workflow changes, and claims/data; add acceptance checks for review checklist sections.
- What value it has (what problem it solves, upgrade provides): Makes review scope explicit, reduces missed files, and reinforces workflow change hygiene.
- Governing contract: workflow contract (specs/WORKFLOW_CONTRACT.md)

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Reviews skipped new files or did not call out workflow risks; checklist did not force coverage enumeration.
- Time/token drain it caused: Back-and-forth review clarifications and rework to confirm coverage.
- Workaround I used this PR (exploit): Added explicit review coverage requirements in AGENTS and pr-review skill, plus checklist sections.
- Next-agent default behavior (subordinate): Always include a Review Coverage section with per-file notes.
- Permanent fix proposal (elevate): Add acceptance checks that enforce the checklist structure and coverage language.
- Smallest increment: Validate required checklist section headers in workflow acceptance.
- Validation (proof it got better): workflow_acceptance now fails if the checklist sections are missing.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a PR template snippet that scaffolds Review Coverage and evidence blocks; validate by ensuring new PRs include the sections and review notes are filled.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: If workflow or review requirements change, update workflow_acceptance to enforce the new requirement in the same PR.
