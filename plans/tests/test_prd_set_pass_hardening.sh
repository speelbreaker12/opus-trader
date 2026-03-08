#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/prd_set_pass.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
command -v jq >/dev/null 2>&1 || fail "jq is required for this test"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

head_sha="$(git -C "$ROOT" rev-parse HEAD)"
real_git="$(command -v git)"
real_jq="$(command -v jq)"
story_id="S99-001"

setup_story_review_artifacts() {
  local case_dir="$1"
  local review_head="$2"
  local story_root="$case_dir/story_artifacts/$story_id"

  mkdir -p \
    "$story_root/self_review" \
    "$story_root/codex" \
    "$story_root/opus"

  cat > "$story_root/self_review/20260214T000000Z_self_review.md" <<EOF
Story: $story_id
HEAD: $review_head
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE
EOF

  cat > "$story_root/codex/20260214T000001Z_review.md" <<EOF
- Story: $story_id
- HEAD: $review_head
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 120

<<<REVIEW_TRANSCRIPT_BEGIN>>>
No P0 or P1 findings. All critical fail-closed paths verified.
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$story_root/codex/20260214T000002Z_review.md" <<EOF
- Story: $story_id
- HEAD: $review_head
- Generator Script: plans/codex_review_logged.sh
- Command Exit Code: 0
- Duration Seconds: 90

<<<REVIEW_TRANSCRIPT_BEGIN>>>
Second pass complete. No regressions found.
<<<REVIEW_TRANSCRIPT_END>>>
EOF

  cat > "$story_root/review_resolution.md" <<EOF
Story: $story_id
HEAD: $review_head
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
EOF

  cat > "$story_root/proof_graph.json" <<EOF
{
  "schema_version": 1,
  "head_sha": "$review_head",
  "generated_at": "2026-02-22T00:00:00+00:00",
  "story_meta": {
    "story_id": "$story_id",
    "category": "infrastructure",
    "enforcement_point": "WAL",
    "loss_mode": {"worst_case": "test", "fail_closed_cap": "test cap", "drift_metric": "test metric", "level": "LOW"},
    "safety_critical": false,
    "scope_touch": ["crates/soldier_infra/src/wal.rs"]
  },
  "ats": [{
    "at_id": "AT-001",
    "enforcement": {"status": "FOUND", "evidence": ["wal.rs:42"]},
    "tests": [
      {"test_name": "test_wal_write", "kind": "TRIP", "causal_proof": {"mechanism": "dispatch_count_assert", "dispatch_count_assert": "0"}, "execution": {"ran_at_head_sha": "$review_head", "pass_result": true}},
      {"test_name": "test_wal_read", "kind": "NON-TRIP", "causal_proof": {"mechanism": "dispatch_count_assert", "dispatch_count_assert": "1"}, "execution": {"ran_at_head_sha": "$review_head", "pass_result": true}}
    ],
    "wiring": {"status": "PROVEN_INTEGRATED", "evidence": "test calls wal directly"},
    "observability": {"metric": "wal_write_latency_ms", "alert": "wal_write_alert"},
    "premortem_checks": {"stoplight": "GREEN", "sections_filled": 10},
    "at_verdict": {"verdict": "PROVEN_INTEGRATED", "severity": "INFO", "rationale": "proven"}
  }],
  "story_verdict": {"reconciliation_status": "RECONCILED", "blocking_count": 0, "hardening_count": 0, "summary": "all proven"},
  "debt_register": []
}
EOF
}

setup_case() {
  local case_dir="$1"
  local verify_head="$2"
  local review_head="${3:-$verify_head}"

  mkdir -p "$case_dir/artifacts"
  cat > "$case_dir/prd.json" <<EOF
{
  "items": [
    {"id":"$story_id","passes":false,"category":"hardening","enforcing_contract_ats":["AT-001"],"enforcement_point":"WAL","loss_mode":{"worst_case":"test worst case","fail_closed_cap":"test cap","drift_metric":"test metric"}}
  ]
}
EOF

  cat > "$case_dir/artifacts/verify.meta.json" <<EOF
{
  "mode": "full",
  "head_sha": "$verify_head"
}
EOF

  printf '0\n' > "$case_dir/artifacts/preflight.rc"
  printf '0\n' > "$case_dir/artifacts/fail_closed_coverage.rc"
  printf '0\n' > "$case_dir/artifacts/proof_graph_${story_id}.rc"
  cat > "$case_dir/artifacts/contract_review.json" <<'EOF'
{
  "decision": "PASS"
}
EOF
  setup_story_review_artifacts "$case_dir" "$review_head"
}

# ── Test 1: missing --artifacts-dir value is rejected deterministically ──
set +e
missing_artifacts_arg_output="$(
  cd "$ROOT" && \
  "$SCRIPT" "$story_id" true --artifacts-dir 2>&1
)"
missing_artifacts_arg_rc=$?
set -e

[[ "$missing_artifacts_arg_rc" -eq 2 ]] || fail "expected exit 2 for missing --artifacts-dir value, got $missing_artifacts_arg_rc"
echo "$missing_artifacts_arg_output" | grep -Fq "ERROR: --artifacts-dir requires a value" || fail "missing artifacts-dir value diagnostic"

# ── Test 2: missing --contract-review value is rejected deterministically ──
set +e
missing_contract_arg_output="$(
  cd "$ROOT" && \
  "$SCRIPT" "$story_id" true --contract-review 2>&1
)"
missing_contract_arg_rc=$?
set -e

[[ "$missing_contract_arg_rc" -eq 2 ]] || fail "expected exit 2 for missing --contract-review value, got $missing_contract_arg_rc"
echo "$missing_contract_arg_output" | grep -Fq "ERROR: --contract-review requires a value" || fail "missing contract-review value diagnostic"

# ── Test 3: mid-run PRD mutation is rejected fail-closed ─────────────
prd_mutation_case="$tmp_dir/prd_mutation_during_head_check"
mkdir -p "$prd_mutation_case"
setup_case "$prd_mutation_case" "$head_sha"

git_mutation_wrapper_dir="$tmp_dir/git-wrapper-prd-mutation"
mkdir -p "$git_mutation_wrapper_dir"
cat > "$git_mutation_wrapper_dir/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

count_file="${TEST_GIT_COUNT_FILE:?missing TEST_GIT_COUNT_FILE}"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s\n' "$count" > "$count_file"

if [[ "$#" -ge 2 && "$1" == "rev-parse" && "$2" == "HEAD" ]]; then
  if [[ "$count" -eq 2 ]]; then
    python3 - <<'PY'
import json
import os

path = os.environ["TEST_MUTATE_PRD_FILE"]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
data["items"][0]["enforcement_point"] = "MUTATED_DURING_VALIDATION"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
  fi
  printf '%s\n' "${TEST_GIT_HEAD:?missing TEST_GIT_HEAD}"
  exit 0
fi

exec "${TEST_GIT_REAL:?missing TEST_GIT_REAL}" "$@"
EOF
chmod +x "$git_mutation_wrapper_dir/git"

set +e
prd_mutation_output="$(
  cd "$ROOT" && \
  PATH="$git_mutation_wrapper_dir:$PATH" \
  TEST_GIT_REAL="$real_git" \
  TEST_GIT_COUNT_FILE="$prd_mutation_case/git.count" \
  TEST_GIT_HEAD="$head_sha" \
  TEST_MUTATE_PRD_FILE="$prd_mutation_case/prd.json" \
  WF_STEP=/bin/true \
  PRD_FILE="$prd_mutation_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$prd_mutation_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$prd_mutation_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$prd_mutation_case/artifacts/contract_review.json" 2>&1
)"
prd_mutation_rc=$?
set -e

[[ "$prd_mutation_rc" -ne 0 ]] || fail "expected pass flip to fail when PRD mutates during validation"
echo "$prd_mutation_output" | grep -Fq "ERROR: PRD modified during validation: $prd_mutation_case/prd.json" || fail "missing mid-run PRD mutation diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$prd_mutation_case/prd.json" >/dev/null || fail "passes changed despite mid-run PRD mutation"

# ── Test 4: late PRD mutation before final rewrite is rejected ───────
late_prd_mutation_case="$tmp_dir/prd_mutation_during_rewrite"
mkdir -p "$late_prd_mutation_case"
setup_case "$late_prd_mutation_case" "$head_sha"

jq_mutation_wrapper_dir="$tmp_dir/jq-wrapper-prd-mutation"
mkdir -p "$jq_mutation_wrapper_dir"
cat > "$jq_mutation_wrapper_dir/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$*" == *'.passes = $status'* ]] && [[ ! -f "${TEST_JQ_MUTATION_MARKER:?missing TEST_JQ_MUTATION_MARKER}" ]]; then
  python3 - <<'PY'
import json
import os

path = os.environ["TEST_MUTATE_PRD_FILE"]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)
data["items"][0]["enforcement_point"] = "MUTATED_DURING_REWRITE"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(data, handle)
PY
  : > "${TEST_JQ_MUTATION_MARKER}"
fi

exec "${TEST_REAL_JQ:?missing TEST_REAL_JQ}" "$@"
EOF
chmod +x "$jq_mutation_wrapper_dir/jq"

set +e
late_prd_mutation_output="$(
  cd "$ROOT" && \
  PATH="$jq_mutation_wrapper_dir:$PATH" \
  TEST_REAL_JQ="$real_jq" \
  TEST_JQ_MUTATION_MARKER="$late_prd_mutation_case/jq.mutated" \
  TEST_MUTATE_PRD_FILE="$late_prd_mutation_case/prd.json" \
  WF_STEP=/bin/true \
  PRD_FILE="$late_prd_mutation_case/prd.json" \
  VERIFY_ARTIFACTS_DIR="$late_prd_mutation_case/artifacts" \
  STORY_ARTIFACTS_ROOT="$late_prd_mutation_case/story_artifacts" \
  "$SCRIPT" "$story_id" true \
  --contract-review "$late_prd_mutation_case/artifacts/contract_review.json" 2>&1
)"
late_prd_mutation_rc=$?
set -e

[[ "$late_prd_mutation_rc" -ne 0 ]] || fail "expected pass flip to fail when PRD mutates during rewrite"
echo "$late_prd_mutation_output" | grep -Fq "ERROR: PRD modified during validation: $late_prd_mutation_case/prd.json" || fail "missing late PRD mutation diagnostic"
jq -e --arg id "$story_id" 'any(.items[]; .id==$id and .passes==false)' "$late_prd_mutation_case/prd.json" >/dev/null || fail "passes changed despite late PRD mutation"

echo "PASS: prd_set_pass_hardening"
