# Skills And Prompt Index

Canonical catalog for prompt-backed workflow skills in this repository.

Validation command:
- `python3 scripts/check_skills_index.py`

| Name | Path | Description |
|---|---|---|
| Reconciliation | `plans/prompts/reconcil.md` | Premortem + R1-R7 reconciliation workflow |
| 6-Skill Review Stack | `plans/prompts/review-stack.md` | All 6 review skills in sequence |
| Cutter | `plans/prompts/cutter.md` | Story slicing/cutting prompt used by `plans/cut_prd.sh` |

## Skill wrappers

| Skill | File |
|---|---|
| `/reconcil` | `SKILLS/reconcil.md` |
| `/review-stack` | `SKILLS/review-stack.md` |
| `/6` | `SKILLS/6.md` |
| `/toc` | `SKILLS/toc.md` |

## Full skill inventory

| Skill | File | Summary |
|---|---|---|
| `/6` | `SKILLS/6.md` | Alias for `/review-stack`. |
| `/acceptance-test` | `SKILLS/acceptance-test.md` | Generate acceptance tests from contract requirements. |
| `/commit-push-pr` | `SKILLS/commit-push-pr.md` | Stage, commit, push, and open PR with repo conventions. |
| `/contract-audit-full` | `SKILLS/contract-audit-full.md` | Exhaustive contract coverage and conflict audit. |
| `/contract-review` | `SKILLS/contract-review.md` | Fast fail-open safety filter for changes. |
| `copilot-aftercare` | `SKILLS/copilot-aftercare.md` | Copilot review response loop workflow. |
| `/devils-advocate` | `SKILLS/devils-advocate.md` | Mutation-style test-the-tests review. |
| `diff-first-review` | `SKILLS/diff-first-review.md` | Diff-first review discipline. |
| `/failure-mode-review` | `SKILLS/failure-mode-review.md` | Implementation-level failure path analysis. |
| `flow-audit-loop` | `SKILLS/flow-audit-loop/SKILL.md` | ACF flow audit loop for contract flow bundles. |
| `/git` | `SKILLS/git.md` | Branch, merge, and worktree discipline. |
| `interview` | `SKILLS/interview.md` | Spec-building interview workflow. |
| `patch-only-edits` | `SKILLS/patch-only-edits.md` | Patch-only editing style and constraints. |
| `/plan` | `SKILLS/plan.md` | Elevation to implementation plan workflow. |
| `/plan-review` | `SKILLS/plan-review.md` | Implementation plan review checklist. |
| `/post-impl-audit` | `SKILLS/post-impl-audit.md` | Post-implementation breaker audit. |
| `post-pr-postmortem` | `SKILLS/post_pr_postmortem.md` | Human-readable post-PR postmortem workflow. |
| `/pr-check` | `SKILLS/pr-check.md` | Review comments to merge-ready branch flow. |
| `/pr-review` | `SKILLS/pr-review.md` | General PR review checklist. |
| `/pre-commit` | `SKILLS/pre-commit.md` | Pre-commit safety gate checks. |
| `/ralph-loop` | `SKILLS/ralph-loop.md` | Run Ralph harness iterations. |
| `/reconcil` | `SKILLS/reconcil.md` | Premortem + reconciliation orchestration. |
| `/review-stack` | `SKILLS/review-stack.md` | Run 6 review skills in sequence. |
| `/self-review` | `SKILLS/self-review.md` | 5-skill self-review stack. |
| `/slice-execute` | `SKILLS/slice-execute.md` | Per-story implementation protocol. |
| `spec-lint-checklist` | `SKILLS/spec_lint_checklist/SKILL.md` | Checklist for `specs/CONTRACT.md` patches. |
| `spec-lint-implementation-plan` | `SKILLS/spec-lint-implementation-plan/SKILL.md` | Validate `IMPLEMENTATION_PLAN.md` against safety contracts. |
| `/step-supervisor` | `SKILLS/step-supervisor.md` | One-step-at-a-time workflow driver. |
| `/strategic-failure-review` | `SKILLS/strategic-failure-review.md` | Systemic/architectural risk review. |
| `/validator-audit` | `SKILLS/validator-audit.md` | Validator completeness and gap audit. |
| `/verify` | `SKILLS/verify.md` | Verification run and failure explanation workflow. |
| `/toc` | `SKILLS/toc.md` | Theory of Constraints commit — commit + §0 what shipped, §1 constraint, §2 next story, §3 enforceable rules. |
