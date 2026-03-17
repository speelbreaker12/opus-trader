---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — first-prompt Obsidian router + commit-scope reminder batch

## 0) What shipped
- Feature/behavior: Replaced the passive Obsidian context dump with a first-prompt router that matches the user message to the best `obsidian/Projects/*.md` note, injects the matched note into hook context, forces an explicit first-response acknowledgement, and falls back to ambiguity handling or new-project proposals when no confident match exists.
- Value (what problem it solves): New sessions now start from the relevant project note instead of forcing the agent to infer context from a broad project list, and blocked commits now remind the user to include only the changes they made.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The old context hook printed every project on every prompt; the agent still had to choose the right project manually; commit-block messages did not remind the user to keep the commit scoped to their own changes.
- Time/token drain it caused: Extra first-turn clarification and repeated context scanning, plus avoidable staging mistakes in dirty worktrees.
- Workaround I used this session (exploit): Reused the existing `UserPromptSubmit` hook path, added deterministic session-aware routing keyed off the prompt and `session_id`, and extended the shared Obsidian guard message instead of duplicating logic in multiple hook paths.
- Next-agent default behavior (subordinate): Treat the first user prompt as a project-routing step, confirm the matched note explicitly, and keep commit-scope reminders centralized in the shared guard.
- Permanent fix proposal (elevate): Keep project routing and commit-scope guidance in repo-owned shared hooks with regression tests wired into workflow verification.
- Smallest increment: Add a dedicated context-hook regression test and keep the router plus shared guard on the workflow-file allowlist.
- Validation (proof it got better): The new hook test proves single-match, ambiguous-match, no-match, and unresolved-session follow-up behavior; the commit-guard tests prove the scope reminder appears in both repo and Claude pre-commit paths.

## 2) Best follow-up
- Single best next step: Add an optional alias field to project notes so routing can match stable project keywords without depending only on filenames and free text.
- 1-3 upgrades worth considering:
- Surface the matched project path and recent debrief directly in the first-turn context output for faster resumes.
- Add a small helper that scaffolds a new project note from the template when the router finds no match.
- Backfill the `pending` commit entry on the next Obsidian Work Tracking update so the project page and debrief stay synchronized.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- The first prompt in a session must route through `obsidian/Projects` and either confirm the matched note, ask the user to choose between ambiguous matches, or propose a new project note.
- Shared commit guidance belongs in `plans/obsidian_commit_guard.sh`; tool-specific hooks should delegate to it instead of carrying their own copy.
- Project notes should keep a top-level `## Commits` section with date, hash or `pending`, and a short description for each project batch.
