# Skills Index

Canonical catalog for prompt-backed workflow skills in this repository.

Validation command:
- `python3 scripts/check_skills_index.py`

## Workflow lifecycle

The daily git-and-obsidian lifecycle. Each skill owns one boundary.

```
  session start
       │
       ▼
  /obsidian-workflow ─── classify task, route to project + worktree
       │
       ▼
  workspace-policy ──── preflight, lane rules, worktree hygiene
       │
       ▼
  (implement)
       │
       ▼
  /commit ───────────── stage, review gate, obsidian tracking, local commit
       │
       ▼
  /push-pr ──────────── refresh branch, push, create or update PR
       │
       ▼
  /pr-check ─────────── surface review comments, resolve conflicts, merge queue
       │
       ▼
  /merge-cleanup ────── merge single PR, sync main, remove worktree + branch, update obsidian
       │
       ▼
  session end
```

Supporting skills:
- `/git` — branch, merge, worktree discipline, conflict resolution
- `/hotfix` — shared baseline bug: dedicated branch from main, merge first
- `/main-recovery` — recover diverged/dirty/stuck main branch

## Review skills

| Skill | File | Purpose |
|-------|------|---------|
| `/pr-review` | `SKILLS/pr-review.md` | General PR review checklist |
| `/failure-mode-review` | `SKILLS/failure-mode-review.md` | Implementation-level failure path analysis |
| `/strategic-failure-review` | `SKILLS/strategic-failure-review.md` | Systemic/architectural risk review |
| `/contract-review` | `SKILLS/contract-review.md` | Fast fail-open safety filter |
| `/validator-audit` | `SKILLS/validator-audit.md` | Validator completeness and gap audit |
| `/devils-advocate` | `SKILLS/devils-advocate.md` | Mutation-style test-the-tests review |
| `/loss-risk-gate` | `SKILLS/loss-risk-gate.md` | Trading loss / profit-block economic safety review |
| `/review-stack` | `SKILLS/review-stack.md` | Run 7 review skills in sequence |
| 7-Skill Review Stack | `plans/prompts/review-stack.md` | All 7 review skills in sequence |
| `/external-review-generic` | `SKILLS/external-review-generic.md` | 4 external reviewers in parallel |
| `/super-pr-review` | `SKILLS/super-pr-review.md` | 7 internal + 4 external with cross-validation |

## Implementation skills

| Skill | Purpose |
|-------|---------|
| `/plan` | Elevation to implementation plan |
| `/plan-review` | Implementation plan review checklist |
| `/premortem` | Pre-implementation safety analysis (25 assertions, STOPLIGHT gate) |
| `/slice-execute` | Per-story implementation protocol |
| `/post-impl-audit` | Post-implementation breaker audit |
| `/reconcil` | Premortem + reconciliation orchestration |
| `/toc` | Theory of Constraints commit format |
| `/verify` | Verification run and failure explanation |

## Contract skills

| Skill | Purpose |
|-------|---------|
| `/contract-audit-full` | Exhaustive contract coverage audit |
| `/contract-review` | Fast fail-open safety filter |
| `contract-gap-detector` | Automated gap finder (autoresearch phase 1) |
| `contract-patch` | Automated patch proposer (autoresearch phase 2) |
| `/acceptance-test` | Generate acceptance tests from contract requirements |

## Design and exploration skills

| Skill | Purpose |
|-------|---------|
| `/design-interface` | "Design It Twice" — parallel interface designs |
| `/grill` | Adversarial plan interview |
| `/codebase-health` | Architecture friction audit |
| `/glossary` | Domain terminology glossary |
| `/triage` | Bug investigation → GH issue with TDD fix plan |
| `interview` | Spec-building interview workflow |

## Reference skills (non-invokable)

| Skill | Purpose |
|-------|---------|
| `workspace-policy` | Shared workspace safety rules (referenced by /commit, /push-pr, /obsidian-workflow) |
| `diff-first-review` | Diff-first review discipline |
| `patch-only-edits` | Patch-only editing constraints |
| `copilot-aftercare` | Copilot review response loop |
| `post-pr-postmortem` | Post-PR postmortem workflow |

## Full inventory

| Skill | File | Invokable |
|-------|------|-----------|
| `/6` | `SKILLS/6.md` | yes (alias for `/review-stack`) |
| `/acceptance-test` | `SKILLS/acceptance-test.md` | yes |
| `/codebase-health` | `SKILLS/codebase-health.md` | yes |
| `/commit` | `SKILLS/commit.md` | yes |
| `/contract-audit-full` | `SKILLS/contract-audit-full.md` | yes |
| `contract-gap-detector` | `SKILLS/contract-gap-detector.md` | no |
| `contract-patch` | `SKILLS/contract-patch.md` | no |
| `/contract-review` | `SKILLS/contract-review.md` | yes |
| `copilot-aftercare` | `SKILLS/copilot-aftercare.md` | no |
| `/design-interface` | `SKILLS/design-interface.md` | yes |
| `/devils-advocate` | `SKILLS/devils-advocate.md` | yes |
| `diff-first-review` | `SKILLS/diff-first-review.md` | no |
| `/external-review-generic` | `SKILLS/external-review-generic.md` | yes |
| `/failure-mode-review` | `SKILLS/failure-mode-review.md` | yes |
| `/git` | `SKILLS/git.md` | yes |
| `/glossary` | `SKILLS/glossary.md` | yes |
| `/grill` | `SKILLS/grill.md` | yes |
| `/hotfix` | `SKILLS/hotfix.md` | yes |
| `interview` | `SKILLS/interview.md` | no |
| `/loss-risk-gate` | `SKILLS/loss-risk-gate.md` | yes |
| `/main-recovery` | `SKILLS/main-recovery.md` | yes |
| `/merge-cleanup` | `SKILLS/merge-cleanup.md` | yes |
| `/obsidian-workflow` | `SKILLS/obsidian-workflow.md` | yes |
| `patch-only-edits` | `SKILLS/patch-only-edits.md` | no |
| `/plan` | `SKILLS/plan.md` | yes |
| `/plan-review` | `SKILLS/plan-review.md` | yes |
| `/post-impl-audit` | `SKILLS/post-impl-audit.md` | yes |
| `post-pr-postmortem` | `SKILLS/post_pr_postmortem.md` | no |
| `/pr-check` | `SKILLS/pr-check.md` | yes |
| `/pr-review` | `SKILLS/pr-review.md` | yes |
| `/pre-commit` | `SKILLS/pre-commit.md` | yes |
| `/premortem` | `SKILLS/premortem.md` | yes |
| `/push-pr` | `SKILLS/push-pr.md` | yes |
| `/ralph-loop` | `SKILLS/ralph-loop.md` | yes |
| `/recon-executor` | `SKILLS/recon-executor.md` | yes |
| `/recon-operator` | `SKILLS/recon_operator.md` | yes |
| `/reconcil` | `SKILLS/reconcil.md` | yes |
| `/review-stack` | `SKILLS/review-stack.md` | yes |
| `/slice-execute` | `SKILLS/slice-execute.md` | yes |
| `/strategic-failure-review` | `SKILLS/strategic-failure-review.md` | yes |
| `/super-pr-review` | `SKILLS/super-pr-review.md` | yes |
| `/toc` | `SKILLS/toc.md` | yes |
| `/triage` | `SKILLS/triage.md` | yes |
| `/validator-audit` | `SKILLS/validator-audit.md` | yes |
| `/verify` | `SKILLS/verify.md` | yes |
| `workspace-policy` | `SKILLS/workspace-policy.md` | no (referenced by other skills) |
