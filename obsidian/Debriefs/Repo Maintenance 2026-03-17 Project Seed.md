---
project: "[[Repo Maintenance]]"
date: "2026-03-17"
---

## Commits
- pending — seed the shared Repo Maintenance project

## 0) What shipped
- Feature/behavior: Created a shared `Repo Maintenance` project note for small, cross-cutting fixes and housekeeping work.
- Value (what problem it solves): Gives minor batches a reusable tracking home so the vault does not grow a new project page for every small issue.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Small fixes were on track to create too many one-off project notes; unmatched maintenance tasks had no sanctioned fallback project; project tracking risked turning into bookkeeping overhead for minor changes.
- Time/token drain it caused: Repeated note creation and more project-note noise than the maintenance work deserved.
- Workaround I used this session (exploit): Seeded a dedicated `Repo Maintenance` note with router-friendly aliases/keywords, a planned branch/worktree, and explicit split-out guidance.
- Next-agent default behavior (subordinate): Route small, cross-cutting fixes to `Repo Maintenance` unless the work clearly deserves its own project.
- Permanent fix proposal (elevate): Keep one maintenance catch-all note and reserve new project pages for distinct streams of work.
- Smallest increment: Create the project note and one seed debrief so the note is ready for immediate use.
- Validation (proof it got better): The router now has a concrete maintenance project to match against, and the project note itself says when work should be split back out.

## 2) Best follow-up
- Single best next step: Teach future scope guards to stop oversized diffs from accumulating under `Repo Maintenance`.
- 1-3 upgrades worth considering:
- Add a pre-push warning when a maintenance branch diff grows past a small-file threshold.
- Add more aliases if future minor-fix prompts consistently miss the maintenance note.
- Auto-create `.worktrees/repo-maintenance` the first time the router matches this project.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Use `Repo Maintenance` for small, cross-cutting fixes and housekeeping work.
- Do not let `Repo Maintenance` become the home for full projects with dedicated review scope.
- Split maintenance work into a dedicated project once it becomes multi-day, domain-specific, or PR-sized on its own.
