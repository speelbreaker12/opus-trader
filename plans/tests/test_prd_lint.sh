#!/usr/bin/env bash

set -e

repo_root="$(cd "$(dirname "$0")/../.." && pwd)"
lint_script="$repo_root/plans/prd_lint.sh"

tmp_dir=$(mktemp -d)
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

cd "$tmp_dir"
git init -q
git config core.hooksPath /dev/null

mkdir -p plans
touch touch.txt

echo '#!/usr/bin/env bash' > plans/verify.sh
chmod +x plans/verify.sh
cp "$repo_root/plans/prd_schema_check.sh" plans/prd_schema_check.sh
chmod +x plans/prd_schema_check.sh

cat <<'JSON' > plans/prd.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-001",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Missing verify gate",
      "category": "acceptance",
      "description": "Missing verify gate",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["echo ok"],
      "evidence": ["touch.txt exists"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": true
    },
    {
      "id": "S1-002",
      "priority": 2,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Contract mismatch",
      "category": "acceptance",
      "description": "Contract mismatch",
      "contract_refs": ["Must reject; RiskState::Degraded on failure"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["baseline", "baseline 2", "baseline 3"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": true
    }
  ]
}
JSON

set +e
output=$("$lint_script" "plans/prd.json" 2>&1)
status=$?
set -e

if [[ $status -ne 2 ]]; then
  echo "Expected exit code 2, got $status"
  echo "$output"
  exit 1
fi

if ! echo "$output" | grep -q "SCHEMA_FAIL"; then
  echo "Expected output to contain SCHEMA_FAIL"
  echo "$output"
  exit 1
fi

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd.json" 2>&1)
status=$?
set -e

if [[ $status -ne 2 ]]; then
  echo "Expected exit code 2 with schema bypass, got $status"
  echo "$output"
  exit 1
fi

if ! echo "$output" | grep -q "MISSING_VERIFY_SH"; then
  echo "Expected output to contain MISSING_VERIFY_SH"
  echo "$output"
  exit 1
fi

if ! echo "$output" | grep -q "CONTRACT_ACCEPTANCE_MISMATCH"; then
  echo "Expected output to contain CONTRACT_ACCEPTANCE_MISMATCH"
  echo "$output"
  exit 1
fi

# Test 1b: allowlist is case-sensitive (lowercase entry must not suppress S1-001)
set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 PRD_LINT_VERIFY_ALLOWLIST=s1-001 "$lint_script" "plans/prd.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected exit code 2 with lowercase allowlist mismatch, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "MISSING_VERIFY_SH"; then
  echo "Expected output to contain MISSING_VERIFY_SH when allowlist case does not match"
  echo "$output"
  exit 1
fi

# Test 1c: exact-case allowlist suppresses verify gate for matching story id
set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 PRD_LINT_VERIFY_ALLOWLIST=S1-001 "$lint_script" "plans/prd.json" 2>&1)
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "Expected exit code 0 with exact-case allowlist, got $status"
  echo "$output"
  exit 1
fi
if echo "$output" | grep -q "MISSING_VERIFY_SH"; then
  echo "Did not expect MISSING_VERIFY_SH when exact-case allowlist includes S1-001"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "CONTRACT_ACCEPTANCE_MISMATCH"; then
  echo "Expected CONTRACT_ACCEPTANCE_MISMATCH to remain with allowlist"
  echo "$output"
  exit 1
fi

# Test 2: scope.create allows new files when scope.touch is empty
mkdir -p new_dir
cat <<'JSON' > plans/prd_create_ok.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-003",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Create a new file",
      "category": "acceptance",
      "description": "Create a new file",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": [], "avoid": [], "create": ["new_dir/new_file.txt"] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$("$lint_script" "plans/prd_create_ok.json" 2>&1)
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "Expected scope.create ok status 0, got $status"
  echo "$output"
  exit 1
fi

# Test 3: scope.create parent missing fails
cat <<'JSON' > plans/prd_create_missing_parent.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-004",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Missing parent",
      "category": "acceptance",
      "description": "Missing parent",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": [], "avoid": [], "create": ["missing_dir/new_file.txt"] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$("$lint_script" "plans/prd_create_missing_parent.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected CREATE_PARENT_MISSING exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "CREATE_PARENT_MISSING"; then
  echo "Expected output to contain CREATE_PARENT_MISSING"
  echo "$output"
  exit 1
fi

# Test 4: scope.create existing path fails
touch new_dir/existing.txt
cat <<'JSON' > plans/prd_create_exists.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-005",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Existing path",
      "category": "acceptance",
      "description": "Existing path",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": [], "avoid": [], "create": ["new_dir/existing.txt"] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$("$lint_script" "plans/prd_create_exists.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected CREATE_PATH_EXISTS exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "CREATE_PATH_EXISTS"; then
  echo "Expected output to contain CREATE_PATH_EXISTS"
  echo "$output"
  exit 1
fi

# Test 5: strict heuristics gate
cat <<'JSON' > plans/prd_strict_heuristics.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-006",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Strict heuristics",
      "category": "acceptance",
      "description": "Strict heuristics",
      "contract_refs": ["Must reject on failure"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["baseline", "baseline 2", "baseline 3"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$(PRD_LINT_STRICT_HEURISTICS=1 "$lint_script" "plans/prd_strict_heuristics.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected strict heuristics exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "CONTRACT_ACCEPTANCE_MISMATCH"; then
  echo "Expected strict heuristics to flag CONTRACT_ACCEPTANCE_MISMATCH"
  echo "$output"
  exit 1
fi

set +e
output=$(PRD_LINT_STRICT_HEURISTICS=0 "$lint_script" "plans/prd_strict_heuristics.json" 2>&1)
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "Expected non-strict heuristics exit code 0, got $status"
  echo "$output"
  exit 1
fi

# Test 6: fail-closed when bulk metadata extraction jq fails (schema bypass mode)
cat <<'JSON' > plans/prd_meta_extract_fail.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-007",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Metadata extract fail closed",
      "category": "acceptance",
      "description": "Malformed reason_codes type should fail closed in bulk jq extraction",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": 1,
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_meta_extract_fail.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected metadata extraction failure exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "ITEM_META_EXTRACTION_FAIL"; then
  echo "Expected output to contain ITEM_META_EXTRACTION_FAIL"
  echo "$output"
  exit 1
fi

# Test 7: stale premortem path tokens in machine-consumed path fields fail closed
cat <<'JSON' > plans/prd_stale_recon_paths.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-008",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Stale recon path guard",
      "category": "acceptance",
      "description": "Machine-consumed stale path must fail closed.",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["reviews/premortems/RUNBOOK_PREMORTEM_RECON.md"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON
mkdir -p reviews/premortems
touch reviews/premortems/RUNBOOK_PREMORTEM_RECON.md

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_stale_recon_paths.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected stale recon path lint failure exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "STALE_RECON_DOC_REF"; then
  echo "Expected output to contain STALE_RECON_DOC_REF"
  echo "$output"
  exit 1
fi

# Test 7b: PREMORTEM_RECONCILIATION_PROCESS token is also blocked in path fields.
cat <<'JSON' > plans/prd_stale_recon_paths_v2.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-010",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Stale recon path guard v2",
      "category": "acceptance",
      "description": "Additional stale premortem token must fail closed.",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON
touch reviews/premortems/PREMORTEM_RECONCILIATION_PROCESS.md

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_stale_recon_paths_v2.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected stale recon path v2 lint failure exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "STALE_RECON_DOC_REF"; then
  echo "Expected v2 output to contain STALE_RECON_DOC_REF"
  echo "$output"
  exit 1
fi

# Test 8: stale tokens in narrative fields remain allowed
cat <<'JSON' > plans/prd_stale_recon_narrative_ok.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-009",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Narrative token allowed",
      "category": "acceptance",
      "description": "Narrative text references legacy token but path fields are canonical.",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["Mention RUNBOOK_PREMORTEM_RECON in historical note only", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "bash -n plans/verify.sh"],
      "evidence": ["bash -n plans/verify.sh output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_stale_recon_narrative_ok.json" 2>&1)
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "Expected narrative stale token fixture to pass lint, got $status"
  echo "$output"
  exit 1
fi
if echo "$output" | grep -q "STALE_RECON_DOC_REF"; then
  echo "Did not expect STALE_RECON_DOC_REF for narrative-only token"
  echo "$output"
  exit 1
fi

# Test 9: stale verify/evidence file references fail closed.
cat <<'JSON' > plans/prd_stale_path_refs.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-011",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Stale path ref",
      "category": "acceptance",
      "description": "Stale verify/evidence path references should fail closed.",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": [
        "./plans/verify.sh",
        "crates/soldier_core/tests/test_dispatch_chokepoint.rs::test_dispatch_chokepoint_no_direct_exchange_client_usage"
      ],
      "evidence": [
        "crates/soldier_core/tests/test_reject_reason.rs::test_reject_reason_in_registry output"
      ],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_stale_path_refs.json" 2>&1)
status=$?
set -e
if [[ $status -ne 2 ]]; then
  echo "Expected stale path refs lint failure exit code 2, got $status"
  echo "$output"
  exit 1
fi
if ! echo "$output" | grep -q "STALE_PATH_REF"; then
  echo "Expected output to contain STALE_PATH_REF"
  echo "$output"
  exit 1
fi

# Test 9b: valid file references in verify/evidence pass.
mkdir -p crates/soldier_core/src
touch crates/soldier_core/src/lib.rs
cat <<'JSON' > plans/prd_valid_path_refs.json
{
  "project": "LintFixture",
  "source": {
    "implementation_plan_path": "IMPLEMENTATION_PLAN.md",
    "contract_path": "CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-012",
      "priority": 1,
      "phase": 1,
      "slice": 1,
      "slice_ref": "Slice 1",
      "story_ref": "Valid path ref",
      "category": "acceptance",
      "description": "Valid verify/evidence path references should pass.",
      "contract_refs": ["CONTRACT.md 0.Y Verification Harness (Non-Negotiable)"],
      "plan_refs": ["Test harness configured (cargo test --workspace)."],
      "scope": { "touch": ["touch.txt"], "avoid": [] },
      "acceptance": ["a", "b", "c"],
      "steps": ["1", "2", "3", "4", "5"],
      "verify": ["./plans/verify.sh", "crates/soldier_core/src/lib.rs::placeholder"],
      "evidence": ["crates/soldier_core/src/lib.rs output"],
      "contract_must_evidence": [],
      "enforcing_contract_ats": [],
      "reason_codes": { "type": "", "values": [] },
      "enforcement_point": "",
      "failure_mode": [],
      "loss_mode": { "worst_case": "test worst case", "fail_closed_cap": "test cap", "drift_metric": "test metric" },
      "observability": { "metrics": [], "status_fields": [], "status_contract_ats": [] },
      "implementation_tests": [],
      "dependencies": [],
      "est_size": "S",
      "risk": "low",
      "needs_human_decision": false,
      "passes": false
    }
  ]
}
JSON

set +e
output=$(PRD_LINT_ALLOW_SCHEMA_BYPASS=1 "$lint_script" "plans/prd_valid_path_refs.json" 2>&1)
status=$?
set -e
if [[ $status -ne 0 ]]; then
  echo "Expected valid path refs fixture to pass lint, got $status"
  echo "$output"
  exit 1
fi
if echo "$output" | grep -q "STALE_PATH_REF"; then
  echo "Did not expect STALE_PATH_REF for valid path references"
  echo "$output"
  exit 1
fi

echo "test_prd_lint.sh: ok"
