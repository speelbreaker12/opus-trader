# Preflight Guard Diagnostics Design

Date: 2026-03-07
Status: Approved

## Goal

Improve `plans/legacy_layout_guard.sh` and `plans/readme_ci_parity_check.sh` so future preflight failures are immediately actionable:

- emit exact offending paths from both guards
- emit exact `file:line` evidence for forbidden README/CI references
- avoid broad or opaque failures that mask unrelated contract work

## Non-Goals

- No change to which canonical workflow entrypoints are required
- No change to `plans/preflight.sh` guard ordering or parallel execution model
- No changed-files-only scoping for these guards
- No weakening of fail-closed behavior

## Current Pain

- `plans/legacy_layout_guard.sh` collapses all active-path offenders into one line and all unlabeled-postmortem offenders into one line.
- `plans/readme_ci_parity_check.sh` reports missing tokens or forbidden regexes, but not the exact matching lines that triggered the failure.
- CI section parse failures can be opaque because the guard does not report which top-level job ids were actually discovered.
- Broad legacy-reference matching can catch workflow-history prose and make unrelated contract work look blocked by an unspecified workflow problem.

## Approved Design

### 1. Legacy Layout Guard

Keep the existing two invariants, but improve both precision and diagnostics.

For active legacy paths:

- collect exact repo-relative offenders
- fail with one path per line
- preserve deterministic order from the existing `forbidden_paths` list

For postmortems containing legacy references without the required archival label:

- narrow the legacy-reference matcher to explicit legacy command/path tokens rather than broad prose-only wording
- emit exact postmortem paths, one per line
- keep the existing archival label requirement unchanged

### 2. README/CI Parity Guard

Keep the current parity rules, but emit precise evidence.

For forbidden references:

- print exact `file:line` hits from `README.md` or `.github/workflows/ci.yml`
- keep the existing fail-closed forbidden-pattern policy

For required-token failures:

- keep the exact checked file and missing token in the failure
- do not downgrade missing-token failures into warnings

For CI section parsing:

- when the `verify` or `prd-story-gate` job section cannot be isolated, print the exact workflow path plus the discovered top-level job ids
- treat this as a guard failure, not a silent skip

## Validation

- Add targeted shell fixtures for `plans/legacy_layout_guard.sh` that prove:
  - active legacy paths are listed one per line
  - unlabeled postmortem offenders are listed one per line
  - broad prose-only matches no longer fail
- Add targeted shell fixtures for `plans/readme_ci_parity_check.sh` that prove:
  - forbidden README references emit exact `README.md:<line>` evidence
  - forbidden CI references emit exact `.github/workflows/ci.yml:<line>` evidence
  - missing/renamed CI job sections report discovered job ids
- Re-run both guard scripts in the real repo and confirm `plans/preflight.sh` surfaces the improved diagnostics cleanly.
