# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: PRD lint now flags contract_refs that mention Anchor/VR titles without the corresponding Anchor-###/VR-### IDs; workflow acceptance asserts the rule is present.
- What value it has (what problem it solves, upgrade provides): Prevents traceability drift by forcing explicit Anchor/VR IDs when titles are referenced, reducing manual PRD cleanup.
- Governing contract: specs/WORKFLOW_CONTRACT.md

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Contract refs used human-readable titles without Anchor/VR IDs; coverage checks required manual cross-referencing; PRD edits kept re-opening the same traceability gaps.
- Time/token drain it caused: Repeated PRD diffing and manual anchor lookups.
- Workaround I used this PR (exploit): Added deterministic lint checks for missing Anchor/VR IDs and acceptance guardrails.
- Next-agent default behavior (subordinate): When referencing an anchor/validation rule title in contract_refs, always include the Anchor-###/VR-### ID in the same array.
- Permanent fix proposal (elevate): Add a PRD autofix to insert missing Anchor/VR IDs when titles match the anchor catalogs.
- Smallest increment: Add a lint autofix hook that maps title → ID using docs/architecture/* catalogs.
- Validation (proof it got better): Lint now emits MISSING_ANCHOR_REF/MISSING_VR_REF and workflow acceptance enforces presence of these rules.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a fixture-based acceptance test that runs prd_lint on a PRD containing an anchor title without its ID; validate by expecting a non-zero exit with the new error codes.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: Require Anchor/VR IDs whenever contract_refs mention an anchor/validation rule title; add a checklist item to confirm prd_lint passes after PRD edits.
