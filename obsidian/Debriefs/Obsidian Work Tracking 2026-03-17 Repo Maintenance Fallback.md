---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- pending — add a shared Repo Maintenance fallback for minor fixes

## 0) What shipped
- Feature/behavior: Added workflow guidance to reuse a shared `Repo Maintenance` project note for small, cross-cutting fixes instead of creating a brand-new project note every time.
- Value (what problem it solves): Reduces project-note sprawl while still keeping minor work tracked somewhere explicit and searchable.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The router/project workflow assumed unmatched work should become a new project note; that would create too many low-value project pages for tiny fixes; agents lacked a sanctioned fallback bucket for miscellaneous maintenance work.
- Time/token drain it caused: Repeated project-note creation for trivial batches and extra bookkeeping noise in the vault.
- Workaround I used this session (exploit): Added a documented fallback to `obsidian/Projects/Repo Maintenance.md` for small, cross-cutting fixes and housekeeping work.
- Next-agent default behavior (subordinate): Use `Repo Maintenance` for minor fixes unless the work has enough scope or continuity to justify a dedicated project note.
- Permanent fix proposal (elevate): Keep one explicit maintenance project as the catch-all for small batches and reserve new project notes for genuinely distinct streams of work.
- Smallest increment: Update the skill/AGENTS guidance and seed the maintenance project note separately.
- Validation (proof it got better): Future small-fix sessions can route to a known maintenance project instead of creating one-off notes by default.

## 2) Best follow-up
- Single best next step: Seed the actual `Repo Maintenance` project note with aliases and keywords so the first-prompt router can find it reliably.
- 1-3 upgrades worth considering:
- Add a router preference that suggests `Repo Maintenance` when a no-match prompt looks like generic cleanup or minor follow-up work.
- Add scope rules later so `Repo Maintenance` stays small and does not become a dumping ground for full projects.
- Add a short note on when to split work back out of `Repo Maintenance` into a dedicated project.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Use `Repo Maintenance` for small, cross-cutting fixes that do not justify a dedicated long-lived project note.
- Create a new project note only when the work is distinct enough to need its own branch/PR/review trail.
- Split work back out of `Repo Maintenance` once it becomes multi-day, domain-specific, or PR-sized on its own.
