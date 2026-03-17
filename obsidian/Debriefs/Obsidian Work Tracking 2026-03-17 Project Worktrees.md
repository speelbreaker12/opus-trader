---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — 2026-03-17 — add `worktree_obsidian` and first-prompt click-through path metadata (no mirror model).
- 75abb925 — project-scoped worktree routing batch

## 0) What shipped
- Feature/behavior: Added `worktree` and `worktree_obsidian` tracking to project notes and taught the first-prompt router to create/reuse dedicated project worktrees plus project-local Obsidian folders automatically.
- Value (what problem it solves): Keeps projects isolated from each other, reduces dirty-tree interference, and gives the agent one canonical workspace path to use after the first message.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Project notes identified the work but not the workspace; rebases and unrelated local dirt could interfere across projects in the shared root checkout; the first-prompt router could find the right project note but still leave the agent in the wrong working tree.
- Time/token drain it caused: Extra cleanup and staging discipline in the root checkout, plus repeated chat guidance telling the agent which branch or directory to use for a project.
- Workaround I used this session (exploit): Added a canonical `worktree` field, defaulted missing projects to `.worktrees/<project-slug>`, and taught the router to auto-bootstrap the project worktree when it is missing.
- Next-agent default behavior (subordinate): When the router reports a project worktree, use it for commands and edits in that session instead of the root checkout.
- Permanent fix proposal (elevate): Treat worktree ownership as part of the project record itself so project routing and workspace isolation stay synchronized.
- Smallest increment: Add `worktree` to the template, update the workflow skill/AGENTS guidance, and extend the router test to prove matched and newly created projects receive dedicated worktrees.
- Validation (proof it got better): The router test now runs in a real git repo and proves both matched-project worktree creation and no-match project/worktree auto-bootstrap.

## 2) Best follow-up
- Single best next step: Teach the router to surface the most recent active handoff for the matched project from within that worktree-aware session context.
- 1-3 upgrades worth considering:
- Rename `## Key Files` to `## Files` and prefix entries by role now that project notes track workspace paths too.
- Add a small helper to migrate older project notes that still point at shared branches like `main` onto dedicated project branches when first matched.
- Add a smoke test that a matched project with an existing `worktree` path is reused rather than recreated.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Each active project note should carry a dedicated `worktree` path instead of assuming the shared repo root.
- When the first-prompt router reports a project worktree, use that worktree for session commands and edits.
- New project auto-bootstrap must update the project note and create the worktree together so the note never points at a missing workspace.
