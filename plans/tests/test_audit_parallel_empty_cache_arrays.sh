#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/audit_parallel.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$script" ]] || fail "audit_parallel.sh not found at $script"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir"/plans "$tmp_dir"/docs "$tmp_dir"/.context
cp "$script" "$tmp_dir"/plans/audit_parallel.sh
chmod +x "$tmp_dir"/plans/audit_parallel.sh

cat > "$tmp_dir"/plans/prd.json <<'JSON'
{
  "items": [
    { "slice": 0 },
    { "slice": 1 }
  ]
}
JSON

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
print(json.dumps({"valid_slices": [], "invalid_slices": [0, 1]}))
EOF_CACHE_CHECK
chmod +x "$tmp_dir"/plans/prd_cache_check.py

cat > "$tmp_dir"/plans/run_prd_auditor.sh <<'EOF_RUN_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail
slice="${AUDIT_SLICE:?missing AUDIT_SLICE}"
audit_file="${AUDIT_OUTPUT_JSON:?missing AUDIT_OUTPUT_JSON}"
mkdir -p "$(dirname "$audit_file")"
cat > "$audit_file" <<JSON
{
  "project": "parallel-fixture",
  "prd_sha256": "fixture",
  "inputs": {},
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
      "id": "S${slice}-000",
      "slice": $slice,
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
EOF_RUN_AUDITOR
chmod +x "$tmp_dir"/plans/run_prd_auditor.sh

cat > "$tmp_dir"/plans/prd_cache_update.py <<'EOF_CACHE_UPDATE'
#!/usr/bin/env python3
import sys
sys.exit(0)
EOF_CACHE_UPDATE
chmod +x "$tmp_dir"/plans/prd_cache_update.py

cat > "$tmp_dir"/plans/prd_audit_merge.sh <<'EOF_MERGE'
#!/usr/bin/env bash
set -euo pipefail
slice_dir="${1:?missing slice dir}"
[[ -f "$slice_dir/audit_slice_0.json" ]]
[[ -f "$slice_dir/audit_slice_1.json" ]]
cat > plans/prd_audit.json <<'JSON'
{
  "project": "parallel-fixture",
  "prd_sha256": "fixture",
  "inputs": {},
  "summary": {
    "items_total": 2,
    "items_pass": 2,
    "items_fail": 0,
    "items_blocked": 0,
    "must_fix_count": 0
  },
  "global_findings": {
    "must_fix": [],
    "risk": [],
    "improvements": []
  },
  "items": []
}
JSON
EOF_MERGE
chmod +x "$tmp_dir"/plans/prd_audit_merge.sh

echo "# roadmap" > "$tmp_dir"/docs/ROADMAP.md

rc=0
output="$(
  cd "$tmp_dir"
  AUDIT_OUTPUT_DIR=".context/parallel_audits" MAX_PARALLEL=2 ./plans/audit_parallel.sh 2>&1
)" || rc=$?

[[ "$rc" -eq 0 ]] || fail "audit_parallel.sh failed (rc=$rc): $output"
if echo "$output" | grep -Fq "unbound variable"; then
  fail "unexpected unbound variable error: $output"
fi
echo "$output" | grep -Fq "[audit_parallel] PASS: Merged audit written to plans/prd_audit.json" \
  || fail "missing merge pass marker in output"
[[ -f "$tmp_dir/plans/prd_audit.json" ]] || fail "merged audit file missing"

echo "test_audit_parallel_empty_cache_arrays.sh: ok"
