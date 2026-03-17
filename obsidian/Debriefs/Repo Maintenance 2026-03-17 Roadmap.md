---
project: "[[Repo Maintenance]]"
date: "2026-03-17"
---

## Commits
- pending — add a roadmap section to the Repo Maintenance project

## 0) What shipped
- Feature/behavior: Added a `## Roadmap` section to the `Repo Maintenance` project note.
- Value (what problem it solves): Makes the boundaries of maintenance work explicit so the fallback project stays useful instead of turning into a dumping ground.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The maintenance note existed, but it did not yet define what should remain there versus split out; maintenance work can easily sprawl without visible boundaries; the project page needed a place to record follow-up guardrails.
- Time/token drain it caused: More judgment calls in chat and a higher chance that unrelated work would accumulate under the maintenance bucket.
- Workaround I used this session (exploit): Added a `## Roadmap` section with explicit split-out and scope-control goals.
- Next-agent default behavior (subordinate): Read the maintenance roadmap before treating the fallback project as the right home for a task.
- Permanent fix proposal (elevate): Turn the roadmap boundaries into router and scope-guard behavior later.
- Smallest increment: Add the roadmap section and one matching debrief so the rule is visible on the project page itself.
- Validation (proof it got better): The maintenance project note now states when work belongs there and when it should become its own project.

## 2) Best follow-up
- Single best next step: Teach the router to prefer `Repo Maintenance` only for clearly small, generic cleanup prompts.
- 1-3 upgrades worth considering:
- Add `scope_paths` later if the maintenance project starts getting regular implementation work.
- Add a small-file threshold for maintenance PRs.
- Add an explicit “graduate to project” checklist if maintenance work crosses a size threshold.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- `Repo Maintenance` is for small, cross-cutting fixes and housekeeping only.
- Split work into a dedicated project once it becomes domain-specific or PR-sized.
- Keep the maintenance roadmap current so fallback-project boundaries stay visible.
