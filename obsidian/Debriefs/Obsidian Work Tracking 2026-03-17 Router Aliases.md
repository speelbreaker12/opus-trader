---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-17"
---

## Commits
- `55adc330` — router alias and keyword scoring batch

## 0) What shipped
- Feature/behavior: Added optional frontmatter `aliases` and `keywords` for project notes, taught the first-prompt router to score them, and seeded the project template plus the Obsidian Work Tracking note with those fields.
- Value (what problem it solves): Improves first-session project matching when the user uses shorthand or related terms that do not appear in the project note title.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): The router mostly depended on project titles plus note body text; shorthand phrasing that users remembered from prior sessions could miss the right note; the newly added workflow skill still depended on the router picking the right project first.
- Time/token drain it caused: Extra back-and-forth when the prompt and project-title wording diverged, plus a need to stuff more descriptive prose into `## Current State` just to help matching.
- Workaround I used this session (exploit): Added explicit alias/keyword frontmatter fields and scored them between project name and section-text matches.
- Next-agent default behavior (subordinate): When a project has stable shorthand names or recurring query terms, record them in `aliases` / `keywords` instead of overloading the log or current-state text.
- Permanent fix proposal (elevate): Keep router scoring extensible through explicit note metadata so project rediscovery improves without turning the matching logic into a brittle keyword soup.
- Smallest increment: Parse frontmatter, score aliases/keywords, add dedicated alias/keyword router tests, and seed the project template so new notes know where to declare them.
- Validation (proof it got better): The router test now includes alias-only and keyword-only match cases, and the current project note/template both declare the new metadata fields.

## 2) Best follow-up
- Single best next step: Add aliases/keywords to the other active project notes when those projects are next touched, so the router can benefit from the new metadata beyond this project.
- 1-3 upgrades worth considering:
- Surface alias/keyword hits in the router output separately from section-text hits when debugging matches.
- Add a tiny validation check that frontmatter `aliases` / `keywords` must be lists when present.
- Normalize suggested new project-note names with a repo-specific title-casing rule so no-match output is more consistent.

## 3) Enforceable rules
1-3 rules so the next agent doesn't repeat the constraint:
- Use `aliases` / `keywords` for router-discovery hints, not ad-hoc prose buried in `## Log`.
- Any router-scoring change must add or update explicit matching coverage in `plans/tests/test_obsidian_context_hook.sh`.
- Backfill `pending` commit hashes the next time the same project note/debrief pair is touched instead of creating stand-alone bookkeeping commits.
