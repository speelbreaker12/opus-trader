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
- If `worktree_obsidian` is present, that path is the project-local Obsidian folder to jump into for context notes.
- If the matched project note has no `worktree`, create a dedicated one at `.worktrees/<project-slug>` and update the project note before substantive work.
- If `worktree_obsidian` does not exist, create `<worktree>/obsidian` for per-project notes so root-view links always have a target.
- If the first-prompt hook reported multiple likely matches, ask the user to choose before doing substantive work.
- If no project matches, create a new project note and dedicated worktree from the first-prompt router output, then confirm both in the first response.

## Project Page Checklist
- Update `## Current State` if the project status changed.
- Keep optional frontmatter `aliases` / `keywords` current when they would help the first-prompt router find this note again.
- Keep `branch` aligned with the dedicated project worktree branch.
- Keep `worktree` current and point it at the dedicated project worktree path.
- Keep `worktree_obsidian` current so root dashboard links can jump directly to project-local notes without manual setup.
- Keep `worktree_obsidian` in sync with actual directory creation; if absent or missing, create `<worktree>/obsidian` and update this field before edits.
- For no-mirror usage, `worktree_obsidian` is the only source of truth for click-through project local notes.
- Keep `## Commits` near the top with `date + hash or pending + short summary`.
- Keep `## Key Files` focused on the active files for the project.
- Link every relevant debrief under `## Debriefs`.
- Append a dated entry under `## Log` for each meaningful batch.

## Dashboard layout for click-through (no mirroring)
- Use project notes as the routing source of truth.
- A project note should include:
  - `worktree` (branch-local checkout path, e.g. `.worktrees/project-slug`)
  - `worktree_obsidian` (path to notes for that worktree, e.g. `.worktrees/project-slug/obsidian`)
- Build a single dashboard note in the root vault (for example `obsidian/Active Projects.md`) with one list item per project using:
  - project note link (`[[Project Name]]`)
  - worktree obsidian folder from `worktree_obsidian` rendered as a markdown link
- The router now refreshes this dashboard automatically after successful creation/refresh of a project worktree.
- If you changed project worktree metadata out of the router path, refresh deterministically by running:
  - `python3 .claude/scripts/refresh_active_projects_index.py --repo-root .`
  whenever `worktree` or `worktree_obsidian` changes.
- Never mirror branch-local notes into main; this keeps branch-local work-in-progress out of shared Obsidian context.

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
