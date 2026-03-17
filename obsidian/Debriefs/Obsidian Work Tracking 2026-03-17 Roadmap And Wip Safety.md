---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — add a roadmap section to project pages and document WIP-safety rules

## 0) What shipped
- Feature/behavior: Added a `## Roadmap` section to the project template and current Obsidian workflow project page, and documented WIP-safety rules for rebases, merges, cherry-picks, and worktree cleanup.
- Value (what problem it solves): Keeps the remaining workflow gaps visible on the project page and gives agents explicit rules to avoid deleting user WIP during branch sync operations.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The missing workflow pieces only lived in chat; project pages did not show the next intended enforcement work; agents had no single written rule set for how to treat dirty worktrees during rebase/merge/sync operations.
- Time/token drain it caused: Repeating the same workflow gaps in conversation and risking accidental WIP loss during branch maintenance.
- Workaround I used this session (exploit): Added a visible roadmap to the project page and documented fail-closed worktree-safety rules in the workflow guidance.
- Next-agent default behavior (subordinate): Read the project roadmap before extending the workflow, and do not run rebase/merge/cherry-pick or delete a worktree when user WIP is still present.
- Permanent fix proposal (elevate): Convert the roadmap items into hook-enforced branch-scope and WIP-safety checks.
- Smallest increment: Add the `## Roadmap` template section, seed the current project roadmap, and document WIP-safety rules where agents already look.
- Validation (proof it got better): The current workflow project page now shows the remaining enforcement backlog, and the docs now explicitly forbid dirty-worktree sync and automatic worktree deletion.

## 2) Best follow-up
- Single best next step: Implement the first branch-scope guard from the roadmap, starting with a pre-push check for unrelated branch diffs.
- 1-3 upgrades worth considering:
- Add a `pre-rebase` hook that blocks rebases in dirty worktrees.
- Add a helper that reports whether a worktree is safe to delete after merge.
- Add router logic for `general question` vs `Repo Maintenance` vs `new project`.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Every project page should carry a `## Roadmap` section that records the next intended slices or workflow guardrails.
- Never rebase, merge, cherry-pick, or remove a project worktree while it still contains uncommitted user WIP.
- Keep project worktrees through active PR work and remove them only after merge, clean state, and explicit approval or clear project completion.
