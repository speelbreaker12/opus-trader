---
status: in-progress
priority: P1
branch: project/contract-phase2-accepted-patch-batch
base: main
pr: 226
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

This branch started as a stacked follow-up off `project/contract-autoresearch-harness-fix` so the accepted hardened Phase 2 contract patches would not widen PR #224. PR #224 was then refreshed, merged into `main` as merge commit `5fb10390`, and PR #226 was retargeted from the stacked base to `main`. The branch has now been refreshed with `git merge origin/main`, producing local merge commit `fe595abc` with no conflicts, so the contract batch remains a 15-file diff against `main`. PR #226 is open against `main`: https://github.com/speelbreaker12/opus-trader/pull/226. The accepted LG/EG/TMC/EC deltas remain applied to `specs/CONTRACT.md` with permanent IDs `AT-1282`, `AT-1283`, and `AT-1284`, plus ledger row `CCL-2026-03-20-01`. `docs/contract_kernel.json`, autoresearch common context, and the affected Phase 1/Phase 2 fixtures/snapshots were refreshed. Targeted contract checks are green, the PR review gate artifact for HEAD `8bd288e1` recorded `CONDITIONAL_PASS` under `artifacts/story/contract-phase2-accepted-patch-batch/self_review/review_stack.md`, and PR #226 CI is being rerun after the retarget/main-refresh step. Repo quick verify run `20260320_171755` still fails only on the unrelated workflow test `wf_test_review_command_wrappers`, expecting `Use the Skill tool with skill name "review-stack"` in `.claude/commands/review-stack.md`; this branch does not touch that file.

## Commits
- `17404bca` — 2026-03-20 — Apply accepted LG/EG/TMC/EC Phase 2 contract patches and refresh dependent artifacts.
- `8bd288e1` — 2026-03-20 — Sync the contract patch batch Obsidian metadata before the stacked push/PR boundary.
- `85b742ee` — 2026-03-21 — Record PR #226, stacked-base refresh status, and review-gate evidence for the accepted Phase 2 contract patch batch.
- `pending` — 2026-03-21 — Record the `#224` merge, retarget PR #226 to `main`, and refresh this branch against `origin/main`.

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
- Refreshed the stacked branch with `git fetch origin --prune && git rebase origin/project/contract-autoresearch-harness-fix`; the branch was already up to date.
- Created stacked PR #226 against `project/contract-autoresearch-harness-fix`: https://github.com/speelbreaker12/opus-trader/pull/226.
- Wrote the review-gate artifact for HEAD `8bd288e1` under `artifacts/story/contract-phase2-accepted-patch-batch/self_review/` and recorded a `CONDITIONAL_PASS` marker for PR creation.
- Merged PR #224 into `main` as merge commit `5fb10390`, then retargeted PR #226 from the stacked base to `main`.
- Refreshed this branch with `git merge origin/main` after the `#224` merge so the PR stays current against `main` without widening its diff.
