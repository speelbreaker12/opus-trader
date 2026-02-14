#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/run_prd_auditor.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

[[ -f "$script" ]] || fail "run_prd_auditor.sh not found at $script"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

mkdir -p "$tmp_dir"/plans "$tmp_dir"/prompts "$tmp_dir"/specs "$tmp_dir"/docs "$tmp_dir"/.context "$tmp_dir"/bin
cp "$script" "$tmp_dir"/plans/run_prd_auditor.sh
chmod +x "$tmp_dir"/plans/run_prd_auditor.sh

cat > "$tmp_dir"/plans/prd.json <<'JSON'
{
  "project": "SliceCacheDriftFixture",
  "source": {
    "implementation_plan_path": "specs/IMPLEMENTATION_PLAN.md",
    "contract_path": "specs/CONTRACT.md"
  },
  "items": [
    {"slice": 1, "id": "S1-001", "title": "first"},
    {"slice": 2, "id": "S2-001", "title": "second"}
  ]
}
JSON

echo "# contract" > "$tmp_dir"/specs/CONTRACT.md
echo "# plan" > "$tmp_dir"/specs/IMPLEMENTATION_PLAN.md
echo "# workflow" > "$tmp_dir"/specs/WORKFLOW_CONTRACT.md
echo "# roadmap" > "$tmp_dir"/docs/ROADMAP.md

cat > "$tmp_dir"/prompts/auditor.md <<'EOF_PROMPT'
role: auditor
meta:
__AUDIT_META_PLACEHOLDER__
EOF_PROMPT

cat > "$tmp_dir"/plans/prd_preflight.sh <<'EOF_PRE'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_PRE
chmod +x "$tmp_dir"/plans/prd_preflight.sh

cat > "$tmp_dir"/plans/build_contract_digest.sh <<'EOF_CDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${CONTRACT_DIGEST_FILE:-.context/contract_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_CDIGEST
chmod +x "$tmp_dir"/plans/build_contract_digest.sh

cat > "$tmp_dir"/plans/build_plan_digest.sh <<'EOF_PDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${PLAN_DIGEST_FILE:-.context/plan_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_PDIGEST
chmod +x "$tmp_dir"/plans/build_plan_digest.sh

cat > "$tmp_dir"/plans/build_markdown_digest.sh <<'EOF_MDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${OUTPUT_FILE:-.context/roadmap_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[]}' > "$out"
EOF_MDIGEST
chmod +x "$tmp_dir"/plans/build_markdown_digest.sh

cat > "$tmp_dir"/plans/prd_slice_prepare.sh <<'EOF_PREP'
#!/usr/bin/env bash
set -euo pipefail

mkdir -p "$(dirname "$OUT_PRD_SLICE")"
cp "$PRD_FILE" "$OUT_PRD_SLICE"

echo '{"sections":[]}' > "$OUT_CONTRACT_DIGEST"
echo '{"sections":[]}' > "$OUT_PLAN_DIGEST"
echo '{"sections":[]}' > "$OUT_ROADMAP_DIGEST"

if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum "$OUT_PRD_SLICE" | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 "$OUT_PRD_SLICE" | awk '{print $1}')"
fi

cat > "$OUT_META" <<JSON
{
  "audit_scope": "slice",
  "slice": "$PRD_SLICE",
  "prd_sha256": "$prd_sha",
  "prd_file": "$OUT_PRD_SLICE",
  "output_file": "$OUT_AUDIT_FILE"
}
JSON
EOF_PREP
chmod +x "$tmp_dir"/plans/prd_slice_prepare.sh

cat > "$tmp_dir"/plans/prd_audit_check.sh <<'EOF_CHECK'
#!/usr/bin/env bash
set -euo pipefail

audit_file="${AUDIT_FILE:-plans/prd_audit.json}"
[[ -f "$audit_file" ]]

if [[ "${AUDIT_PROMISE_REQUIRED:-1}" == "1" ]]; then
  log_file="${AUDIT_STDOUT:-.context/prd_auditor_stdout.log}"
  [[ -f "$log_file" ]]
  grep -Fq '<promise>AUDIT_COMPLETE</promise>' "$log_file"
fi

echo "PRD audit check OK"
EOF_CHECK
chmod +x "$tmp_dir"/plans/prd_audit_check.sh

cat > "$tmp_dir"/bin/fake_auditor.sh <<'EOF_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail

calls_file=".context/fake_auditor_calls"
calls=0
if [[ -f "$calls_file" ]]; then
  calls="$(cat "$calls_file")"
fi
echo $((calls + 1)) > "$calls_file"

prd_file=".context/prd_slice.json"
if [[ ! -f "$prd_file" ]]; then
  prd_file="plans/prd.json"
fi

if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum "$prd_file" | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 "$prd_file" | awk '{print $1}')"
fi

mkdir -p plans
cat > plans/prd_audit.json <<JSON
{
  "project": "SliceCacheDriftFixture",
  "prd_sha256": "$prd_sha",
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
  "items": []
}
JSON

echo "<promise>AUDIT_COMPLETE</promise>"
EOF_AUDITOR
chmod +x "$tmp_dir"/bin/fake_auditor.sh

run_slice_audit() {
  (
    cd "$tmp_dir"
    AUDITOR_AGENT_CMD="./bin/fake_auditor.sh" \
    AUDITOR_AGENT_ARGS="" \
    AUDITOR_TIMEOUT=30 \
    AUDIT_PROGRESS=0 \
    AUDIT_SCOPE=slice \
    AUDIT_SLICE=1 \
    ./plans/run_prd_auditor.sh
  )
}

# First run should execute auditor and populate cache.
run_slice_audit

calls_after_first="$(cat "$tmp_dir/.context/fake_auditor_calls")"
[[ "$calls_after_first" == "1" ]] || fail "expected first run to invoke auditor once, got $calls_after_first"

# Second run should hit cache and skip auditor execution.
run_slice_audit

calls_after_second="$(cat "$tmp_dir/.context/fake_auditor_calls")"
[[ "$calls_after_second" == "1" ]] || fail "expected cache hit to avoid auditor call, got $calls_after_second"

# Simulate stale prepared slice drift and confirm cache invalidation re-runs auditor.
cat > "$tmp_dir/.context/prd_slice.json" <<'JSON'
{"slice":1,"mutated":true}
JSON

run_slice_audit

calls_after_third="$(cat "$tmp_dir/.context/fake_auditor_calls")"
[[ "$calls_after_third" == "2" ]] || fail "expected drift to force re-audit, got $calls_after_third"

# Cache metadata should be refreshed to current prepared slice hash.
expected_slice_sha="$(sha256_file "$tmp_dir/.context/prd_slice.json")"
cached_slice_sha="$(jq -r '.slice_prd_sha256 // empty' "$tmp_dir/.context/prd_audit_cache.json")"
[[ "$cached_slice_sha" == "$expected_slice_sha" ]] || fail "slice cache sha mismatch after drift refresh"

echo "test_run_prd_auditor_slice_cache_drift.sh: ok"
