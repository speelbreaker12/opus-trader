---
project: "[[Autoresearch]]"
date: "2026-03-18"
---

## Commits
- pending

## 0) What shipped
- Feature/behavior: Added contract review rendering guardrails so proposals from `sample_contract_patch` cannot be marked accepted in `--accepted-only` output.
- Value (what problem it solves): Prevents accidental inclusion of sample fixture output in CONTRACT patch artifacts.

## 1) Constraint (ONE)
- How it manifested (2-3 concrete symptoms):
  - Prior run notes showed fixture-only proposals from `sample_contract_patch` were being treated as regular accepted candidates.
  - Existing accepted-only flow could render a patch that included sample fixture content.
  - Manual review process had no automated barrier for this special-case path.
- Time/token drain it caused:
  - Extra manual review cycles and repeated safety checks before applying accepted-only patches.
- Workaround I used this session (exploit):
  - Added explicit runtime hard-fail in `--accepted-only` and dedicated regression test.
- Next-agent default behavior (subordinate):
  - Keep sample fixture proposals rejected unless moved into a first-party fixture with explicit promotion review.
- Permanent fix proposal (elevate):
  - Maintain fixture provenance checks in render-review for other special fixtures and report them in checklist outputs.
- Smallest increment:
  - Keep existing guard + checklist line in `CONTRACT_REVIEW_*.md`.
- Validation (proof it got better):
  - New regression test in `autoresearch/tests/test_contract_render_review.py` verifies accepted-only fails when `sample_contract_patch` is marked accepted.

## 2) Best follow-up
- Single best next step:
  - Update remaining contract harness baselines after sample fixture guard change is merged.
- 1-3 upgrades worth considering:
  - Review `autoressearch/skills/harness.sh` env defaults to remove unrelated `eval_exit` unbound failures.

## 3) Enforceable rules
- `rule: Keep sample fixture proposals rejected` / `trigger: any proposal._fixture_id == sample_contract_patch` / `prevents: accidental accepted-only sample patch inclusion` / `enforce: render_review.py --accepted-only decision validation`
- `rule: Keep proposal provenance explicit` / `trigger: non-main fixture IDs` / `prevents: hidden fixture drift in review outputs` / `enforce: proposals metadata and checklist review guidance`
