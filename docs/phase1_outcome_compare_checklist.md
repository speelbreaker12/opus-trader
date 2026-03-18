# Phase 1 Outcome Comparison Checklist

Purpose: compare `opus-trader` and `ralph` Phase 1 outcomes using the same criteria and reproducible artifacts.

## 1) Freeze snapshots

Capture exact refs first so comparison is repeatable:

```bash
git -C /Users/admin/Desktop/opus-trader rev-parse HEAD
git -C /Users/admin/Desktop/ralph rev-parse HEAD
```

Optional: use branch names/tags/SHAs with `--opus-ref` and `--ralph-ref`.

## 2) Run baseline comparison (no expensive gates)

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph
```

## 2b) Snapshot-isolation smoke check (non-HEAD refs)

Validate non-HEAD comparisons are analyzed from detached snapshots:

```bash
./scripts/check_phase1_compare_snapshot_isolation.sh \
  --opus /Users/admin/Desktop/opus-trader \
  --ralph /Users/admin/Desktop/ralph \
  --opus-ref phase1-compare-explicit-20260214-003126-opus \
  --ralph-ref phase1-compare-explicit-20260214-003126-ralph \
  --skip-meta-test
```

The script exits non-zero if a non-HEAD repo result has `path == analysis_path`.

CI also runs this check as `phase1-snapshot-isolation-smoke` with both repos set to the same checkout (`HEAD` vs `HEAD~1`) to assert non-HEAD snapshot behavior in automation.

What this gives:
- evidence-pack coverage (required + any-of evidence items),
- `tools/phase1_meta_test.py` result for both repos,
- Phase 1 PRD completion parity (`passes`, remaining, `needs_human_decision`),
- Phase 1 traceability parity (contract refs + `enforcing_contract_ats` coverage),
- operational readiness footprint parity (required status fields + alert metrics tokens),
- deterministic report + JSON under `artifacts/phase1_compare/<run_id>/`.

## 3) Add verification parity

Run quick verify in both repos under the same script:

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --run-quick-verify
```

If you need per-repo control, use:

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --run-quick-verify-opus
```

Supported per-repo toggles:
- `--run-quick-verify-opus`
- `--run-quick-verify-ralph`
- `--run-full-verify-opus`
- `--run-full-verify-ralph`

If trees are dirty, results are still useful for local signal but not release-grade. For release-grade comparison, use clean worktrees or CI clean checkout.
When quick verify runs, the report also adds gate-by-gate parity (detected gate headers + first failure line).

Optional full-verify parity (slow):

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --run-full-verify
```

The report also compares latest verify artifact gate rc/time parity from `artifacts/verify/*/*.rc` and `*.time`.

## 4) Add implementation churn context (optional)

Compare each repo against its own base branch:

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --opus-base origin/main \
  --ralph-base origin/main
```

This adds `git diff --shortstat` and changed-file counts to the report.

## 5) Add one identical scenario command (optional)

Run the same command in both repos for apples-to-apples timing/pass-fail:

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --scenario-cmd "cargo test -p soldier_core --test test_gate_ordering"
```

Use a command that exists in both repos.

This now adds behavioral parity extraction from scenario logs:
- reason codes seen,
- required status fields observed,
- dispatch-count values observed,
- rejection/blocked line counts.

## 6) Add flakiness/stability comparison (optional)

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --flaky-runs 3 \
  --flaky-cmd "cargo test -p soldier_core --test test_phase1_dispatch_auth"
```

If `--flaky-cmd` is omitted, flakiness uses `--scenario-cmd` when present, else defaults to `./plans/verify.sh quick`.

## 7) Decision rule

The report now includes an auto-weighted score table (`correctness/safety`, `performance`, `maintainability`).
Default weights are `60/25/15`, override with:

```bash
./scripts/compare_phase1_outcomes.sh \
  /Users/admin/Desktop/opus-trader \
  /Users/admin/Desktop/ralph \
  --weight-correctness 60 \
  --weight-performance 25 \
  --weight-maintainability 15
```

Use the weighted winner as the primary decision signal, and treat any scoring note as a risk flag requiring ref/coverage cleanup.

## 8) Report artifacts to review

- Markdown summary: `artifacts/phase1_compare/<run_id>/report.md`
- Machine-readable detail: `artifacts/phase1_compare/<run_id>/report.json`
- Command logs per repo: `artifacts/phase1_compare/<run_id>/<repo>/logs/*.log`
