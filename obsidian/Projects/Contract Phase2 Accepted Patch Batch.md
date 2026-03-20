---
status: in-progress
priority: P1
branch: project/contract-phase2-accepted-patch-batch
base: project/contract-autoresearch-harness-fix
pr:
started: "2026-03-20"
aliases: []
keywords:
  - contract patch batch
  - accepted phase2 patches
scope_paths:
  - specs/CONTRACT.md
  - docs/contract_kernel.json
  - autoresearch/contract/common/**
  - autoresearch/contract/phase1/fixtures/**
  - autoresearch/contract/phase1/internal/**
  - autoresearch/contract/phase2/fixtures/snapshot/**
  - obsidian/Projects/Contract Phase2 Accepted Patch Batch.md
  - obsidian/Debriefs/Contract Phase2 Accepted Patch Batch *.md
---

## Current State

Stacked branch `project/contract-phase2-accepted-patch-batch` is cut from `project/contract-autoresearch-harness-fix` to apply the accepted hardened Phase 2 contract patches without widening PR #224. The accepted LG/EG/TMC/EC deltas are now applied to `specs/CONTRACT.md` with permanent IDs `AT-1282`, `AT-1283`, and `AT-1284`, plus ledger row `CCL-2026-03-20-01`. `docs/contract_kernel.json`, autoresearch common context, and the affected Phase 1/Phase 2 fixtures/snapshots were refreshed. Targeted contract checks are green. Repo quick verify run `20260320_171755` finished with an unrelated workflow-test failure in `wf_test_review_command_wrappers`, expecting `Use the Skill tool with skill name "review-stack"` in `.claude/commands/review-stack.md`; this branch does not touch that file.

## Commits
- `pending` — 2026-03-20 — Apply accepted LG/EG/TMC/EC Phase 2 contract patches and refresh dependent artifacts.

## Key Files
- `specs/CONTRACT.md`
- `docs/contract_kernel.json`
- `autoresearch/contract/common/`
- `autoresearch/contract/phase1/fixtures/`
- `autoresearch/contract/phase2/fixtures/snapshot/`

## Debriefs
- [[Contract Phase2 Accepted Patch Batch 2026-03-20]]

## Log
### 2026-03-20
- Created a stacked contract-patch branch from `project/contract-autoresearch-harness-fix` so accepted autoresearch outputs can be applied to `specs/CONTRACT.md` in-scope.
- The accepted patch set currently consists of LG replace fallback alignment, EG non-zero cooldown AT coverage, three TMC clarifications/ATs, and the EC retry-schedule AT; OPL remained pending due to AT id collisions with existing §3.1 tests.
- Applied the accepted contract patch batch to `specs/CONTRACT.md`: LG stale-L2 algorithm text now covers replace-order fallback, EG gained non-zero cooldown coverage as `AT-1283`, TMC gained corroboration/reason-purity clarifications plus `AT-1282`, and EC gained the bounded retry-schedule AT as `AT-1284`.
- Added `CCL-2026-03-20-01` so the contract change ledger remains append-only for this branch delta.
- Refreshed `docs/contract_kernel.json`, `autoresearch/contract/common/{at_registry,section_index,context_manifest}`, and the affected live Phase 1 fixtures plus Phase 2 snapshot fixtures.
- Verified the batch with `python3 scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --check-at --strict --include-bare-section-refs`, `python3 scripts/check_contract_kernel.py --kernel docs/contract_kernel.json`, `./plans/check_contract_change_ledger.sh`, and `git diff --check`; only the existing Appendix A wording warnings remain from `check_contract_crossrefs.py`.
- Ran `./plans/verify.sh quick` as run `20260320_171755`; it passed preflight, verify gate contract, artifact lint, contract kernel/ledger/manifest, AT profile parity, contract/spec validators, mechanical verification, rust gates, and most workflow tests, then failed on the unrelated workflow test `wf_test_review_command_wrappers` because `.claude/commands/review-stack.md` did not contain the expected literal `Use the Skill tool with skill name "review-stack"`.
