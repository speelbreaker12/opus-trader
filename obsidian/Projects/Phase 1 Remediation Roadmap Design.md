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

Dedicated planning branch/worktree for the Phase 1 remediation roadmap spec. The initial spec commit is written, and the design is being tightened after user review without widening the audit-note branch.

## Commits
- `c72bddc5` — 2026-03-21 — write the initial Phase 1 remediation roadmap spec and supporting Obsidian tracking files.
- `pending` — 2026-03-21 — incorporate review feedback: move WAL to optional cleanup, widen Story 2 registry/codegen scope, and clarify Story 3 as interface+wiring+math.

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
