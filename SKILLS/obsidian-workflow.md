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
- Treat the matched project note as the owner of the current worktree, branch, base, and PR metadata.
- If the first-prompt hook reported multiple likely matches, ask the user to choose before doing substantive work.
- If no project matches, propose a new project note name and create it from `obsidian/Templates/Project.md` when the user confirms.
- If the matched project note declares a different branch than the current branch/worktree, switch to that project’s worktree or create a new one before editing.
- If the current branch already has an open PR and the new task maps to a different project note, do not edit in place; create or switch to that project’s worktree first.

## Project Page Checklist
- Update `## Current State` if the project status changed.
- Keep frontmatter `branch`, `base`, and `pr` accurate for the owning worktree/branch/PR.
- Keep frontmatter `scope_paths` current and explicit enough for hook enforcement; do not rely on the hooks guessing intent from `## Key Files`.
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
- Before commit, run `git diff --cached --name-only` and confirm every staged file stays inside the active project note’s `scope_paths`.
- If anything is outside `scope_paths`, stop and split the work into the correct project/worktree/branch instead of widening the current commit.
- Stage Obsidian files for exactly one project per commit.
- Every staged debrief must declare the same project as the staged project note.
- If the guard blocks the commit, unstage unrelated Obsidian files instead of bypassing the hook.

## Push / PR Scope
- Before push or PR open, run `git diff --name-only origin/main...HEAD` (or the project note’s declared `base`) and confirm the full branch diff stays inside `scope_paths`.
- Never push a branch whose full diff crosses project scope, even if the last commit is clean.
- Use `plans/open_project_pr.sh` when creating the PR so the guard runs first and the resulting PR number is written back into the project note.

## Output
- First response: confirm the matched project note was found and read, or ask the user to choose/propose a new note.
- Before commit: project note updated, matching debrief updated, staged Obsidian files scoped to one project.
