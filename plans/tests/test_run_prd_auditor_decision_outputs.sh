#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
auditor_script="$repo_root/plans/run_prd_auditor.sh"
check_script="$repo_root/plans/prd_audit_check.sh"
hash_utils_script="$repo_root/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$auditor_script" ]] || fail "run_prd_auditor.sh not found at $auditor_script"
[[ -x "$check_script" ]] || fail "prd_audit_check.sh not executable at $check_script"
[[ -f "$hash_utils_script" ]] || fail "hash_utils.sh not found at $hash_utils_script"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup_repo() {
  local repo="$1"

  mkdir -p "$repo"/plans "$repo"/plans/lib "$repo"/prompts "$repo"/specs "$repo"/docs "$repo"/.context "$repo"/bin
  cp "$auditor_script" "$repo"/plans/run_prd_auditor.sh
  chmod +x "$repo"/plans/run_prd_auditor.sh
  cp "$check_script" "$repo"/plans/prd_audit_check.sh
  chmod +x "$repo"/plans/prd_audit_check.sh
  cp "$hash_utils_script" "$repo"/plans/lib/hash_utils.sh

  cat > "$repo"/plans/prd.json <<'JSON'
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

  echo "# contract" > "$repo"/specs/CONTRACT.md
  echo "# plan" > "$repo"/specs/IMPLEMENTATION_PLAN.md
  echo "# workflow" > "$repo"/specs/WORKFLOW_CONTRACT.md
  echo "# roadmap" > "$repo"/docs/ROADMAP.md

  cat > "$repo"/prompts/auditor.md <<'EOF_PROMPT'
role: auditor
meta:
__AUDIT_META_PLACEHOLDER__
EOF_PROMPT

  cat > "$repo"/plans/prd_preflight.sh <<'EOF_PRE'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_PRE
  chmod +x "$repo"/plans/prd_preflight.sh

  cat > "$repo"/plans/build_contract_digest.sh <<'EOF_CDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${CONTRACT_DIGEST_FILE:-.context/contract_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_CDIGEST
  chmod +x "$repo"/plans/build_contract_digest.sh

  cat > "$repo"/plans/build_plan_digest.sh <<'EOF_PDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${PLAN_DIGEST_FILE:-.context/plan_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_PDIGEST
  chmod +x "$repo"/plans/build_plan_digest.sh

  cat > "$repo"/plans/build_markdown_digest.sh <<'EOF_MDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${OUTPUT_FILE:-.context/roadmap_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_MDIGEST
  chmod +x "$repo"/plans/build_markdown_digest.sh

  cat > "$repo"/bin/fake_auditor.sh <<'EOF_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail
scenario="${AUDIT_SCENARIO:-PASS}"
prd_file="plans/prd.json"
out_file="plans/prd_audit.json"
if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum "$prd_file" | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 "$prd_file" | awk '{print $1}')"
fi

status="PASS"
items_pass=1
items_fail=0
items_blocked=0
must_fix_count=0
reasons='[]'
patch_suggestions='[]'
contract_notes='[]'

case "$scenario" in
  PASS)
    ;;
  FAIL)
    status="FAIL"
    items_pass=0
    items_fail=1
    must_fix_count=1
    reasons='["needs remediation"]'
    patch_suggestions='["tighten acceptance coverage"]'
    contract_notes='["failure confirmed"]'
    ;;
  BLOCKED)
    status="BLOCKED"
    items_pass=0
    items_blocked=1
    reasons='["missing prerequisite evidence"]'
    patch_suggestions='["add missing prerequisite artifact"]'
    contract_notes='["blocked by missing evidence"]'
    ;;
  *)
    echo "unknown AUDIT_SCENARIO: $scenario" >&2
    exit 9
    ;;
esac

cat > "$out_file" <<JSON
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
      "reasons": $reasons,
      "schema_check": { "missing_fields": [], "notes": ["checked schema"] },
      "contract_check": {
        "refs_present": true,
        "refs_specific": true,
        "contract_refs_resolved": true,
        "acceptance_enforces_invariant": true,
        "contradiction": false,
        "notes": $contract_notes
      },
      "verify_check": {
        "has_verify_sh": true,
        "has_targeted_checks": true,
        "evidence_concrete": true,
        "notes": []
      },
      "scope_check": { "too_broad": false, "est_size_too_large": false, "notes": [] },
      "dependency_check": { "invalid": false, "forward_dep": false, "cycle": false, "notes": [] },
      "patch_suggestions": $patch_suggestions
    }
  ]
}
JSON

echo "<promise>AUDIT_COMPLETE</promise>"
EOF_AUDITOR
  chmod +x "$repo"/bin/fake_auditor.sh
}

run_scenario() {
  local expected_decision="$1"
  local scenario_dir
  scenario_dir="$(printf '%s' "$expected_decision" | tr '[:upper:]' '[:lower:]')"
  local repo="$tmp_dir/$scenario_dir"

  setup_repo "$repo"

  (
    cd "$repo"
    AUDITOR_AGENT_CMD="./bin/fake_auditor.sh" \
    AUDITOR_AGENT_ARGS="" \
    AUDIT_SCENARIO="$expected_decision" \
    AUDIT_PROGRESS=0 \
    ./plans/run_prd_auditor.sh
  )

  (
    cd "$repo"
    PRD_FILE="plans/prd.json" \
    AUDIT_FILE="plans/prd_audit.json" \
    AUDIT_STDOUT=".context/prd_auditor_stdout.log" \
    ./plans/prd_audit_check.sh >/dev/null 2>&1
  )

  cache_decision="$(jq -r '.decision // empty' "$repo/.context/prd_audit_cache.json")"
  [[ "$cache_decision" == "$expected_decision" ]] \
    || fail "cache decision mismatch for $expected_decision: got '$cache_decision'"

  cost_decision="$(tail -n 1 "$repo/.context/audit_costs.jsonl" | jq -r '.decision // empty')"
  [[ "$cost_decision" == "$expected_decision" ]] \
    || fail "cost decision mismatch for $expected_decision: got '$cost_decision'"

  auditor_rc="$(jq -r 'select(.stage == "auditor") | .rc // empty' "$repo/.context/audit_costs.jsonl" | tail -n 1)"
  [[ "$auditor_rc" == "0" ]] \
    || fail "auditor stage rc mismatch for $expected_decision: got '$auditor_rc'"
}

run_scenario PASS
run_scenario FAIL
run_scenario BLOCKED

echo "test_run_prd_auditor_decision_outputs.sh: ok"
