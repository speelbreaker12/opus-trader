# Phase 1 Slice 6 Hybrid Merge Checklist

## Goal

Use this checklist to evaluate whether Ralph or Opus has the stronger Slice 6 implementation and to produce a defensible hybrid decision.

The checklist is for manual sign-off before any Slice 6 merge or cherry-pick.

## Scope

- Compare the same Slice 6 implementation window in both repos.
- Preserve strict evidence parity across both paths.
- Verify non-HEAD refs are executed from detached snapshots, never from the caller working tree.

## Inputs

- Opus repo path: `/Users/admin/Desktop/opus-trader`
- Ralph repo path: `/Users/admin/Desktop/ralph`
- Baseline pinned refs:
  - `phase1-compare-explicit-20260214-003126-opus`
  - `phase1-compare-explicit-20260214-003126-ralph`

## Prereqs

- Clean worktree for both repos or explicit intent to run with dirty state.
- `.py` runtime for `tools/phase1_compare.py`.
- Access to quick-verify gate dependencies in each repo snapshot.

## Baseline Comparison Run

```bash
python3 tools/phase1_compare.py \
  --opus /Users/admin/Desktop/opus-trader \
  --ralph /Users/admin/Desktop/ralph \
  --opus-ref phase1-compare-explicit-20260214-003126-opus \
  --ralph-ref phase1-compare-explicit-20260214-003126-ralph \
  --run-quick-verify \
  --skip-meta-test \
  --output /tmp/phase1_compare_slice6_hybrid/report.md
```

### Required go/no-go outputs

- Exit code `0`.
- `Blockers -> opus: 0` and `ralph: 0`.
- `phase1_compare` report exists:
  - `/tmp/phase1_compare_slice6_hybrid/report.md`
  - `/tmp/phase1_compare_slice6_hybrid/report.json`

## Snapshot Isolation Check

```bash
./scripts/check_phase1_compare_snapshot_isolation.sh \
  --opus /Users/admin/Desktop/opus-trader \
  --ralph /Users/admin/Desktop/ralph \
  --opus-ref phase1-compare-explicit-20260214-003126-opus \
  --ralph-ref phase1-compare-explicit-20260214-003126-ralph \
  --skip-meta-test
```

- Expected result: PASS message and non-HEAD repos must show `path != analysis_path`.

## Decision Signals (minimum)

### Correctness/Safety (must be tied/favorable)
- Required evidence completion count: `required_all_ok/required_all_total`
- `config_matrix_pass` vs `config_matrix_fail`
- Contract traceability deltas (`missing_enforcing_ats`, unknown refs)
- `determinism_unique_hashes` and `traceability_unique_intent_ids`

### Performance/Stability
- `verify_quick` must be green
- `scenario` and `flakiness` (if used) should not add risk
- `changed_files` and `diff_shortstat` should be within expected Slice 6 scope

### Maintainability / Merge Hygiene
- `missing_required_all` and `failed_any_of` should not increase without justification.
- `verify_artifacts_quick` run IDs should be captured for audit and traceability.
- New/known gaps must be documented as blockers with a decision to defer or fix.

## Pass/Fail Gate

Do not mark the merge decision as pass unless:

- both repos have `Blockers == 0` for the chosen comparison run, and
- `Block 1` (snapshot isolation) is PASS, and
- any additional manual decision notes are explicitly approved in `plans/phase1_comparison_todo.md`.

## Known Follow-ups

- Keep `plans/phase1_comparison_todo.md` current with:
  - any non-zero blockers,
  - evidence IDs,
  - remediation owner,
  - re-run timestamp.
