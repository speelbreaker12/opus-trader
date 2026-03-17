---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — conditional Obsidian handoff policy batch

## 0) What shipped
- Feature/behavior: Added a conditional Obsidian handoff policy, a dedicated `obsidian/Handoffs/` location, and a reusable handoff template tied into the project-page workflow guidance.
- Value (what problem it solves): Gives agents one explicit place to save a handoff when asked, while avoiding low-signal handoff boilerplate on every completed commit.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The repo already had `plans/pause.md` and workflow-specific handoff artifacts, but the Obsidian workflow had no defined place for a user-requested project handoff; that made it unclear where an agent should save a handoff inside the vault; requiring handoffs on every commit would have created noise instead of useful context.
- Time/token drain it caused: Re-explaining handoff expectations in chat and risking drift between project tracking notes, debriefs, and non-Obsidian workflow artifacts.
- Workaround I used this session (exploit): Kept the rule conditional, created a dedicated Obsidian handoff path/template, and documented that it complements rather than replaces existing workflow-required handoff files.
- Next-agent default behavior (subordinate): Only create an Obsidian handoff when work is paused, blocked, or explicitly handed off, and save it under `obsidian/Handoffs/` from the handoff template.
- Permanent fix proposal (elevate): Keep Obsidian handoffs as project-level continuity notes and keep workflow-required handoff artifacts separate so each handoff mechanism has a clear scope.
- Smallest increment: Add `obsidian/Templates/Handoff.md`, track `obsidian/Handoffs/`, and teach `/obsidian-workflow` plus AGENTS/project templates where and when to save a handoff.
- Validation (proof it got better): The Obsidian workflow now names one canonical handoff path and template, the project template exposes a `## Handoffs` section, and the current project note records the same rule and location.

## 2) Best follow-up
- Single best next step: Teach the first-prompt router to surface the most recent active handoff for the matched project when one exists, so resume sessions can start from it automatically.
- 1-3 upgrades worth considering:
- Add a tiny `README.md` under `obsidian/Handoffs/` if you want the folder purpose visible without opening the skill/template first.
- Add optional frontmatter `status: resolved` handling for handoff notes so stale handoffs are easier to retire explicitly.
- Extend the project note template with a short comment explaining when `## Handoffs` should stay empty versus linked.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Obsidian handoffs are conditional; do not create them for every finished batch.
- When the user asks for a handoff, save it under `obsidian/Handoffs/` from `obsidian/Templates/Handoff.md` and link it from the project page.
- Obsidian handoffs complement but do not replace `plans/pause.md` or any workflow-specific required handoff artifact.
