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

cat > "$tmp_dir"/AGENTS.md <<'EOF_AGENTS'
This fixture simulates repo-level instructions that must not leak into the auditor workspace.
EOF_AGENTS

cat > "$tmp_dir"/plans/prd.json <<'JSON'
{
  "project": "IsolatedAuditorFixture",
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
echo '{"sections":[],"anchors":{},"key_map":{}}' > "$out"
EOF_CDIGEST
chmod +x "$tmp_dir"/plans/build_contract_digest.sh

cat > "$tmp_dir"/plans/build_plan_digest.sh <<'EOF_PDIGEST'
#!/usr/bin/env bash
set -euo pipefail
out="${PLAN_DIGEST_FILE:-.context/plan_digest.json}"
mkdir -p "$(dirname "$out")"
echo '{"sections":[],"anchors":{},"key_map":{}}' > "$out"
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
[[ -f "${AUDIT_STDOUT:-.context/prd_auditor_stdout.log}" ]]
grep -Fq '<promise>AUDIT_COMPLETE</promise>' "${AUDIT_STDOUT:-.context/prd_auditor_stdout.log}"
echo "PRD audit check OK"
EOF_CHECK
chmod +x "$tmp_dir"/plans/prd_audit_check.sh

cat > "$tmp_dir"/bin/codex <<'EOF_FAKE'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "exec" ]]; then
  shift
fi

audit_cwd=""
disable_multi_agent=0
disable_js_repl=0
disable_apps=0
sandbox_mode=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --disable)
      case "${2:-}" in
        multi_agent) disable_multi_agent=1 ;;
        js_repl) disable_js_repl=1 ;;
        apps) disable_apps=1 ;;
      esac
      shift 2
      ;;
    -C|--cd)
      audit_cwd="$2"
      shift 2
      ;;
    --sandbox)
      sandbox_mode="${2:-}"
      shift 2
      ;;
    --skip-git-repo-check)
      shift
      ;;
    --*)
      shift
      ;;
    *)
      break
      ;;
  esac
done

if [[ -n "$audit_cwd" ]]; then
  cd "$audit_cwd"
fi

[[ "$disable_multi_agent" == "1" ]] || { echo "missing --disable multi_agent" >&2; exit 25; }
[[ "$disable_js_repl" == "1" ]] || { echo "missing --disable js_repl" >&2; exit 26; }
[[ "$disable_apps" == "1" ]] || { echo "missing --disable apps" >&2; exit 27; }
[[ "$sandbox_mode" == "workspace-write" ]] || { echo "missing --sandbox workspace-write" >&2; exit 28; }

if [[ -f AGENTS.md ]]; then
  echo "unexpected AGENTS.md in auditor cwd: $PWD" >&2
  exit 19
fi

[[ -f plans/prd.json ]] || { echo "missing isolated plans/prd.json" >&2; exit 20; }
[[ -f .context/contract_digest.json ]] || { echo "missing isolated contract digest" >&2; exit 21; }
[[ -f .context/plan_digest.json ]] || { echo "missing isolated plan digest" >&2; exit 22; }
[[ -f specs/WORKFLOW_CONTRACT.md ]] || { echo "missing isolated workflow contract" >&2; exit 23; }
[[ -f docs/ROADMAP.md ]] || { echo "missing isolated roadmap" >&2; exit 24; }

if command -v sha256sum >/dev/null 2>&1; then
  prd_sha="$(sha256sum plans/prd.json | awk '{print $1}')"
else
  prd_sha="$(shasum -a 256 plans/prd.json | awk '{print $1}')"
fi

mkdir -p plans
cat > plans/prd_audit.json <<JSON
{
  "project": "IsolatedAuditorFixture",
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

printf '%s\n' '<promise>AUDIT_COMPLETE</promise>'
EOF_FAKE
chmod +x "$tmp_dir"/bin/codex

(
  cd "$tmp_dir"
  AUDITOR_AGENT_CMD="./bin/codex" \
  AUDITOR_AGENT_ARGS="exec" \
  AUDIT_PROGRESS=0 \
  ./plans/run_prd_auditor.sh
)

if command -v sha256sum >/dev/null 2>&1; then
  expected_sha="$(sha256sum "$tmp_dir/plans/prd.json" | awk '{print $1}')"
else
  expected_sha="$(shasum -a 256 "$tmp_dir/plans/prd.json" | awk '{print $1}')"
fi

audit_sha="$(jq -r '.prd_sha256 // empty' "$tmp_dir/plans/prd_audit.json")"
[[ "$audit_sha" == "$expected_sha" ]] || fail "isolated audit sha mismatch"
grep -Fq '<promise>AUDIT_COMPLETE</promise>' "$tmp_dir/.context/prd_auditor_stdout.log" \
  || fail "missing promise marker in stdout log"
if grep -Fq 'unexpected AGENTS.md in auditor cwd' "$tmp_dir/.context/prd_auditor_stdout.log"; then
  fail "auditor inherited repo AGENTS.md"
fi

echo "test_run_prd_auditor_isolated_workspace.sh: ok"
