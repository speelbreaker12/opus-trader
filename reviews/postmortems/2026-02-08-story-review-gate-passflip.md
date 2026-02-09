# PR Postmortem (Agent-Filled)

Governing contract: workflow (`specs/WORKFLOW_CONTRACT.md`)

## 0) What shipped
- Feature/behavior: Added a fail-closed story review evidence gate (`plans/story_review_gate.sh`) plus a self-review artifact logger (`plans/self_review_logged.sh`), enforced this gate in `plans/prd_set_pass.sh` for `passes=true` flips, and added postmortem/digest tooling (`plans/story_postmortem_logged.sh`, `plans/codex_review_digest.sh`) with auto-digest generation in `plans/codex_review_logged.sh`.
- What value it has (what problem it solves, upgrade provides): Prevents pass flips when review evidence is stale/missing for current `HEAD`, ensures blocking/major/medium findings are explicitly resolved before PRD pass mutation, and makes Codex/postmortem evidence easier to consume without losing raw artifacts.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): `passes=true` enforcement validated verify artifacts but did not require HEAD-matched review artifacts; review evidence checks were procedural/manual; stale review files could be mistaken for current approval.
- Time/token drain it caused: Repeated manual verification and reviewer uncertainty over whether evidence matched current commit.
- Workaround I used this PR (exploit): Added deterministic gate script and wired it directly into pass-flip path.
- Next-agent default behavior (subordinate): Use `plans/self_review_logged.sh`, `plans/codex_review_logged.sh`, and `review_resolution.md`, then run `plans/prd_set_pass.sh` which now enforces review artifacts fail-closed.
- Permanent fix proposal (elevate): Add focused fixture tests for `plans/story_review_gate.sh` fail cases (missing/HEAD mismatch/resolution mismatch).
- Smallest increment: Add fixture directories under `plans/fixtures/` and one shell test runner for expected failures.
- Validation (proof it got better): `plans/prd_set_pass.sh` now hard-fails without HEAD-matched review evidence and full verify remains green.

## 2) Given what I built, what's the single best follow-up PR, and what 1-3 upgrades are worth considering next? Include smallest increment + how we validate.
- Response: Best follow-up is fixture-driven tests for `plans/story_review_gate.sh` to prevent regressions in gate parsing/semantics. Upgrades: (1) enforce schema-like lint for `review_resolution.md` fields; (2) optionally emit a compact gate audit line into verify artifacts when pass-flip gate fails; (3) add one example template file in `docs/` for resolution format. Smallest increment is (1) fixture tests. Validate by intentional mismatches that must fail with deterministic error text.

## 3) Given what I built and the pain I hit (top sinks + failure modes), what 1-3 enforceable AGENTS.md rules should we add so the next agent doesn't repeat it?
- Response: 1) Any new pass-flip enforcement must be wired directly into `plans/prd_set_pass.sh` (not advisory docs only). 2) Any new workflow script must be added to `plans/workflow_files_allowlist.txt` and its coverage test in same PR. 3) Any new workflow gate semantics must be reflected in `specs/WORKFLOW_CONTRACT.md` in the same PR.

## 4) Architectural Risk Lens (required)
1. Architectural-level failure modes (not just implementation bugs)
- Failure mode: Pass flip occurs with stale review evidence from previous commit.
- Trigger: No HEAD binding on review artifacts.
- Blast radius: Non-reviewed code marked complete in PRD.
- Detection signal: `story_review_gate.sh` fail on HEAD mismatch.
- Containment: Block in `plans/prd_set_pass.sh` before writing PRD.

2. Systemic risks and emergent behaviors
- Cross-component interaction: `prd_set_pass.sh`, review artifact writers, and workflow contract docs.
- Emergent behavior risk: Human process drift where review appears done but does not match current commit.
- Propagation path: Stale artifacts -> manual assumption of approval -> pass flip.
- Containment: Mandatory HEAD-matched gate for self/Codex/resolution evidence.

3. Compounding failure scenarios
- Chain: stale self-review -> stale Codex review -> pass flip -> story merged as complete.
- Escalation condition: No deterministic verification of review evidence against HEAD.
- Breakpoints/guards that stop compounding: `story_review_gate.sh` + fail-closed call inside `prd_set_pass.sh`.
- Evidence (test/log/validation): `artifacts/verify/20260208_151445/` + `plans/prd_set_pass.sh` review gate enforcement.

4. Hidden assumptions that could be violated
- Assumption: Resolution file references a Codex artifact for current story/head.
- How it can be violated: Relative path points outside codex directory or old file.
- Detection: Gate requires referenced file exists, is under story codex dir, and contains `- HEAD: <current>`.
- Handling/fail-closed behavior: pass-flip rejected with explicit error.

5. Long-term maintenance hazards
- Hazard: Review gate format drift between docs and scripts.
- Why it compounds over time: Manual review artifacts evolve informally.
- Owner: Workflow maintainers.
- Smallest follow-up: Add fixture-based regression tests for expected formats.
- Validation plan: CI test fails on format mismatch and passes on compliant fixtures.

## Evidence (optional but recommended)
- Command:
  - `./plans/verify.sh full`
  - Key output: `=== VERIFY OK (mode=full) ===`
  - Artifact/log path: `artifacts/verify/20260208_180755/`
