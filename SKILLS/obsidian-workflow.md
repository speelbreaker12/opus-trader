# SKILL: /obsidian-workflow (Project Tracking Companion)

Purpose
- Keep Obsidian project tracking consistent at session start and before commit.
- Complement the hooks with the exact project-page and debrief checklist the agent should follow.

When to use
- At the start of a new session in this repo.
- After the first prompt hook identifies or proposes an Obsidian project note.
- Before committing changes that affect `obsidian/Projects/` or `obsidian/Debriefs/`.

## Session Start
- Read the matched project note under `obsidian/Projects/`.
- If the matched project note already records a `worktree`, use that worktree for commands and edits in the session.
- Keep `branch` aligned with the branch checked out in that project worktree.
- If the matched project note has no `worktree`, create a dedicated one at `.worktrees/<project-slug>` and update the project note before substantive work.
- If the first-prompt hook reported multiple likely matches, ask the user to choose before doing substantive work.
- If no project matches and the work is only a small, cross-cutting fix or housekeeping batch, use `obsidian/Projects/Repo Maintenance.md` instead of creating a brand-new long-lived project note.
- If no project matches, create a new project note and dedicated worktree from the first-prompt router output, then confirm both in the first response.

## Project Page Checklist
- Update `## Current State` if the project status changed.
- Keep optional frontmatter `aliases` / `keywords` current when they would help the first-prompt router find this note again.
- Keep `branch` aligned with the dedicated project worktree branch.
- Keep `worktree` current and point it at the dedicated project worktree path.
- Keep frontmatter `pr` current for the active PR, if one exists.
- Keep `## Commits` near the top with `date + hash or pending + short summary`.
- Keep `## PRs` near the top with `PR number or pending + branch + short status`.
- Keep `## Key Files` focused on the active files for the project.
- Link every relevant debrief under `## Debriefs`.
- Append a dated entry under `## Log` for each meaningful batch.
- Move work out of `Repo Maintenance` into a dedicated project once it becomes multi-day, domain-specific, or large enough to deserve its own PR/review trail.

## Debrief Checklist
- Use `obsidian/Templates/Debrief.md`.
- Set `project: "[[Project Name]]"` in frontmatter.
- Add a `## Commits` section.
- Use `pending` when the commit hash does not exist yet, then backfill it later.

## Handoffs
- Only write an Obsidian handoff when work is paused mid-stream, blocked, or the user explicitly asks for a handoff.
- Save it at `obsidian/Handoffs/<Project> YYYY-MM-DD <Short Title>.md`.
- Start from `obsidian/Templates/Handoff.md`.
- Link active handoffs from the project note `## Handoffs` section.
- When work resumes or completes, update or clear the active handoff reference on the project page.
- This Obsidian handoff does not replace `plans/pause.md` or workflow-specific handoff files when those are required elsewhere in the repo.

## Commit Scope
- Stage Obsidian files for exactly one project per commit.
- Every staged debrief must declare the same project as the staged project note.
- If the guard blocks the commit, unstage unrelated Obsidian files instead of bypassing the hook.

## Output
- First response: confirm the matched project note was found and read, and confirm the project worktree that will be used for the session.
- Before commit: project note updated, matching debrief updated, staged Obsidian files scoped to one project.
