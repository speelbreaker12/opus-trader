---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## 0) What shipped
- Feature/behavior: `post-commit` now prints a commit visibility line when `obsidian/Active Projects.md` changes.
- Value (what problem it solves): Makes dashboard sync into commit context so you can tell in log output whether pre-commit auto-sync touched the index in that commit.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Hooks updated workspace metadata automatically, but commit logs did not show whether `Active Projects.md` changed, making auditability weaker.
- Time/token drain it caused: Extra terminal inspection after commits to confirm whether dashboard sync actually occurred.
- Workaround I used this session (exploit): Added `obsidian/Active Projects.md` to the post-commit notifier.
- Next-agent default behavior (subordinate): Use commit log output as confirmation that dashboard refresh happened.
- Permanent fix proposal (elevate): Keep lightweight automation visibility hooks for any future pre-commit auto-updated files.
- Smallest increment: Print a one-line post-commit confirmation when the dashboard file is in the commit diff.
- Validation (proof it got better): Commit flow now emits `obsidian: Active Projects dashboard auto-sync touched this commit.` when applicable.

## 2) Best follow-up
- Single best next step: Add a deterministic stale-worktree warning in the same post-commit output when the project link resolves to missing paths.
- 1-3 upgrades worth considering:
  - Add a one-line check for unresolved `worktree_obsidian` paths.
  - Show the `project` row count before and after refresh when changed.
  - Add a manual `--notify` flag for optional verbose hook output.

## 3) Enforceable rules
1) Emit one post-commit summary line for every index file the pre-commit auto-sync may modify.
2) Keep sync-related automation visibility in hook output for commit review traceability.
