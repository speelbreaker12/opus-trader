# PR Postmortem (Agent-Filled)

Governing contract: workflow (specs/WORKFLOW_CONTRACT.md)

## 0) What shipped
- Feature/behavior: Refreshed docs/contract_kernel.json and added workflow acceptance checks to validate kernel presence and source hashes.
- What value it has (what problem it solves, upgrade provides): Keeps the contract kernel aligned with source files and prevents stale kernel artifacts from passing silently.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): verify failed when kernel sources hash mismatched; workflow acceptance had no explicit kernel check; manual rebuild required.
- Time/token drain it caused: repeated verify runs and manual inspection of kernel hashes.
- Workaround I used this PR (exploit): added workflow acceptance checks and regenerated the kernel.
- Next-agent default behavior (subordinate): rebuild kernel when source hashes change, and rely on acceptance to catch staleness.
- Permanent fix proposal (elevate): ensure CI runs kernel check and requires updated kernel on source changes.
- Smallest increment: add acceptance checks (done).
- Validation (proof it got better): `python3 scripts/check_contract_kernel.py` now enforced via workflow acceptance.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Add a small test fixture for kernel generation to guarantee deterministic output; validate by running workflow acceptance and kernel check.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: No new AGENTS.md rule needed; existing workflow maintenance rules are sufficient.
