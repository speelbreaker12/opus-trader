---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — add a dedicated `## PRs` section to project pages

## 0) What shipped
- Feature/behavior: Added a dedicated `## PRs` section to the project template and workflow guidance, and recorded the active PR on the Obsidian Work Tracking page.
- Value (what problem it solves): Makes active and historical PR scope visible on the project page instead of burying PR state only in frontmatter or chat.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Project notes already tracked branches and commits but not PR history in a readable section; open PR state could drift away from the project note; reviewers had to infer whether a project already had an active PR from branch names or chat context.
- Time/token drain it caused: Extra checks against GitHub and repeated chat clarification about whether a project already had a PR open.
- Workaround I used this session (exploit): Added a `## PRs` section near the top of project pages and documented how to keep it current alongside `pr:` frontmatter.
- Next-agent default behavior (subordinate): Update `## PRs` whenever a project opens, updates, or closes a PR.
- Permanent fix proposal (elevate): Treat project-note PR history as a first-class tracking surface alongside commits and debriefs.
- Smallest increment: Add the section to the project template, teach the workflow guidance to maintain it, and seed the current project note with the active PR.
- Validation (proof it got better): The active project note now shows PR `#213` directly on the page and the template/workflow docs require the same structure for future projects.

## 2) Best follow-up
- Single best next step: Teach future scope guards to compare the active project note `## PRs` section and `pr:` frontmatter against the current branch before push.
- 1-3 upgrades worth considering:
- Add `base` and `head` details to `## PRs` entries when branch discipline gets stricter.
- Add a helper that writes the opened PR number back to the project page automatically after `gh pr create`.
- Add a pre-push warning if a project note has no `## PRs` entry while the branch already has an open PR.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Project notes should carry a `## PRs` section near the top, not just a `pr:` frontmatter field.
- When a PR is opened or updated, record it on the project page with PR number, branch, and short status.
- Keep frontmatter `pr` aligned with the active entry in `## PRs`.
