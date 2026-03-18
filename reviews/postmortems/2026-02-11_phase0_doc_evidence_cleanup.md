# PR Postmortem (Agent-Filled)

## 0) What shipped
- Feature/behavior: Consolidated Phase 0 docs/evidence references, fixed Phase 1 index clarity, and aligned roadmap evidence path naming to canonical `evidence/phaseN/`.
- What value it has (what problem it solves, upgrade provides): Removes stale or ambiguous evidence navigation, prevents host-path leakage in artifacts, and keeps review/verify gates deterministic.
- Governing contract: `specs/WORKFLOW_CONTRACT.md` | `specs/CONTRACT.md`

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms):
  - CI `pr-gate-enforced` blocked on unresolved bot comments.
  - PR artifacts contained machine-local absolute paths.
  - Evidence/index docs mixed existing and pending artifacts, causing review ambiguity.
- Time/token drain it caused: Extra CI reruns and repeated PR comment triage.
- Workaround I used this PR (exploit): Applied narrow file-level fixes tied to each bot comment and re-verified quickly before pushing.
- Next-agent default behavior (subordinate): Treat each bot thread as a concrete file-diff task; patch immediately and verify.
- Permanent fix proposal (elevate): Add a pre-push doc lint for absolute-path leakage and missing postmortem references.
- Smallest increment: Add a lightweight check script invoked from preflight for `evidence/**/*.json` absolute paths and PR body postmortem file existence.
- Validation (proof it got better): Review threads resolved and `./plans/verify.sh quick` remained green on updated head.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Best follow-up is a docs hygiene gate PR that validates evidence-link existence and path portability. Upgrades: (1) absolute-path detector for evidence artifacts, (2) phase index validator that marks missing files as pending, (3) postmortem-link existence check. Start with (1); validate by preventing any `/Users/...` or similar absolute paths in checked-in evidence.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response:
  - Require bot review threads to be resolved by direct file diffs before any merge attempt.
  - Require postmortem file existence when PR body references `reviews/postmortems/...`.
  - Require evidence artifact path portability (repo-relative paths only; no host-local absolute paths).
