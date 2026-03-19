---
project: "[[chairman-synthesis]]"
date: "2026-03-19"
---

## Commits
- pending — 2026-03-19 — plans: harden chairman synthesis and parallel review pipeline

## 0) What shipped
- Feature/behavior: Multiple correctness and robustness fixes across `chairman_synthesis.sh` and `parallel_review.sh` — PIPESTATUS bash 3.2 portability fix, transcript extraction logic rewrite, sidecar parser cross-pollination guard, dry-run prompt preservation, canonical read error handling, zero-findings warning, and distinct chairman failure exit code.
- Value (what problem it solves): PIPESTATUS[0] access resets the array in bash 3.2 (macOS default), causing unbound variable errors under set -u. Transcript extraction ran awk unconditionally then fell through to a second pass, producing duplicated content. Sidecar parser look-ahead could leak citation/description/fix from one finding heading into the next. Dry-run deleted the prompt file before the operator could inspect it. parallel_review.sh silently swallowed chairman failures into the aggregate exit code.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Unbound variable crash on macOS bash 3.2 when reading PIPESTATUS[1] after PIPESTATUS[0]; duplicated transcript content in chairman prompt due to unconditional awk + fallback; sidecar findings with wrong citation or description from adjacent heading.
- Time/token drain it caused: Debugging bash portability issues and investigating why sidecar findings had incorrect metadata.
- Workaround I used this session (exploit): Snapshot PIPESTATUS into a local array on one line; rewrite extraction as if/elif/else; add heading_pat break in look-ahead loop; guard description/fix with `not already set` checks.
- Next-agent default behavior (subordinate): Always capture PIPESTATUS into a local array in a single assignment before accessing individual elements.
- Permanent fix proposal (elevate): Add bash 3.2 compatibility to the project's shell lint/CI checks; add a sidecar parser unit test with adjacent findings to catch cross-pollination.
- Smallest increment: The two-file change as committed.
- Validation (proof it got better): Manual code review. No automated tests for these scripts exist yet.

## 2) Best follow-up
- Single best next step: Run a dry-run chairman synthesis with multi-tool artifacts to verify extraction and sidecar output end-to-end.
- 1-3 upgrades worth considering:
  - Add a bash 3.2 compatibility lint (e.g., shellcheck with explicit shell directive)
  - Extract the Python sidecar parser into a standalone file with pytest coverage for adjacent-heading edge cases
  - Add integration test for parallel_review.sh exit codes (0, 1, 3, 4)

## 3) Enforceable rules
- Always capture PIPESTATUS into a local array in one statement before accessing elements — bash 3.2 resets the array on first subscript access.
- Transcript extraction must use explicit priority: markers > frontmatter > raw. Never run awk unconditionally and then fall through.
- Sidecar parser look-ahead must stop at the next heading to prevent cross-pollination.
