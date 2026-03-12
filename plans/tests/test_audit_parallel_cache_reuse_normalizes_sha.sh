#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/audit_parallel.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

[[ -f "$script" ]] || fail "audit_parallel.sh not found at $script"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir"/plans "$tmp_dir"/docs "$tmp_dir"/.context/parallel_audits
cp "$script" "$tmp_dir"/plans/audit_parallel.sh
chmod +x "$tmp_dir"/plans/audit_parallel.sh

cat > "$tmp_dir"/plans/prd.json <<'JSON'
{
  "items": [
    {
      "id": "S0-000",
      "slice": 0,
      "passes": false
    }
  ]
}
JSON

current_full_sha="$(hash_file "$tmp_dir/plans/prd.json")"
stale_full_sha="3927acfa636ab75679c0d0e5ab64406326b56bf88307b8892836182a89122e08"
canonical_inputs='{"prd":"plans/prd.json","contract":"CONTRACT.md","plan":"IMPLEMENTATION_PLAN.md","workflow_contract":"WORKFLOW_CONTRACT.md","roadmap":"docs/ROADMAP.md"}'

cat > "$tmp_dir"/plans/build_contract_digest.sh <<'EOF_CONTRACT'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .context
echo '{"sections":[]}' > .context/contract_digest.json
EOF_CONTRACT
chmod +x "$tmp_dir"/plans/build_contract_digest.sh

cat > "$tmp_dir"/plans/build_plan_digest.sh <<'EOF_PLAN'
#!/usr/bin/env bash
set -euo pipefail
mkdir -p .context
echo '{"sections":[]}' > .context/plan_digest.json
EOF_PLAN
chmod +x "$tmp_dir"/plans/build_plan_digest.sh

cat > "$tmp_dir"/plans/build_markdown_digest.sh <<'EOF_ROADMAP'
#!/usr/bin/env bash
set -euo pipefail
out="${OUTPUT_FILE:-.context/roadmap_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_ROADMAP
chmod +x "$tmp_dir"/plans/build_markdown_digest.sh

cat > "$tmp_dir"/plans/prd_cache_check.py <<'EOF_CACHE_CHECK'
#!/usr/bin/env python3
import json
print(json.dumps({"valid_slices": [0], "invalid_slices": []}))
EOF_CACHE_CHECK
chmod +x "$tmp_dir"/plans/prd_cache_check.py

cat > "$tmp_dir"/plans/prd_slice_prepare.sh <<'EOF_SLICE_PREP'
#!/usr/bin/env bash
set -euo pipefail

out_prd_slice="${OUT_PRD_SLICE:?missing OUT_PRD_SLICE}"
out_meta="${OUT_META:?missing OUT_META}"

mkdir -p "$(dirname "$out_prd_slice")"
cat > "$out_prd_slice" <<'JSON'
{
  "items": [
    {
      "id": "S0-000",
      "slice": 0
    }
  ]
}
JSON

cat > "$out_meta" <<JSON
{
  "audit_scope": "slice",
  "prd_slice_file": "$out_prd_slice"
}
JSON
EOF_SLICE_PREP
chmod +x "$tmp_dir"/plans/prd_slice_prepare.sh

cat > "$tmp_dir"/plans/prd_audit_check.sh <<'EOF_AUDIT_CHECK'
#!/usr/bin/env bash
set -euo pipefail

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

audit_file="${AUDIT_FILE:?missing AUDIT_FILE}"
prd_file="${PRD_FILE:?missing PRD_FILE}"
audit_sha="$(jq -r '.prd_sha256 // empty' "$audit_file")"
slice_sha="$(hash_file "$prd_file")"
full_sha="$(hash_file plans/prd.json)"

[[ "$audit_sha" == "$slice_sha" || "$audit_sha" == "$full_sha" ]]
EOF_AUDIT_CHECK
chmod +x "$tmp_dir"/plans/prd_audit_check.sh

cat > "$tmp_dir"/plans/prd_audit_merge.sh <<'EOF_MERGE'
#!/usr/bin/env bash
set -euo pipefail

hash_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

slice_dir="${1:?missing slice dir}"
slice_file="$slice_dir/audit_slice_0.json"
slice_prd="$slice_dir/prd_slice_0.json"
expected_slice_sha="$(hash_file "$slice_prd")"
actual_sha="$(jq -r '.prd_sha256 // empty' "$slice_file")"
[[ "$actual_sha" == "$expected_slice_sha" ]] || {
  echo "slice audit hash not normalized to current slice sha" >&2
  exit 1
}
actual_inputs="$(jq -c '.inputs' "$slice_file")"
expected_inputs='{"prd":"plans/prd.json","contract":"CONTRACT.md","plan":"IMPLEMENTATION_PLAN.md","workflow_contract":"WORKFLOW_CONTRACT.md","roadmap":"docs/ROADMAP.md"}'
[[ "$actual_inputs" == "$expected_inputs" ]] || {
  echo "slice audit inputs not normalized to canonical paths" >&2
  exit 1
}

full_sha="$(hash_file plans/prd.json)"
cat > plans/prd_audit.json <<JSON
{
  "project": "parallel-fixture",
  "prd_sha256": "$full_sha",
  "inputs": $expected_inputs,
  "summary": {
    "items_total": 1,
    "items_pass": 1,
    "items_fail": 0,
    "items_blocked": 0,
    "must_fix_count": 0
  },
  "global_findings": {
    "must_fix": [],
    "risk": [],
    "improvements": []
  },
  "items": [
    {
      "id": "S0-000",
      "slice": 0,
      "status": "PASS",
      "reasons": [],
      "schema_check": { "missing_fields": [], "notes": ["fixture"] },
      "contract_check": {
        "refs_present": true,
        "refs_specific": true,
        "contract_refs_resolved": true,
        "roadmap_refs_resolved": true,
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
      "scope_check": {
        "too_broad": false,
        "est_size_too_large": false,
        "notes": []
      },
      "dependency_check": {
        "invalid": false,
        "forward_dep": false,
        "cycle": false,
        "notes": []
      },
      "patch_suggestions": []
    }
  ]
}
JSON
EOF_MERGE
chmod +x "$tmp_dir"/plans/prd_audit_merge.sh

cat > "$tmp_dir"/plans/prd_cache_update.py <<'EOF_CACHE_UPDATE'
#!/usr/bin/env python3
import sys
sys.exit(0)
EOF_CACHE_UPDATE
chmod +x "$tmp_dir"/plans/prd_cache_update.py

cat > "$tmp_dir"/plans/run_prd_auditor.sh <<'EOF_RUN_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail
echo "unexpected re-audit" >&2
exit 99
EOF_RUN_AUDITOR
chmod +x "$tmp_dir"/plans/run_prd_auditor.sh

echo "# roadmap" > "$tmp_dir"/docs/ROADMAP.md

cat > "$tmp_dir"/.context/prd_audit_slice_cache.json <<JSON
{
  "slices": {
    "0": {
      "audit_json": "$tmp_dir/.context/parallel_audits/audit_slice_0.json",
      "decision": "PASS"
    }
  }
}
JSON

cat > "$tmp_dir"/.context/parallel_audits/audit_slice_0.json <<JSON
{
  "project": "parallel-fixture",
  "prd_sha256": "$stale_full_sha",
  "inputs": {
    "prd": "plans/prd.json",
    "contract": "specs/CONTRACT.md",
    "plan": "specs/IMPLEMENTATION_PLAN.md",
    "workflow_contract": "specs/WORKFLOW_CONTRACT.md",
    "roadmap": "docs/ROADMAP.md"
  },
  "summary": {
    "items_total": 1,
    "items_pass": 1,
    "items_fail": 0,
    "items_blocked": 0,
    "must_fix_count": 0
  },
  "global_findings": {
    "must_fix": [],
    "risk": [],
    "improvements": []
  },
  "items": [
    {
      "id": "S0-000",
      "slice": 0,
      "status": "PASS",
      "reasons": [],
      "schema_check": { "missing_fields": [], "notes": ["fixture"] },
      "contract_check": {
        "refs_present": true,
        "refs_specific": true,
        "contract_refs_resolved": true,
        "roadmap_refs_resolved": true,
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
      "scope_check": {
        "too_broad": false,
        "est_size_too_large": false,
        "notes": []
      },
      "dependency_check": {
        "invalid": false,
        "forward_dep": false,
        "cycle": false,
        "notes": []
      },
      "patch_suggestions": []
    }
  ]
}
JSON

rc=0
output="$(
  cd "$tmp_dir"
  AUDIT_OUTPUT_DIR=".context/parallel_audits" MAX_PARALLEL=1 ./plans/audit_parallel.sh 2>&1
)" || rc=$?

[[ "$rc" -eq 0 ]] || fail "audit_parallel.sh failed (rc=$rc): $output"
if echo "$output" | grep -Fq "are identical"; then
  fail "unexpected identical-copy failure: $output"
fi
if echo "$output" | grep -Fq "unexpected re-audit"; then
  fail "cache hit should not trigger re-audit: $output"
fi
echo "$output" | grep -Fq "[audit_parallel] Slice 0: CACHE HIT (reused)" \
  || fail "missing cache reuse marker: $output"
echo "$output" | grep -Fq "[audit_parallel] PASS: Merged audit written to plans/prd_audit.json" \
  || fail "missing merge pass marker: $output"

actual_sha="$(jq -r '.prd_sha256 // empty' "$tmp_dir/.context/parallel_audits/audit_slice_0.json")"
current_slice_sha="$(hash_file "$tmp_dir/.context/parallel_audits/prd_slice_0.json")"
[[ "$actual_sha" == "$current_slice_sha" ]] \
  || fail "expected normalized slice sha $current_slice_sha, got $actual_sha"
[[ "$actual_sha" != "$stale_full_sha" ]] \
  || fail "stale full PRD sha was not replaced"
actual_inputs="$(jq -c '.inputs' "$tmp_dir/.context/parallel_audits/audit_slice_0.json")"
[[ "$actual_inputs" == "$canonical_inputs" ]] \
  || fail "expected canonical inputs $canonical_inputs, got $actual_inputs"
[[ -f "$tmp_dir/plans/prd_audit.json" ]] || fail "merged audit file missing"

echo "test_audit_parallel_cache_reuse_normalizes_sha.sh: ok"
