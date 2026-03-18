#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
script="$repo_root/plans/run_prd_auditor.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
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
  "project": "TimeoutFallbackFixture",
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
  "items": []
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

cat > "$tmp_dir"/plans/audit_parallel.sh <<'EOF_FALLBACK'
#!/usr/bin/env bash
set -euo pipefail
prd_file="${PRD_FILE:-plans/prd.json}"
out_file="${MERGED_AUDIT_FILE:-plans/prd_audit.json}"
if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum "$prd_file" | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 "$prd_file" | awk '{print $1}')"
fi
mkdir -p "$(dirname "$out_file")"
cat > "$out_file" <<JSON
{
  "project": "TimeoutFallbackFixture",
  "prd_sha256": "$prd_sha",
  "inputs": {
    "prd": "plans/prd.json",
    "contract": "specs/CONTRACT.md",
    "plan": "specs/IMPLEMENTATION_PLAN.md",
    "workflow_contract": "specs/WORKFLOW_CONTRACT.md",
    "roadmap": "docs/ROADMAP.md"
  },
  "summary": {
    "items_total": 0,
    "items_pass": 0,
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
EOF_FALLBACK
chmod +x "$tmp_dir"/plans/audit_parallel.sh

cat > "$tmp_dir"/bin/hang_auditor.sh <<'EOF_HANG'
#!/usr/bin/env bash
set -euo pipefail
sleep 2
EOF_HANG
chmod +x "$tmp_dir"/bin/hang_auditor.sh

(
  cd "$tmp_dir"
  AUDITOR_AGENT_CMD="./bin/hang_auditor.sh" \
  AUDITOR_AGENT_ARGS="" \
  AUDITOR_TIMEOUT=1 \
  AUDITOR_TIMEOUT_FALLBACK_PARALLEL=1 \
  AUDIT_PROGRESS=0 \
  ./plans/run_prd_auditor.sh
)

log_file="$tmp_dir/.context/prd_auditor_stdout.log"
[[ -f "$log_file" ]] || fail "missing auditor stdout log"
grep -Fq "invoking parallel slice fallback" "$log_file" || fail "missing fallback marker in stdout log"
grep -Fq "<promise>AUDIT_COMPLETE</promise>" "$log_file" || fail "missing promise marker after fallback"

if command -v sha256sum >/dev/null 2>&1; then
  expected_sha="$(sha256sum "$tmp_dir/plans/prd.json" | awk '{print $1}')"
else
  expected_sha="$(shasum -a 256 "$tmp_dir/plans/prd.json" | awk '{print $1}')"
fi
audit_sha="$(jq -r '.prd_sha256 // empty' "$tmp_dir/plans/prd_audit.json")"
[[ "$audit_sha" == "$expected_sha" ]] || fail "fallback audit sha mismatch"

echo "test_run_prd_auditor_timeout_fallback.sh: ok"
