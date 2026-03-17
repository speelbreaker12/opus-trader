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
- If the first-prompt hook reported multiple likely matches, ask the user to choose before doing substantive work.
- If no project matches, propose a new project note name and create it from `obsidian/Templates/Project.md` when the user confirms.

## Project Page Checklist
- Update `## Current State` if the project status changed.
- Keep optional frontmatter `aliases` / `keywords` current when they would help the first-prompt router find this note again.
- Keep `## Commits` near the top with `date + hash or pending + short summary`.
- Keep `## Key Files` focused on the active files for the project.
- Link every relevant debrief under `## Debriefs`.
- Append a dated entry under `## Log` for each meaningful batch.

## Debrief Checklist
- Use `obsidian/Templates/Debrief.md`.
- Set `project: "[[Project Name]]"` in frontmatter.
- Add a `## Commits` section.
- Use `pending` when the commit hash does not exist yet, then backfill it later.

## Commit Scope
- Stage Obsidian files for exactly one project per commit.
- Every staged debrief must declare the same project as the staged project note.
- If the guard blocks the commit, unstage unrelated Obsidian files instead of bypassing the hook.

## Output
- First response: confirm the matched project note was found and read, or ask the user to choose/propose a new note.
- Before commit: project note updated, matching debrief updated, staged Obsidian files scoped to one project.
