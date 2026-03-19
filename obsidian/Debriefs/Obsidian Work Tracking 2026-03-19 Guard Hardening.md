---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-19"
type: debrief
---

## What shipped
- Slim context hook: replaced scoring/tokenizing router with deterministic branch-ownership lookup; skill handles ambiguity
- Tiered commit gates: trivial (<10 lines, docs-only) and light (<50 lines, no crates/) tiers skip heavy ceremony
- Review-fix mode: OBSIDIAN_REVIEW_FIX=1 relaxes obsidian gate for follow-up commits on reviewed branches
- Amend-aware obsidian guard: inherits project/debrief from parent commit when amending
- Hotfix branch exemption: hotfix/*, fix/* branches skip obsidian and scope guards
- Verify cache in pre-push: skips redundant verify.sh if tree SHA already verified
- Force-with-lease allowance: permits --force-with-lease on feature branches (still blocks main/master)
- Scope guard dry-run: --dry-run flag for pr-create reports violations without blocking
- Mixed-project branch warning: soft warning at commit time if prior commits touch out-of-scope files
- Code-review-expert guard improvements: skip for formatting-only changes, SKIP_CODE_REVIEW_REASON env var
- New helper scripts: worktree_commit_push.sh, post_rebase_frontmatter_check.sh, write_review_gate_marker.sh
- New slash command: /obsidian-workflow

## Constraint
- Workflow guards were too rigid for iterative development: every commit required full obsidian ceremony even for trivial fixes, blocking flow

## Follow-up
- Test the tiered commit gates end-to-end across several real commits
- Verify hotfix branch exemption works with all guard layers
- Consider adding worktree field auto-detection to context hook

## Rules
- Commit tier classification must be fail-closed: default to "full" when tier cannot be determined
- Hotfix exemption applies only to obsidian and scope guards, not to main-branch protection or clippy
