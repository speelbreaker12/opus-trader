# PRD Gate Ref/Pass Hardening Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Close the proven false-fail and false-pass gaps in `plans/prd_ref_check.sh` and `plans/prd_set_pass.sh` without changing the normative pass-flip contract in `specs/WORKFLOW_CONTRACT.md`.

**Architecture:** Keep both gate scripts in Bash with the existing inline Python structure in `prd_ref_check.sh`. Add focused failing shell regressions first, then implement the smallest parser and validation changes needed: `ROADMAP.md` ref support plus boundary-aware numeric section matching in `prd_ref_check.sh`, and explicit CLI validation plus a portable PRD-integrity guard in `prd_set_pass.sh`. Because these are workflow/harness files, keep new regression coverage wired into the verification surface and finish with workflow verification, code review, and full verify.

**Tech Stack:** Bash 3.2-compatible shell, inline Python 3, `jq`, existing `plans/tests/*.sh` fixture pattern, workflow verification via `./plans/workflow_verify.sh` and `./plans/verify.sh full`.

---

## Validated Baseline

- Reviewed against repo `5f80fd4fcf09` on `wip/main-pre-sync-20260304`.
- `specs/WORKFLOW_CONTRACT.md` is the normative source for pass-flip semantics; it explicitly keeps the `policy/certification` exemption for `passes=true`.
- `specs/SOURCE_OF_TRUTH.md` forbids repo-root `CONTRACT.md`; any plan must keep `specs/CONTRACT.md` canonical.
- `plans/prd_ref_check.sh` currently expands `EXTRA_CONTRACT_FILES[@]` under `set -u`; temp fixtures must seed at least one extra contract file or they will fail before hitting the roadmap assertions.
- `plans/prd_slice_prepare.sh` already recognizes `ROADMAP.md` / `P0-*`-style roadmap refs from both `contract_refs` and `plan_refs`, so `prd_ref_check.sh` is the current drift point on both surfaces.
- `plans/preflight.sh` uses explicit test lists. If a new harness regression file is added, it must be registered there or verify will not run it.
- `plans/tests/test_preflight_fixture_profiles.sh` hardcodes the full-only fixture membership and count, so any new preflight fixture entry must update that meta-test in the same change.
- `plans/tests/test_prd_set_pass.sh` already contains a `PATH`-based fake-`git` pattern for mid-run state changes; reuse that pattern for a PRD-mutation regression rather than inventing a new hook.

## Implementation Order

1. Add dedicated `prd_ref_check` regression coverage and wire it into full verify.
2. Implement `ROADMAP.md` ref resolution and boundary-aware numeric section matching.
3. Add `prd_set_pass` regressions for missing option values and mid-run PRD mutation.
4. Implement `prd_set_pass` hardening with portable hashing and deterministic diagnostics.
5. Run review + workflow verification + full verify.

### Task 1: Add `prd_ref_check` Ref-Resolution Regressions

**Files:**
- Create: `plans/tests/test_prd_ref_check_refs.sh`
- Modify: `plans/preflight.sh`
- Modify: `plans/tests/test_preflight_fixture_profiles.sh`
- Modify: `plans/workflow_files_allowlist.txt`
- Modify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Write the failing test**

Create `plans/tests/test_prd_ref_check_refs.sh` using the same temporary-fixture pattern as the other shell tests.

Seed the fixture with a minimal extra contract file so the current checker reaches the intended roadmap assertions instead of failing on empty `EXTRA_CONTRACT_FILES` expansion:

```bash
cat > "$tmp_repo/docs/contract_kernel.json" <<'EOF'
{}
EOF
```

Include three focused cases:

1. `ROADMAP.md` ref case in both `contract_refs` and `plan_refs`:

```bash
tmp_repo="$tmp_dir/repo-roadmap"
mkdir -p "$tmp_repo/specs" "$tmp_repo/docs"
cat > "$tmp_repo/specs/CONTRACT.md" <<'EOF'
# Contract
AT-001
EOF
cat > "$tmp_repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Plan
## Global Non-Negotiables
EOF
cat > "$tmp_repo/docs/ROADMAP.md" <<'EOF'
# ROADMAP
## P0-A Launch Policy Baseline
EOF
cat > "$tmp_repo/docs/contract_kernel.json" <<'EOF'
{}
EOF
cat > "$tmp_repo/prd.json" <<'EOF'
{"items":[
  {"id":"S0-100","story_ref":"P0-A prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-101","story_ref":"P0-B prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-102","story_ref":"P0-C prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-103","story_ref":"P0-D prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-104","story_ref":"P0-E prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-105","story_ref":"P0-F prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-200","story_ref":"Infra roadmap contract ref stub","category":"infra","contract_refs":["ROADMAP.md P0-A Launch Policy Baseline"],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-201","story_ref":"Infra roadmap plan ref stub","category":"infra","contract_refs":[],"plan_refs":["ROADMAP.md P0-A Launch Policy Baseline"],"acceptance":[],"verify":[],"enforcing_contract_ats":[]}
]}
EOF
```

Run the checker from inside `"$tmp_repo"` so its relative file lookup resolves the temp `specs/` and `docs/` tree.

2. Bare roadmap anchor case:

```bash
cat > "$tmp_repo/prd.json" <<'EOF'
{"items":[
  {"id":"S0-100","story_ref":"P0-A prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-101","story_ref":"P0-B prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-102","story_ref":"P0-C prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-103","story_ref":"P0-D prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-104","story_ref":"P0-E prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-105","story_ref":"P0-F prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-202","story_ref":"Infra roadmap bare-anchor stub","category":"infra","contract_refs":[],"plan_refs":["P0-A Launch Policy Baseline"],"acceptance":[],"verify":[],"enforcing_contract_ats":[]}
]}
EOF
```

3. Numeric section-boundary case:

```bash
cat > "$tmp_repo/specs/CONTRACT.md" <<'EOF'
# Contract
## 12.2 Something Else
## 2.21 Neighbor
## 2.2.1 Nested
EOF
cat > "$tmp_repo/prd.json" <<'EOF'
{"items":[
  {"id":"S0-100","story_ref":"P0-A prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-101","story_ref":"P0-B prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-102","story_ref":"P0-C prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-103","story_ref":"P0-D prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-104","story_ref":"P0-E prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-105","story_ref":"P0-F prereq stub","contract_refs":[],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]},
  {"id":"S0-201","story_ref":"Boundary ref stub","contract_refs":["CONTRACT.md 2.2 Missing Section"],"plan_refs":[],"acceptance":[],"verify":[],"enforcing_contract_ats":[]}
]}
EOF
```

Assert the current checker:
- reaches the actual roadmap assertions instead of crashing on fixture bootstrap
- fails the roadmap `contract_refs` and `plan_refs` cases even though `docs/ROADMAP.md` exists
- fails the bare `P0-A Launch Policy Baseline` form even though `plans/prd_slice_prepare.sh` already recognizes that anchor style
- incorrectly passes or resolves the `2.2` case against nearby sections

**Step 2: Run the targeted test to verify it fails**

Run: `bash plans/tests/test_prd_ref_check_refs.sh`  
Expected: `FAIL` under current behavior.

**Step 3: Register the new test in the workflow verification surface**

Add the new file to `FULL_ONLY_REVIEW_FIXTURE_TESTS` in `plans/preflight.sh`, not the smoke list. This keeps quick preflight churn down while still ensuring the new regression is exercised by `./plans/verify.sh full`.

Because fixture membership is asserted mechanically, update these meta-tests in the same task:
- `plans/tests/test_preflight_fixture_profiles.sh` (new fixture entry + `full_only_count`)
- `plans/workflow_files_allowlist.txt` and `plans/tests/test_workflow_allowlist_coverage.sh` if the repo continues to treat new workflow/harness tests as allowlisted workflow surface files

**Step 4: Re-run the test registration check**

Run:

```bash
bash -n plans/preflight.sh plans/tests/test_prd_ref_check_refs.sh plans/tests/test_preflight_fixture_profiles.sh plans/tests/test_workflow_allowlist_coverage.sh
bash plans/tests/test_preflight_fixture_profiles.sh
bash plans/tests/test_workflow_allowlist_coverage.sh
```

Expected: syntax check passes.

**Step 5: Commit**

```bash
git add plans/tests/test_prd_ref_check_refs.sh plans/preflight.sh plans/tests/test_preflight_fixture_profiles.sh plans/workflow_files_allowlist.txt plans/tests/test_workflow_allowlist_coverage.sh
git commit -m "test: add prd ref check regression coverage"
```

### Task 2: Implement `prd_ref_check` Roadmap + Boundary Matching

**Files:**
- Modify: `plans/prd_ref_check.sh`
- Modify: `plans/prd_gate_help.md`
- Verify: `plans/tests/test_prd_ref_check_refs.sh`
- Verify: `plans/tests/test_prd_gate.sh`

**Step 1: Write the minimal failing assertions into the new test**

Extend `plans/tests/test_prd_ref_check_refs.sh` so it expects:
- roadmap `contract_refs` case exits `0` once `docs/ROADMAP.md` is present
- roadmap `plan_refs` case exits `0` once `docs/ROADMAP.md` is present
- bare `P0-A Launch Policy Baseline` case exits `0` for a `policy` or `infra` story once `docs/ROADMAP.md` is present
- numeric boundary case exits `1` with `unresolved contract_ref`

**Step 2: Run the targeted tests and confirm failure**

Run:

```bash
bash plans/tests/test_prd_ref_check_refs.sh
bash plans/tests/test_prd_gate.sh
```

Expected:
- the new ref-check test fails
- `test_prd_gate.sh` still passes on the current baseline

**Step 3: Implement the smallest parser changes**

In `plans/prd_ref_check.sh`:

1. Resolve roadmap input before entering Python:

```bash
ROADMAP_FILE=""
if [[ -f "docs/ROADMAP.md" ]]; then
  ROADMAP_FILE="docs/ROADMAP.md"
elif [[ -f "ROADMAP.md" ]]; then
  ROADMAP_FILE="ROADMAP.md"
fi
```

Pass `"$ROADMAP_FILE"` into the Python block separately from the extra contract files.

2. Split the haystacks:
- `contract_haystack`
- `plan_haystack`
- `roadmap_haystack` (empty when no roadmap file exists)

3. Teach `strip_prefix()` to drop `ROADMAP.md` / `docs/ROADMAP.md`.

4. Add a helper that decides whether a ref should target the roadmap:

```python
roadmap_anchor_re = re.compile(r'^P\d+-[A-Z]\b', re.IGNORECASE)

def is_roadmap_ref(item: dict, ref: str) -> bool:
    category = str(item.get('category', '')).lower()
    s = str(ref).strip()
    return (
        category in ('policy', 'infra')
        and ('ROADMAP.MD' in s.upper() or roadmap_anchor_re.match(strip_prefix(s)) is not None)
    )
```

5. Fail closed if a roadmap ref is used but no roadmap file is present:

```python
if is_roadmap_ref(item, ref) and not roadmap_haystack:
    unresolved.append((item_id, 'contract', ref))
    continue
```

6. Route both `contract_refs` and `plan_refs` through `roadmap_haystack` when `is_roadmap_ref(item, ref)` is true. Keep the current fail-closed behavior when a roadmap ref is used but `ROADMAP.md` is absent.

7. Replace plain substring matching for numeric section IDs with a dedicated helper:

```python
numeric_section_re = re.compile(r'^[0-9]+(?:\.[0-9A-Z]+)*$', re.IGNORECASE)

def candidate_in_haystack(candidate: str, haystack: str) -> bool:
    if numeric_section_re.fullmatch(candidate):
        return bool(re.search(r'(?<![0-9.])' + re.escape(candidate) + r'(?![0-9.])', haystack))
    return candidate in haystack
```

Then call `candidate_in_haystack()` from `resolve_ref()`.

8. Update `plans/prd_gate_help.md` so supported `contract_refs` and `plan_refs` explicitly include roadmap refs for `policy/infra` stories, for example:

```text
ROADMAP.md P0-A Launch Policy Baseline
P0-A Launch Policy Baseline
```

Keep the note that prose-heavy refs are discouraged.

**Step 4: Re-run the targeted tests**

Run:

```bash
bash plans/tests/test_prd_ref_check_refs.sh
bash plans/tests/test_prd_gate.sh
./plans/prd_ref_check.sh plans/prd.json
```

Expected:
- new ref-check regression passes
- existing PRD gate smoke stays green
- current repo `plans/prd.json` still resolves successfully

**Step 5: Commit**

```bash
git add plans/prd_ref_check.sh plans/prd_gate_help.md plans/tests/test_prd_ref_check_refs.sh plans/preflight.sh
git commit -m "fix: harden prd ref resolution"
```

### Task 3: Add `prd_set_pass` Regression Coverage

**Files:**
- Modify: `plans/tests/test_prd_set_pass.sh`

**Step 1: Write the failing tests**

Add four focused cases to `plans/tests/test_prd_set_pass.sh`:

1. Missing `--artifacts-dir` value:

```bash
set +e
missing_artifacts_arg_output="$(
  cd "$ROOT" && "$SCRIPT" "$story_id" true --artifacts-dir 2>&1
)"
missing_artifacts_arg_rc=$?
set -e
[[ "$missing_artifacts_arg_rc" -eq 2 ]] || fail "expected exit 2 for missing --artifacts-dir value"
echo "$missing_artifacts_arg_output" | grep -Fq "ERROR: --artifacts-dir requires a value" || fail "missing artifacts-dir value diagnostic"
```

2. Missing `--contract-review` value:

```bash
[[ "$missing_contract_arg_rc" -eq 2 ]] || fail "expected exit 2 for missing --contract-review value"
echo "$missing_contract_arg_output" | grep -Fq "ERROR: --contract-review requires a value" || fail "missing contract-review value diagnostic"
```

3. Mid-run PRD mutation:
- Reuse the existing fake-`git` wrapper pattern.
- On the second `git rev-parse HEAD`, mutate the PRD file before returning the same HEAD.

Example wrapper sketch:

```bash
if [[ "$#" -ge 2 && "$1" == "rev-parse" && "$2" == "HEAD" ]]; then
  if [[ "$count" -eq 2 ]]; then
    python3 - <<'PY'
import json, os
path = os.environ["TEST_MUTATE_PRD_FILE"]
data = json.load(open(path))
data["items"][0]["enforcement_point"] = "MUTATED"
json.dump(data, open(path, "w"))
PY
  fi
  printf '%s\n' "${TEST_GIT_HEAD:?missing TEST_GIT_HEAD}"
  exit 0
fi
```

Assert:
- exit is non-zero with a deterministic mutation diagnostic
- `passes` remains `false`

4. Late mutation before the final rewrite:
- Add a second mutation case that changes the live PRD after the initial integrity snapshot is captured and after the final `HEAD` re-check, but before the rewrite is committed.
- Use a `PATH` wrapper around the last external command in the rewrite path (for example `jq` or `mv`) so the test proves the final read/write window is closed rather than only the earlier `git rev-parse HEAD` window.

Assert:
- exit is non-zero with the same deterministic mutation diagnostic
- `passes` remains `false`

**Step 2: Run the targeted tests and confirm failure**

Run: `bash plans/tests/test_prd_set_pass.sh`  
Expected: the new missing-arg and both mutation cases fail on the current script.

**Step 3: Keep the test runtime scoped**

Do not add a new test file here. Extend the existing `plans/tests/test_prd_set_pass.sh`, which is already wired into `FULL_ONLY_REVIEW_FIXTURE_TESTS`.

**Step 4: Commit**

```bash
git add plans/tests/test_prd_set_pass.sh
git commit -m "test: add prd set pass hardening regressions"
```

### Task 4: Implement `prd_set_pass` Hardening

**Files:**
- Modify: `plans/prd_set_pass.sh`
- Verify: `plans/tests/test_prd_set_pass.sh`

**Step 1: Run the failing test suite once more before editing**

Run: `bash plans/tests/test_prd_set_pass.sh`  
Expected: confirms the failures are real and reproducible.

**Step 2: Add explicit option-value validation**

Patch the option parser to validate before `shift 2`:

```bash
--artifacts-dir)
  [[ -n "${2:-}" ]] || { echo "ERROR: --artifacts-dir requires a value" >&2; exit 2; }
  ARTIFACTS_DIR="$2"
  shift 2
  ;;
--contract-review)
  [[ -n "${2:-}" ]] || { echo "ERROR: --contract-review requires a value" >&2; exit 2; }
  CONTRACT_REVIEW_FILE="$2"
  shift 2
  ;;
```

**Step 3: Add a portable PRD integrity helper and snapshot-based rewrite**

Do not use GNU-only `sha256sum` directly. Add a small helper that works on macOS and Linux:

```bash
file_sha256() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}
```

After the lock is acquired and JSON validity is proven:
- capture an immutable snapshot of `"$PRD_FILE"` into a temp file
- compute the integrity hash from the snapshot
- run all subsequent `jq` reads against the snapshot, not the live PRD file
- extend `cleanup()` to delete the snapshot temp file on every exit path

```bash
prd_snapshot="$(mktemp)"
cp "$PRD_FILE" "$prd_snapshot"
prd_sha_start="$(file_sha256 "$prd_snapshot")"
```

Then, after the existing final `HEAD` re-check and immediately before the final replace, compare the live file hash against the snapshot hash and build the updated JSON from the snapshot:

```bash
prd_sha_end="$(file_sha256 "$PRD_FILE")"
if [[ "$prd_sha_start" != "$prd_sha_end" ]]; then
  echo "ERROR: PRD modified during validation: $PRD_FILE" >&2
  exit 7
fi

jq --arg id "$ID" --argjson status "$STATUS" '
  .items = (.items | map(if .id == $id then .passes = $status else . end))
' "$prd_snapshot" > "$tmp"
```

Keep the current pass semantics unchanged; this is a consistency guard only. The snapshot avoids reading partially-mutated live state during the final rewrite, and the final hash check keeps the write fail-closed if the live PRD changed mid-run.

**Step 4: Optional cleanup while the file is open**

If the touched line stays isolated and the diff remains small, remove the `2>&1` from the external-manifest invocation:

```bash
if "${gate_cmd[@]}" "$gate_type" "$ID" "$slice_prefix" --manifest "$manifest_path"; then
```

Treat this as opportunistic cleanup only. Do not expand scope if it causes test churn.

**Step 5: Re-run the targeted tests**

Run:

```bash
bash plans/tests/test_prd_set_pass.sh
```

Expected: full pass, including the new missing-arg and PRD-mutation cases.
Expected: full pass, including the new missing-arg case and both PRD-mutation cases.

**Step 6: Commit**

```bash
git add plans/prd_set_pass.sh plans/tests/test_prd_set_pass.sh
git commit -m "fix: harden prd set pass validation"
```

### Task 5: Workflow Verification, Review, and Final Verify

**Files:**
- Verify: `plans/prd_ref_check.sh`
- Verify: `plans/prd_set_pass.sh`
- Verify: `plans/preflight.sh`
- Verify: `plans/prd_gate_help.md`
- Verify: `plans/tests/test_prd_ref_check_refs.sh`
- Verify: `plans/tests/test_prd_set_pass.sh`
- Verify: `plans/tests/test_preflight_fixture_profiles.sh`
- Verify: `plans/workflow_files_allowlist.txt`
- Verify: `plans/tests/test_workflow_allowlist_coverage.sh`

**Step 1: Run the focused regression stack**

Run:

```bash
bash plans/tests/test_prd_ref_check_refs.sh
bash plans/tests/test_prd_gate.sh
bash plans/tests/test_prd_set_pass.sh
bash plans/tests/test_preflight_fixture_profiles.sh
bash plans/tests/test_workflow_allowlist_coverage.sh
```

Expected: all pass.

**Step 2: Run workflow verification**

Run:

```bash
./plans/workflow_verify.sh
```

Expected: pass. This catches script syntax + quick verify regressions on the workflow surface.

**Step 3: Run code review before final verify**

Use the repo-default review step for significant harness edits:
- run `code-review-expert` on the current diff
- address any P0/P1/P2 findings

If fixes are made after review, re-run the focused regressions before continuing.

**Step 4: Run final full verify**

Run:

```bash
./plans/verify.sh full
```

Expected: pass with a new artifact directory under `artifacts/verify/<run_id>/`.

**Step 5: Capture final evidence**

Record in `plans/progress.txt`:
- commands run
- final verify artifact path
- test files touched
- whether `2>&1` cleanup was included or deferred

**Step 6: Commit**

```bash
git add plans/progress.txt
git commit -m "chore: record prd gate hardening verification"
```

## Deferred Work

- Parsing `docs/contract_kernel.json` structurally instead of concatenating raw JSON text into the contract haystack.
- Generalizing the hardcoded `S8-020` compact-CSP exemption if it proves to be a repeated pattern.
- Reworking `extract_health_keys()` / `extract_status_csp_keys()` block extraction to avoid fixed byte windows.

## Verification Sequence

1. `bash plans/tests/test_prd_ref_check_refs.sh`
2. `bash plans/tests/test_prd_gate.sh`
3. `bash plans/tests/test_prd_set_pass.sh`
4. `bash plans/tests/test_preflight_fixture_profiles.sh`
5. `bash plans/tests/test_workflow_allowlist_coverage.sh`
6. `./plans/workflow_verify.sh`
7. `./plans/verify.sh full`

## Evidence To Collect

- Failing and passing output for the roadmap ref regression.
- Failing and passing output for the roadmap `plan_refs` regression.
- Failing and passing output for the bare `P0-A Launch Policy Baseline` regression.
- Failing and passing output for the numeric section-boundary regression.
- Failing and passing output for missing `--artifacts-dir` / `--contract-review` values.
- Failing and passing output for the mid-run PRD mutation regression.
- Failing and passing output for the late-mutation-before-final-rewrite regression.
- Passing output for `plans/tests/test_preflight_fixture_profiles.sh`.
- Passing output for `plans/tests/test_workflow_allowlist_coverage.sh`.
- Final full-verify artifact directory under `artifacts/verify/<run_id>/`.

## Done Criteria

- `plans/tests/test_prd_ref_check_refs.sh` reaches the intended roadmap assertions without failing on fixture bootstrap.
- `prd_ref_check.sh` accepts valid roadmap refs for `policy/infra` stories in both `contract_refs` and `plan_refs`, for both `ROADMAP.md ...` and bare `P0-A ...` forms, and still fails closed when roadmap refs are used without a roadmap file.
- Numeric section refs are matched by section boundary, not by raw substring collision.
- `prd_set_pass.sh` emits deterministic option-value diagnostics, validates against a locked snapshot, and rejects a PRD that changes during validation, including the final rewrite window.
- All new regression coverage and workflow-surface bookkeeping updates are self-proving via the dedicated preflight/allowlist meta-tests.
- `code-review-expert` review is completed and `./plans/verify.sh full` passes.
