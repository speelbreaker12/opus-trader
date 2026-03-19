---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- `633c39d7` — obsidian workflow skill companion batch

## 0) What shipped
- Feature/behavior: Added a companion `/obsidian-workflow` skill, registered it in the skills index, and updated the first-prompt Obsidian router to point agents at it explicitly.
- Value (what problem it solves): Keeps the hooks as the enforcement layer while giving every new session a reusable checklist for what to read, update, and include on the relevant Obsidian project page and debrief.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The router could tell the agent which project note matched, but it did not provide a stable checklist for what to do with that note; Obsidian tracking requirements were split between hook output, AGENTS instructions, and prior chat context; this made the workflow easy to follow inconsistently across sessions.
- Time/token drain it caused: Re-explaining the project-page/debrief expectations in chat, then checking whether the current session actually recorded the same fields and sections as the previous one.
- Workaround I used this session (exploit): Added a repo-local skill as the checklist source of truth and taught the router to point at it in every first-response branch.
- Next-agent default behavior (subordinate): When the router references `/obsidian-workflow`, use it as the checklist companion before updating the matched project page or its debrief.
- Permanent fix proposal (elevate): Keep hooks responsible for enforcement and project matching, and keep the skill responsible for the human-readable workflow/checklist so both layers stay narrow and easy to change.
- Smallest increment: Add the wrapper skill, the canonical skill doc, router references, and test coverage proving the hint appears in single-match, ambiguous, and no-match outputs.
- Validation (proof it got better): The router test now asserts the companion-skill hint and checklist instruction are present in all first-message branches, and the skills index checker validates the new skill path is tracked correctly.

## 2) Best follow-up
- Single best next step: Add lightweight aliases or keywords to project notes so the router can match projects more accurately without expanding the prompt-scoring logic too far.
- 1-3 upgrades worth considering:
- Update the project template so `## Key Files` and `## Commits` phrasing stays aligned with `/obsidian-workflow`.
- Add a small smoke test that reads the skill wrapper and verifies it still points at `SKILLS/obsidian-workflow.md`.
- Extend the router to mention the suggested new project-note filename in a more deterministic title-cased format when there is no match.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Keep Obsidian routing enforcement in hooks and keep the workflow checklist in `/obsidian-workflow`; do not move both concerns into one layer.
- If the first-prompt router mentions `/obsidian-workflow`, the agent must treat it as the checklist for project-note and debrief updates in that session.
- Any change to the router text that references a skill must be covered by `plans/tests/test_obsidian_context_hook.sh` and `scripts/check_skills_index.py`.
