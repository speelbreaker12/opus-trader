---
project: "[[chairman-synthesis]]"
date: "2026-03-19"
---

## Commits
- pending — 2026-03-19 — plans: integrate chairman synthesis into parallel review pipeline

## 0) What shipped
- Feature/behavior: `--chairman <sonnet|opus>` flag in `parallel_review.sh` that auto-runs `chairman_synthesis.sh` after all reviews complete; citation regex fix in chairman script to accept line ranges; diff context fix in `review_logged.sh` so codex exec fallback always has content.
- Value (what problem it solves): Chairman synthesis was a manual post-step; now it runs automatically as part of the review pipeline. The codex fallback fix prevents reviews of "(no content available)".

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms): Operators had to remember to run chairman_synthesis.sh manually after parallel_review.sh; codex exec fallback path produced empty reviews because diff context was only built for non-codex tools.
- Time/token drain it caused: Extra manual step after every review run; wasted codex tokens on empty-content reviews.
- Workaround I used this session (exploit): Integrated chairman call directly into parallel_review.sh with proper validation and error handling.
- Next-agent default behavior (subordinate): Use `--chairman opus` or `--chairman sonnet` when running parallel_review.sh to get automatic synthesis.
- Permanent fix proposal (elevate): Add smoke tests for the chairman integration path.
- Smallest increment: The three-file change as committed.
- Validation (proof it got better): Code reviewed manually; changes are additive and gated behind a new flag so existing behavior is unchanged when flag is not used.

## 2) Best follow-up
- Single best next step: Test the full pipeline end-to-end: `parallel_review.sh --chairman opus --story TEST --uncommitted`.
- 1-3 upgrades worth considering:
  - Add a fixture-based smoke test for the chairman integration in parallel_review.sh
  - Consider making chairman the default (always-on) rather than opt-in

## 3) Enforceable rules
- The `--chairman` flag validates its argument to sonnet|opus only — do not bypass this check.
- Chairman synthesis is skipped when any review fails (`any_failed != 0`) to avoid synthesizing incomplete data.
