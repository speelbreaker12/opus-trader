# Orphans and Gaps

## 1. Missing Documentation Artifacts (Minor)
- **Gap**: `plans/ideas.md` and `plans/pause.md` are referenced in the `ralph.sh` prompt (`read AGENTS.md + prd.json + progress.txt ... Append deferred ideas to plans/ideas.md`).
- **Status**: These files are not guaranteed to exist by `init.sh` or `bootstrap.sh`.
- **Impact**: If they don't exist, the agent might fail to write to them or create them implicitly (which is fine, but explicit is better).
- **Fix**: Add `touch plans/ideas.md` to `plans/init.sh` or `plans/bootstrap.sh`.

## 2. CI/Local Gate Drift Risk
- **Observation**: `plans/verify.sh` is the single source of truth. `plans/bootstrap.sh` creates a CI workflow that calls it.
- **Risk**: If `plans/verify.sh` depends on local-only tools (like specific `docker` setups or local secrets) not present in CI, the pipeline breaks.
- **Mitigation**: Ensure `verify.sh` gracefully handles missing optional tools or that CI environment matches local dev environment (e.g. devcontainer).

## 3. Contract Check Visibility
- **Observation**: `plans/contract_check.sh` and `plans/contract_review_validate.sh` were readable via `cat` but not `read_file`, suggesting they might be ignored by some tool configurations or standard ignore files not immediately obvious (or just a quirk of the agent environment).
- **Status**: They *do* exist and function correctly in the acceptance tests.
- **Action**: Verify if they are intended to be committed. `plans/bootstrap.sh` does *not* create them, but `plans/workflow_acceptance.sh` creates stubs for them. This implies they are expected to be part of the repo (Checked: they are present in the file list).

## 4. `plans/prd_lint.sh`
- **Observation**: Referenced by `cut_prd.sh` but not mandated by `ralph.sh`.
- **Status**: Exists. Used by Story Cutter.
- **Role**: Helper script, not critical path for the harness (harness uses `prd_schema_check.sh`).

## 5. Story Verify Allowlist
- **Observation**: `ralph.sh` references `plans/story_verify_allowlist.txt`.
- **Status**: Exists.
- **Note**: Ensure this file is populated if stories use custom verify commands, otherwise they will fail safe.

## Summary
The workflow is tight and well-defined. Most artifacts have clear producers and consumers. The only "orphans" are optional documentation files that are lazily created. The core logic in `ralph.sh` covers all bases (pre/post verify, contract review, schema check).
