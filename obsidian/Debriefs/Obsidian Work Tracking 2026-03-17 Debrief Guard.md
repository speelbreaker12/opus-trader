---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending (this hook/debrief batch is not committed yet)

## 0) What shipped
- Feature/behavior: Added a repo-owned Obsidian commit guard that blocks commits unless a staged project note, a staged debrief, and a project-note link to the staged debrief are all present, then repointed the Claude-side pre-commit hook to delegate to that same shared guard.
- Value (what problem it solves): Prevents future agents from satisfying project tracking partially and forgetting the debrief trail that closes out a session, while keeping tool-time blocking consistent with repo pre-commit.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The original repo pre-commit hook did not enforce any Obsidian tracking; the Claude-side hook only checked for project notes; completed work could be committed without any session debrief.
- Time/token drain it caused: Follow-up questions after commit and manual cleanup to restore missing project memory.
- Workaround I used this session (exploit): Added one shared guard script, wired it into the canonical repo pre-commit path, then delegated the Claude-side hook to the same script instead of maintaining duplicate logic.
- Next-agent default behavior (subordinate): Stage the project note and debrief together, and add the debrief link before trying to commit.
- Permanent fix proposal (elevate): Keep Obsidian commit enforcement in one shared guard with regression tests under `plans/tests/`, and make all tool-side hooks delegate to it.
- Smallest increment: Maintain a dedicated guard script and fail-closed shell test that runs in workflow verification.
- Validation (proof it got better): The repo hook and Claude-side hook both block commits missing a project note, block commits missing a debrief, block missing links, and pass when all three conditions are staged.

## 2) Best follow-up
- Single best next step: Add frontmatter validation for required debrief fields in the shared guard.
- 1-3 upgrades worth considering:
- Validate debrief frontmatter fields in the shared guard for stronger consistency.
- Add a helper command that scaffolds a debrief from the template and injects the project link.
- Surface the active project's most recent debrief in the context hook for faster session resumes.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Do not commit repository changes without staging both the project note and a matching debrief.
- Ensure the staged project note links the staged debrief under `## Debriefs` before commit.
- Keep Obsidian tracking enforcement in repo-owned hooks and tests, not only tool-specific hooks.
