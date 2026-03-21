---
status: in-progress
priority: P1
branch: project/phase1-remediation-roadmap-design
base: main
pr:
started: "2026-03-21"
aliases:
  - phase1 remediation roadmap
keywords:
  - roadmap
  - phase-1
  - remediation
  - design
scope_paths:
  - docs/superpowers/specs/2026-03-21-phase1-remediation-roadmap-design.md
  - obsidian/Projects/Phase 1 Remediation Roadmap Design.md
  - obsidian/Debriefs/Phase 1 Remediation Roadmap Design *.md
---

## Current State

Dedicated planning branch/worktree for the Phase 1 remediation roadmap spec. Two review-driven revisions are committed, and one final cleanup pass is being applied before freezing the design for planning.

## Commits
- `c72bddc5` — 2026-03-21 — write the initial Phase 1 remediation roadmap spec and supporting Obsidian tracking files.
- `1d193bee` — 2026-03-21 — refine the roadmap by moving WAL to optional cleanup, widening Story 2 registry/codegen scope, and clarifying Story 3 as interface+wiring+math.
- `pending` — 2026-03-21 — finalize roadmap truthfulness: split WAL and EMCLOSE-006 out of the core regression lane, fix lane/count wording, strengthen contract-first proof rules, and use canonical repo paths.

## Key Files
- docs/superpowers/specs/2026-03-21-phase1-remediation-roadmap-design.md
- obsidian/Projects/Phase 1 Remediation Roadmap Design.md
- obsidian/Debriefs/Phase 1 Remediation Roadmap Design 2026-03-21.md

## Debriefs
- [[Phase 1 Remediation Roadmap Design 2026-03-21]]

## Log
### 2026-03-21
- Created a dedicated planning worktree and branch so the roadmap spec can be committed without widening the audit-note branch scope.
- Captured the approved design for a mergeable, safety-first remediation roadmap for all audited Phase 1 regressions.
- Chose a hard workflow-baseline precondition, four core remediation stories in risk order, and a separate optional WAL cleanup lane.
- Confirmed the dedicated planning worktree builds cleanly with `cargo build --workspace`.
- Incorporated user review that demotes WAL cleanup off the critical path, widens Story 2 to include reject-code surface alignment, and reframes Story 3 as interface+wiring+math work.
- Incorporated final review cleanup to separate optional WAL findings and the EMCLOSE-006 proof gap from the core regression lane, tighten contract wording, and replace shorthand paths with canonical repo paths.
