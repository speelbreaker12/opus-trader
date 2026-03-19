---
project: "[[Obsidian Work Tracking]]"
date: "2026-03-19"
type: debrief
---

## What shipped
- Risk-class commit classification: replaced size-based tiers (trivial/light/full) with semantic classes (docs_only, obsidian_only, non_critical, critical) driven by which paths are touched
- Shared frontmatter parser: extracted `plans/lib/obsidian_frontmatter.py` to eliminate 3 duplicate `parse_frontmatter` implementations across context hook and scope guard
- Context hook worktree-mismatch warning: compares CWD to project note's `worktree` field, warns if editing in wrong worktree
- Context hook merged-PR detection: checks `gh pr view` for MERGED state, warns about stale branch
- Force-push blocker fix: removed special-case bypass for `--force-with-lease` that could silently skip all Level 1 checks; now handled as a single pattern with descriptive message
- Obsidian commit guard cleanup: replaced `recent_has_obsidian` (lookback-count based) with `branch_has_obsidian_update` (merge-base scoped), removed redundant "light tier" code paths
- Scope guard improved error messages: `base:` field missing now gives actionable instructions instead of terse `die`
- Pre-push frontmatter integrity hook: added conditional call to `post_rebase_frontmatter_check.sh` (guard for silent clobber after rebase)
- Commit skill docs: updated SKILLS/commit.md with obsidian tracking soft-gate instructions and risk-class descriptions

## Constraint
- Three independent copies of the frontmatter parser had diverged (context hook used `re.match`, one scope guard block used `str.split`). Any frontmatter format fix had to be applied three times. Extraction to a shared module was overdue.

## Follow-up
- Add unit tests for `obsidian_frontmatter.py` (parse edge cases: nested lists, multiline values, empty frontmatter)
- Wire up `post_rebase_frontmatter_check.sh` script (referenced in pre-push but may not exist yet)
- Test merged-PR detection behavior when `gh` CLI is unavailable

## Rules
- Change class must default to `critical` when classification fails (fail-closed)
- Frontmatter parser is single-source: never duplicate parse logic in calling scripts
- Context hook warnings (worktree mismatch, merged PR) are advisory only -- never block execution
