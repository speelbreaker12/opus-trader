#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/run_prd_auditor.sh"
check_script="$repo_root/plans/prd_audit_check.sh"
hash_utils="$repo_root/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$script" ]] || fail "run_prd_auditor.sh not found at $script"
[[ -f "$check_script" ]] || fail "prd_audit_check.sh not found at $check_script"
[[ -f "$hash_utils" ]] || fail "hash_utils.sh not found at $hash_utils"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup_fixture() {
  local fixture_root="$1"

  mkdir -p "$fixture_root"/plans "$fixture_root"/plans/lib "$fixture_root"/prompts "$fixture_root"/specs "$fixture_root"/docs "$fixture_root"/.context "$fixture_root"/bin
  cp "$script" "$fixture_root"/plans/run_prd_auditor.sh
  cp "$check_script" "$fixture_root"/plans/prd_audit_check.sh
  cp "$hash_utils" "$fixture_root"/plans/lib/hash_utils.sh
  chmod +x "$fixture_root"/plans/run_prd_auditor.sh "$fixture_root"/plans/prd_audit_check.sh

  cat > "$fixture_root"/plans/prd.json <<'JSON'
{
  "project": "DecisionFixture",
  "source": {
    "implementation_plan_path": "specs/IMPLEMENTATION_PLAN.md",
    "contract_path": "specs/CONTRACT.md"
  },
  "rules": {
    "one_story_per_iteration": true,
    "one_commit_per_story": true,
    "no_prd_rewrite": true,
    "passes_only_flips_after_verify_green": true
  },
  "items": [
    {
      "id": "S1-001"
    }
  ]
}
JSON

  echo "# contract" > "$fixture_root"/specs/CONTRACT.md
  echo "# plan" > "$fixture_root"/specs/IMPLEMENTATION_PLAN.md
  echo "# workflow" > "$fixture_root"/specs/WORKFLOW_CONTRACT.md
  echo "# roadmap" > "$fixture_root"/docs/ROADMAP.md

  cat > "$fixture_root"/prompts/auditor.md <<'EOF_PROMPT'
role: auditor
meta:
__AUDIT_META_PLACEHOLDER__
EOF_PROMPT

  cat > "$fixture_root"/plans/prd_preflight.sh <<'EOF_PRE'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_PRE
  chmod +x "$fixture_root"/plans/prd_preflight.sh

  cat > "$fixture_root"/plans/build_contract_digest.sh <<'EOF_CDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${CONTRACT_DIGEST_FILE:-.context/contract_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_CDIGEST
  chmod +x "$fixture_root"/plans/build_contract_digest.sh

  cat > "$fixture_root"/plans/build_plan_digest.sh <<'EOF_PDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${PLAN_DIGEST_FILE:-.context/plan_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_PDIGEST
  chmod +x "$fixture_root"/plans/build_plan_digest.sh

  cat > "$fixture_root"/plans/build_markdown_digest.sh <<'EOF_MDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${OUTPUT_FILE:-.context/roadmap_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_MDIGEST
  chmod +x "$fixture_root"/plans/build_markdown_digest.sh

  cat > "$fixture_root"/bin/fake_auditor.sh <<'EOF_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail

decision="${AUDIT_DECISION_FIXTURE:-PASS}"
if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum "plans/prd.json" | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 "plans/prd.json" | awk '{print $1}')"
fi

case "$decision" in
  PASS)
    status="PASS"
    items_pass=1
    items_fail=0
    items_blocked=0
    must_fix_count=0
    reasons_json='[]'
    patches_json='[]'
    ;;
  FAIL)
    status="FAIL"
    items_pass=0
    items_fail=1
    items_blocked=0
    must_fix_count=1
    reasons_json='["failed invariant"]'
    patches_json='["narrow the scope"]'
    ;;
  BLOCKED)
    status="BLOCKED"
    items_pass=0
    items_fail=0
    items_blocked=1
    must_fix_count=0
    reasons_json='["missing dependency"]'
    patches_json='["restore dependency contract"]'
    ;;
  *)
    echo "unknown decision fixture: $decision" >&2
    exit 2
    ;;
esac

cat > "plans/prd_audit.json" <<JSON
{
  "project": "DecisionFixture",
  "prd_sha256": "$prd_sha",
  "inputs": {
    "prd": "plans/prd.json",
    "contract": "specs/CONTRACT.md",
    "plan": "specs/IMPLEMENTATION_PLAN.md",
    "workflow_contract": "specs/WORKFLOW_CONTRACT.md",
    "roadmap": "docs/ROADMAP.md"
  },
  "summary": {
    "items_total": 1,
    "items_pass": $items_pass,
    "items_fail": $items_fail,
    "items_blocked": $items_blocked,
    "must_fix_count": $must_fix_count
  },
  "global_findings": {
    "must_fix": [],
    "risk": [],
    "improvements": []
  },
  "items": [
    {
      "id": "S1-001",
      "slice": 1,
      "status": "$status",
      "reasons": $reasons_json,
      "schema_check": { "missing_fields": [], "notes": ["checked schema"] },
      "contract_check": {
        "refs_present": true,
        "refs_specific": true,
        "contract_refs_resolved": true,
        "acceptance_enforces_invariant": true,
        "contradiction": false,
        "notes": []
      },
      "verify_check": {
        "has_verify_sh": true,
        "has_targeted_checks": true,
        "evidence_concrete": true,
        "notes": []
      },
      "scope_check": { "too_broad": false, "est_size_too_large": false, "notes": [] },
      "dependency_check": { "invalid": false, "forward_dep": false, "cycle": false, "notes": [] },
      "patch_suggestions": $patches_json
    }
  ]
}
JSON

printf '%s\n' "<promise>AUDIT_COMPLETE</promise>"
EOF_AUDITOR
  chmod +x "$fixture_root"/bin/fake_auditor.sh
}

run_case() {
  local case_name="$1"
  local expected_decision="$2"
  local case_dir="$tmp_dir/$case_name"
  local cache_decision
  local cost_decision

  setup_fixture "$case_dir"

  (
    cd "$case_dir"
    AUDITOR_AGENT_CMD="./bin/fake_auditor.sh" \
    AUDITOR_AGENT_ARGS="" \
    AUDIT_DECISION_FIXTURE="$expected_decision" \
    AUDIT_PROGRESS=0 \
    ./plans/run_prd_auditor.sh
  ) >/dev/null

  (
    cd "$case_dir"
    PRD_FILE="plans/prd.json" \
    AUDIT_FILE="plans/prd_audit.json" \
    AUDIT_STDOUT=".context/prd_auditor_stdout.log" \
    ./plans/prd_audit_check.sh
  ) >/dev/null

  cache_decision="$(jq -r '.decision // empty' "$case_dir/.context/prd_audit_cache.json")"
  [[ "$cache_decision" == "$expected_decision" ]] \
    || fail "$case_name: expected cache decision $expected_decision, got $cache_decision"

  cost_decision="$(jq -r 'select(.stage == "complete") | .decision' "$case_dir/.context/audit_costs.jsonl" | tail -n 1)"
  [[ "$cost_decision" == "$expected_decision" ]] \
    || fail "$case_name: expected final cost decision $expected_decision, got $cost_decision"
}

run_case "pass" "PASS"
run_case "fail" "FAIL"
run_case "blocked" "BLOCKED"

echo "test_run_prd_auditor_decision_outputs.sh: ok"
