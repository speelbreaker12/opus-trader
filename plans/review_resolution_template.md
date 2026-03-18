# Review Resolution Template

Copy this into `artifacts/story/<STORY_ID>/review_resolution.md` and replace placeholders.

Story: <STORY_ID>
HEAD: <HEAD_SHA>
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
Cycle 1 review file: codex/<TIMESTAMP>_review.md
Cycle 2 review file: codex/<TIMESTAMP>_review.md

## Finding Disposition

Cycle 1 review: codex/<CYCLE1_TIMESTAMP>_review.md
Cycle 1 high-severity count: <N>

<!-- List EVERY P0/P1 finding from cycle 1. Each line must follow this exact format: -->
<!-- F-<N> | <P0|P1|P2> | <file:line> | <description> | <FIXED|DEFERRED|WONTFIX> | <evidence> -->
<!-- Gate requires: P0 cannot be DEFERRED or WONTFIX. DEFERRED must reference a debt item. -->
<!-- If cycle 1 had 0 high-severity findings, write: "No high-severity findings in cycle 1." -->

| ID | Severity | Location | Description | Disposition | Evidence |
|----|----------|----------|-------------|-------------|----------|
| F-1 | P1 | file.rs:42 | Brief description of finding | FIXED | commit abc1234 |
| F-2 | P2 | file.rs:55 | Brief description of finding | DEFERRED | debt D-001 target slice N |

Cycle 2 review: codex/<CYCLE2_TIMESTAMP>_review.md
Cycle 2 high-severity count: <N>
Cycle 2 new P0/P1 findings: 0
