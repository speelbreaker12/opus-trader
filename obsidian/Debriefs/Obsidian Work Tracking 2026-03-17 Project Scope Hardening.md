---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Added branch-owned project metadata with `base` and `scope_paths`, enforced scope/branch checks in pre-commit and pre-push, guarded PR creation against scope drift, and added a wrapper that writes the created PR number back to the project note.
- Value (what problem it solves): Forces one project note, one worktree, one branch, and one PR to stay aligned so unrelated changes get blocked before commit, push, or PR creation.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Workflow changes could still leak unrelated files into a commit or branch diff; project notes did not declare an explicit allowed file scope; a branch with an open PR could drift into a second project because the existing router and commit guard were advisory at branch level.
- Time/token drain it caused: Review cycles were spent reasoning about whether a branch still matched its project, and recovery from mixed-scope diffs required manual sorting late in the loop.
- Workaround I used this session (exploit): Centralized the scope check into one shared guard script and wired it into commit, push, and PR-open entry points so the same branch-owned metadata blocks drift consistently.
- Next-agent default behavior (subordinate): Before commit, push, or PR creation, treat the active project note as the source of truth for branch ownership, base branch, and allowed paths; if scope changes, stop and split the work into a new worktree and branch.
- Permanent fix proposal (elevate): Keep all branch ownership and scope validation in the shared guard path so future workflow entry points reuse the same fail-closed decision logic instead of copying partial checks.
- Smallest increment: Add `base` / `scope_paths` to the template and active notes, implement `plans/project_scope_guard.sh`, wire it into the hooks and PR gate, and add deterministic regression coverage for commit, push, router, and PR-open flows.
- Validation (proof it got better): The new guard tests, PR wrapper tests, router branch-mismatch tests, and PR gate scope tests pass, and the hooks now block off-scope files using declared project metadata instead of guesswork.

## 2) Best follow-up
- Single best next step: Fix the unrelated contract-kernel drift and rerun `./plans/verify.sh quick` so the workflow branch has a repo-level green verification signal instead of only targeted guard coverage.
- 1-3 upgrades worth considering:
- Add dedicated pre-push fixture coverage that exercises the hook shell around the shared push-mode guard.
- Extend note validation to fail fast when `scope_paths` is omitted from a project file touched by workflow branches.
- Surface the owning project note path directly in more hook error messages so recovery commands are even more obvious.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Never commit files outside the active project note's declared `scope_paths`; enforce: `plans/project_scope_guard.sh commit`.
- Never push a branch whose full diff crosses project scope; enforce: `plans/project_scope_guard.sh push` through `.githooks/pre-push`.
- Never open or extend a PR unless exactly one project note owns the branch and its diff still matches declared scope; enforce: `plans/project_scope_guard.sh pr-create` via `plans/open_project_pr.sh` and `.claude/hooks/pr-review-gate-hook.sh`.
