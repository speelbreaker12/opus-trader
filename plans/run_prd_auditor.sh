#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Lock file to prevent concurrent runs
AUDIT_LOCK_FILE="${AUDIT_LOCK_FILE:-.context/prd_auditor.lock}"
mkdir -p "$(dirname "$AUDIT_LOCK_FILE")"
if command -v flock >/dev/null 2>&1; then
  exec 201>"$AUDIT_LOCK_FILE"
  if ! flock -n 201; then
    echo "[prd_auditor] ERROR: another auditor is running" >&2
    exit 6
  fi
else
  # Fallback for macOS: use mkdir atomicity
  if ! mkdir "$AUDIT_LOCK_FILE.d" 2>/dev/null; then
    echo "[prd_auditor] ERROR: another auditor is running (lock: $AUDIT_LOCK_FILE.d)" >&2
    exit 6
  fi
  trap 'rmdir "$AUDIT_LOCK_FILE.d" 2>/dev/null || true' EXIT
fi

# Timeout for agent calls
AUDITOR_TIMEOUT="${AUDITOR_TIMEOUT:-600}"

AUDITOR_PROMPT="${AUDITOR_PROMPT:-prompts/auditor.md}"
AUDITOR_AGENT_CMD="${AUDITOR_AGENT_CMD:-codex}"
AUDITOR_AGENT_ARGS="${AUDITOR_AGENT_ARGS:-}"
AUDITOR_PROMPT_FLAG="${AUDITOR_PROMPT_FLAG:-}"
AUDIT_OUTPUT_JSON="${AUDIT_OUTPUT_JSON:-plans/prd_audit.json}"
AUDIT_PRD_FILE="${AUDIT_PRD_FILE:-plans/prd.json}"
AUDIT_CACHE_FILE="${AUDIT_CACHE_FILE:-.context/prd_audit_cache.json}"
AUDIT_STDOUT_LOG="${AUDIT_STDOUT_LOG:-.context/prd_auditor_stdout.log}"
AUDIT_CONTRACT_FILE="${AUDIT_CONTRACT_FILE:-}"
AUDIT_PLAN_FILE="${AUDIT_PLAN_FILE:-}"
AUDIT_WORKFLOW_CONTRACT_FILE="${AUDIT_WORKFLOW_CONTRACT_FILE:-}"
AUDIT_SCOPE="${AUDIT_SCOPE:-${PRD_AUDIT_SCOPE:-full}}"
AUDIT_SLICE="${AUDIT_SLICE:-${PRD_AUDIT_SLICE:-}}"
AUDIT_META_FILE="${AUDIT_META_FILE:-.context/prd_audit_meta.json}"
AUDIT_CONTRACT_DIGEST_FILE="${AUDIT_CONTRACT_DIGEST_FILE:-.context/contract_digest.json}"
AUDIT_PLAN_DIGEST_FILE="${AUDIT_PLAN_DIGEST_FILE:-.context/plan_digest.json}"
AUDIT_CONTRACT_SLICE_DIGEST_FILE="${AUDIT_CONTRACT_SLICE_DIGEST_FILE:-.context/contract_digest_slice.json}"
AUDIT_PLAN_SLICE_DIGEST_FILE="${AUDIT_PLAN_SLICE_DIGEST_FILE:-.context/plan_digest_slice.json}"
AUDIT_PRD_SLICE_FILE="${AUDIT_PRD_SLICE_FILE:-.context/prd_slice.json}"

if [[ ! -f "$AUDITOR_PROMPT" ]]; then
  echo "[prd_auditor] ERROR: missing prompt file: $AUDITOR_PROMPT" >&2
  exit 2
fi

if [[ -z "${AUDITOR_AGENT_CMD:-}" ]]; then
  echo "[prd_auditor] ERROR: AUDITOR_AGENT_CMD is empty" >&2
  exit 2
fi

if ! command -v "$AUDITOR_AGENT_CMD" >/dev/null 2>&1; then
  echo "[prd_auditor] ERROR: AUDITOR_AGENT_CMD not found: $AUDITOR_AGENT_CMD" >&2
  exit 2
fi

if [[ "$AUDITOR_AGENT_CMD" == "codex" && -z "$AUDITOR_AGENT_ARGS" ]]; then
  AUDITOR_AGENT_ARGS="exec"
fi

sha256_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

# Progress reporting (controllable via AUDIT_PROGRESS env var)
AUDIT_PROGRESS="${AUDIT_PROGRESS:-1}"

# Fail-fast mode: stop at first FAIL item (useful for iteration)
AUDIT_FAIL_FAST="${AUDIT_FAIL_FAST:-0}"
export AUDIT_FAIL_FAST

# Cost tracking (append-only JSONL log)
AUDIT_COST_FILE="${AUDIT_COST_FILE:-.context/audit_costs.jsonl}"
_audit_start_ts=""
_audit_run_id=""
_audit_stage_ts=""

audit_cost_start() {
  _audit_start_ts=$(date +%s)
  _audit_stage_ts=$_audit_start_ts
  _audit_run_id=$(echo "${_audit_start_ts}$$" | shasum -a 256 | cut -c1-8)
  mkdir -p "$(dirname "$AUDIT_COST_FILE")"
}

audit_cost_stage() {
  local stage="$1"
  local cache_hit="${2:-false}"
  local now=$(date +%s)
  local duration=$((now - _audit_stage_ts))
  echo "{\"run_id\":\"$_audit_run_id\",\"stage\":\"$stage\",\"duration_s\":$duration,\"cache_hit\":$cache_hit,\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$AUDIT_COST_FILE"
  _audit_stage_ts=$now
}

audit_cost_end() {
  local decision="$1"
  local total_duration=$(($(date +%s) - _audit_start_ts))
  echo "{\"run_id\":\"$_audit_run_id\",\"stage\":\"complete\",\"decision\":\"$decision\",\"total_duration_s\":$total_duration,\"ts\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >> "$AUDIT_COST_FILE"
}

progress() {
  local msg="$1"
  if [[ "$AUDIT_PROGRESS" == "1" ]]; then
    echo "[prd_auditor] $msg" >&2
  fi
}

resolve_input_file() {
  local preferred="$1"
  local fallback="$2"
  if [[ -n "$preferred" && -f "$preferred" ]]; then
    echo "$preferred"
    return 0
  fi
  if [[ -n "$fallback" && -f "$fallback" ]]; then
    echo "$fallback"
    return 0
  fi
  echo ""
}

if [[ ! -f "$AUDIT_PRD_FILE" ]]; then
  echo "[prd_auditor] ERROR: missing PRD file: $AUDIT_PRD_FILE" >&2
  exit 2
fi

expected_sha="$(sha256_file "$AUDIT_PRD_FILE")"
if [[ -z "$expected_sha" ]]; then
  echo "[prd_auditor] ERROR: unable to compute sha256 for $AUDIT_PRD_FILE" >&2
  exit 2
fi

if [[ -z "$AUDIT_CONTRACT_FILE" ]]; then
  AUDIT_CONTRACT_FILE="$(resolve_input_file "specs/CONTRACT.md" "CONTRACT.md")"
fi
if [[ -z "$AUDIT_PLAN_FILE" ]]; then
  AUDIT_PLAN_FILE="$(resolve_input_file "specs/IMPLEMENTATION_PLAN.md" "IMPLEMENTATION_PLAN.md")"
fi
if [[ -z "$AUDIT_WORKFLOW_CONTRACT_FILE" ]]; then
  AUDIT_WORKFLOW_CONTRACT_FILE="$(resolve_input_file "specs/WORKFLOW_CONTRACT.md" "WORKFLOW_CONTRACT.md")"
fi

# ROADMAP support (optional - unblocks slice 0 policy/infra items)
AUDIT_ROADMAP_FILE="${AUDIT_ROADMAP_FILE:-}"
AUDIT_ROADMAP_DIGEST_FILE="${AUDIT_ROADMAP_DIGEST_FILE:-.context/roadmap_digest.json}"
AUDIT_ROADMAP_SLICE_DIGEST_FILE="${AUDIT_ROADMAP_SLICE_DIGEST_FILE:-.context/roadmap_digest_slice.json}"

if [[ -z "$AUDIT_ROADMAP_FILE" ]]; then
  AUDIT_ROADMAP_FILE="$(resolve_input_file "docs/ROADMAP.md" "ROADMAP.md")"
fi
roadmap_sha=""
if [[ -n "$AUDIT_ROADMAP_FILE" && -f "$AUDIT_ROADMAP_FILE" ]]; then
  roadmap_sha="$(sha256_file "$AUDIT_ROADMAP_FILE")"
fi

if [[ -z "$AUDIT_CONTRACT_FILE" || -z "$AUDIT_PLAN_FILE" || -z "$AUDIT_WORKFLOW_CONTRACT_FILE" ]]; then
  echo "[prd_auditor] ERROR: missing contract/plan/workflow contract file (contract=$AUDIT_CONTRACT_FILE plan=$AUDIT_PLAN_FILE workflow=$AUDIT_WORKFLOW_CONTRACT_FILE)" >&2
  exit 2
fi

contract_sha="$(sha256_file "$AUDIT_CONTRACT_FILE")"
plan_sha="$(sha256_file "$AUDIT_PLAN_FILE")"
workflow_sha="$(sha256_file "$AUDIT_WORKFLOW_CONTRACT_FILE")"
prompt_sha="$(sha256_file "$AUDITOR_PROMPT")"

audit_cache_matches() {
  if ! command -v jq >/dev/null 2>&1; then
    return 1
  fi
  if [[ ! -f "$AUDIT_CACHE_FILE" || ! -f "$AUDIT_OUTPUT_JSON" ]]; then
    return 1
  fi
  if ! jq -e \
    --arg prd_sha "$expected_sha" \
    --arg contract_sha "$contract_sha" \
    --arg plan_sha "$plan_sha" \
    --arg workflow_sha "$workflow_sha" \
    --arg prompt_sha "$prompt_sha" \
    '
      .prd_sha256 == $prd_sha and
      .contract_sha256 == $contract_sha and
      .impl_plan_sha256 == $plan_sha and
      .workflow_contract_sha256 == $workflow_sha and
      .auditor_prompt_sha256 == $prompt_sha and
      .audited_scope == "full" and
      .decision == "PASS"
    ' "$AUDIT_CACHE_FILE" >/dev/null 2>&1; then
    return 1
  fi
  if ! jq -e \
    --arg prd_sha "$expected_sha" \
    '
      .prd_sha256 == $prd_sha and
      ((.summary.items_fail | tonumber? // 1) == 0) and
      ((.summary.items_blocked | tonumber? // 1) == 0)
    ' "$AUDIT_OUTPUT_JSON" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

if audit_cache_matches; then
  audit_check_prd_file="$AUDIT_PRD_FILE"
  if [[ "$AUDIT_SCOPE" == "slice" ]]; then
    audit_check_prd_file="$AUDIT_PRD_SLICE_FILE"
  fi
  if [[ ! -x "./plans/prd_audit_check.sh" ]]; then
    echo "[prd_auditor] ERROR: missing audit check script: ./plans/prd_audit_check.sh" >&2
    exit 2
  fi
  AUDIT_PROMISE_REQUIRED=0 \
    PRD_FILE="$audit_check_prd_file" \
    AUDIT_FILE="$AUDIT_OUTPUT_JSON" \
    AUDIT_STDOUT="$AUDIT_STDOUT_LOG" \
    ./plans/prd_audit_check.sh
  echo "[prd_auditor] SKIP: audit cache matches inputs and last decision PASS" >&2
  exit 0
fi

progress "Cache miss, running full audit..."
audit_cost_start

# Pre-flight validation (fast, no LLM)
if [[ -x "./plans/prd_preflight.sh" ]]; then
  progress "Running pre-flight validation..."
  if ! ./plans/prd_preflight.sh "$AUDIT_PRD_FILE"; then
    echo "[prd_auditor] ERROR: Pre-flight validation failed" >&2
    exit 2
  fi
fi

mkdir -p ".context"

progress "Building contract digest..."
CONTRACT_SOURCE_FILE="$AUDIT_CONTRACT_FILE" CONTRACT_DIGEST_FILE="$AUDIT_CONTRACT_DIGEST_FILE" ./plans/build_contract_digest.sh
audit_cost_stage "contract_digest"

progress "Building plan digest..."
PLAN_SOURCE_FILE="$AUDIT_PLAN_FILE" PLAN_DIGEST_FILE="$AUDIT_PLAN_DIGEST_FILE" ./plans/build_plan_digest.sh
audit_cost_stage "plan_digest"

# Build ROADMAP digest if available
if [[ -n "$AUDIT_ROADMAP_FILE" && -f "$AUDIT_ROADMAP_FILE" ]]; then
  progress "Building roadmap digest..."
  SOURCE_FILE="$AUDIT_ROADMAP_FILE" \
    OUTPUT_FILE="$AUDIT_ROADMAP_DIGEST_FILE" \
    DIGEST_MODE="slim" \
    ./plans/build_markdown_digest.sh
  audit_cost_stage "roadmap_digest"
fi

if [[ "$AUDIT_SCOPE" == "slice" ]]; then
  if [[ -z "$AUDIT_SLICE" ]]; then
    echo "[prd_auditor] ERROR: AUDIT_SLICE required when AUDIT_SCOPE=slice" >&2
    exit 2
  fi
  progress "Preparing slice $AUDIT_SLICE..."
  PRD_FILE="$AUDIT_PRD_FILE" \
    PRD_SLICE="$AUDIT_SLICE" \
    CONTRACT_DIGEST="$AUDIT_CONTRACT_DIGEST_FILE" \
    PLAN_DIGEST="$AUDIT_PLAN_DIGEST_FILE" \
    ROADMAP_DIGEST="$AUDIT_ROADMAP_DIGEST_FILE" \
    OUT_PRD_SLICE="$AUDIT_PRD_SLICE_FILE" \
    OUT_CONTRACT_DIGEST="$AUDIT_CONTRACT_SLICE_DIGEST_FILE" \
    OUT_PLAN_DIGEST="$AUDIT_PLAN_SLICE_DIGEST_FILE" \
    OUT_ROADMAP_DIGEST="$AUDIT_ROADMAP_SLICE_DIGEST_FILE" \
    OUT_AUDIT_FILE="$AUDIT_OUTPUT_JSON" \
    OUT_META="$AUDIT_META_FILE" \
    ./plans/prd_slice_prepare.sh
  audit_cost_stage "slice_prepare"
else
  if ! command -v jq >/dev/null 2>&1; then
    echo "[prd_auditor] ERROR: jq required to write audit meta" >&2
    exit 2
  fi
  jq -n \
    --arg audit_scope "full" \
    --arg prd_sha "$expected_sha" \
    --arg prd_file "$AUDIT_PRD_FILE" \
    --arg contract_digest "$AUDIT_CONTRACT_DIGEST_FILE" \
    --arg plan_digest "$AUDIT_PLAN_DIGEST_FILE" \
    --arg output_file "$AUDIT_OUTPUT_JSON" \
    --arg generated_at "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{audit_scope:$audit_scope, prd_sha256:$prd_sha, prd_file:$prd_file, contract_digest:$contract_digest, plan_digest:$plan_digest, output_file:$output_file, generated_at:$generated_at}' \
    > "$AUDIT_META_FILE"
fi

AUDITOR_AGENT_ARGS_ARR=()
if [[ -n "$AUDITOR_AGENT_ARGS" ]]; then
  _old_ifs="$IFS"; IFS=$' \t\n'
  read -r -a AUDITOR_AGENT_ARGS_ARR <<<"$AUDITOR_AGENT_ARGS"
  IFS="$_old_ifs"
fi

run_auditor() {
  local prompt meta_json
  prompt="$(cat "$AUDITOR_PROMPT")"

  # Embed meta file content directly in prompt to avoid parallel execution race conditions
  if [[ -f "$AUDIT_META_FILE" ]]; then
    meta_json="$(cat "$AUDIT_META_FILE")"
    prompt="${prompt//__AUDIT_META_PLACEHOLDER__/$meta_json}"
  else
    echo "[prd_auditor] ERROR: missing audit meta file: $AUDIT_META_FILE" >&2
    return 1
  fi

  if [[ -n "$AUDITOR_AGENT_ARGS" ]]; then
    if [[ -n "${AUDITOR_PROMPT_FLAG:-}" ]]; then
      "$AUDITOR_AGENT_CMD" "${AUDITOR_AGENT_ARGS_ARR[@]}" "$AUDITOR_PROMPT_FLAG" "$prompt"
    else
      "$AUDITOR_AGENT_CMD" "${AUDITOR_AGENT_ARGS_ARR[@]}" "$prompt"
    fi
  else
    if [[ -n "${AUDITOR_PROMPT_FLAG:-}" ]]; then
      "$AUDITOR_AGENT_CMD" "$AUDITOR_PROMPT_FLAG" "$prompt"
    else
      "$AUDITOR_AGENT_CMD" "$prompt"
    fi
  fi
}

mkdir -p "$(dirname "$AUDIT_STDOUT_LOG")"

progress "Starting auditor agent (timeout=${AUDITOR_TIMEOUT}s)..."

# Run auditor with timeout
auditor_start_ts="$(date +%s)"
auditor_rc=0
if command -v timeout >/dev/null 2>&1; then
  timeout "$AUDITOR_TIMEOUT" bash -c "$(declare -f run_auditor); run_auditor" > "$AUDIT_STDOUT_LOG" 2>&1 || auditor_rc=$?
elif command -v gtimeout >/dev/null 2>&1; then
  gtimeout "$AUDITOR_TIMEOUT" bash -c "$(declare -f run_auditor); run_auditor" > "$AUDIT_STDOUT_LOG" 2>&1 || auditor_rc=$?
else
  run_auditor > "$AUDIT_STDOUT_LOG" 2>&1 || auditor_rc=$?
fi
auditor_end_ts="$(date +%s)"
auditor_duration=$((auditor_end_ts - auditor_start_ts))
progress "Auditor completed in ${auditor_duration}s (rc=$auditor_rc)"
audit_cost_stage "auditor"

if [[ "$auditor_rc" -eq 124 || "$auditor_rc" -eq 137 ]]; then
  echo "[prd_auditor] ERROR: auditor timed out after ${AUDITOR_TIMEOUT}s" >&2
  exit 5
fi

# Auditor prompt hardcodes output to plans/prd_audit.json
# If AUDIT_OUTPUT_JSON differs, copy the output to the expected location
AUDITOR_DEFAULT_OUTPUT="plans/prd_audit.json"
if [[ "$AUDIT_OUTPUT_JSON" != "$AUDITOR_DEFAULT_OUTPUT" && -f "$AUDITOR_DEFAULT_OUTPUT" && ! -f "$AUDIT_OUTPUT_JSON" ]]; then
  progress "Copying audit output to $AUDIT_OUTPUT_JSON"
  mkdir -p "$(dirname "$AUDIT_OUTPUT_JSON")"
  cp "$AUDITOR_DEFAULT_OUTPUT" "$AUDIT_OUTPUT_JSON"
fi

if [[ ! -f "$AUDIT_OUTPUT_JSON" ]]; then
  echo "[prd_auditor] ERROR: auditor did not produce $AUDIT_OUTPUT_JSON" >&2
  exit 3
fi

progress "Validating audit output..."

if command -v jq >/dev/null 2>&1; then
  if ! jq -e . "$AUDIT_OUTPUT_JSON" >/dev/null 2>&1; then
    echo "[prd_auditor] ERROR: $AUDIT_OUTPUT_JSON is not valid JSON" >&2
    exit 4
  fi
  audit_sha="$(jq -r '.prd_sha256 // empty' "$AUDIT_OUTPUT_JSON")"
  if [[ -z "$audit_sha" ]]; then
    echo "[prd_auditor] ERROR: $AUDIT_OUTPUT_JSON missing prd_sha256" >&2
    exit 4
  fi
  # In slice mode, the auditor may use either the full PRD SHA or slice PRD SHA
  # Accept either to allow flexibility in auditor implementation
  validate_sha="$expected_sha"
  if [[ "$AUDIT_SCOPE" == "slice" && -f "$AUDIT_PRD_SLICE_FILE" ]]; then
    slice_sha="$(sha256_file "$AUDIT_PRD_SLICE_FILE")"
    if [[ "$audit_sha" != "$expected_sha" && "$audit_sha" != "$slice_sha" ]]; then
      echo "[prd_auditor] ERROR: prd_sha256 mismatch (expected $expected_sha or $slice_sha, got $audit_sha)" >&2
      exit 4
    fi
  elif [[ "$audit_sha" != "$expected_sha" ]]; then
    echo "[prd_auditor] ERROR: prd_sha256 mismatch (expected $expected_sha, got $audit_sha)" >&2
    exit 4
  fi
fi

if [[ ! -x "./plans/prd_audit_check.sh" ]]; then
  echo "[prd_auditor] ERROR: missing audit check script: ./plans/prd_audit_check.sh" >&2
  exit 2
fi
audit_check_prd_file="$AUDIT_PRD_FILE"
if [[ "$AUDIT_SCOPE" == "slice" ]]; then
  audit_check_prd_file="$AUDIT_PRD_SLICE_FILE"
fi
AUDIT_PROMISE_REQUIRED=1 \
  PRD_FILE="$audit_check_prd_file" \
  AUDIT_FILE="$AUDIT_OUTPUT_JSON" \
  AUDIT_STDOUT="$AUDIT_STDOUT_LOG" \
  ./plans/prd_audit_check.sh

write_audit_cache() {
  if ! command -v jq >/dev/null 2>&1; then
    return 0
  fi
  local decision="BLOCKED"
  local items_fail
  local items_blocked
  items_fail="$(jq -r '.summary.items_fail // empty' "$AUDIT_OUTPUT_JSON" 2>/dev/null || true)"
  items_blocked="$(jq -r '.summary.items_blocked // empty' "$AUDIT_OUTPUT_JSON" 2>/dev/null || true)"
  if [[ "$items_fail" =~ ^[0-9]+$ && "$items_blocked" =~ ^[0-9]+$ ]]; then
    if (( items_fail > 0 )); then
      decision="FAIL"
    elif (( items_blocked > 0 )); then
      decision="BLOCKED"
    else
      decision="PASS"
    fi
  fi
  mkdir -p "$(dirname "$AUDIT_CACHE_FILE")"
  jq -n \
    --arg prd_sha "$expected_sha" \
    --arg contract_sha "$contract_sha" \
    --arg plan_sha "$plan_sha" \
    --arg workflow_sha "$workflow_sha" \
    --arg roadmap_sha "$roadmap_sha" \
    --arg prompt_sha "$prompt_sha" \
    --arg decision "$decision" \
    --arg audited_scope "$AUDIT_SCOPE" \
    --arg slice "${AUDIT_SLICE:-}" \
    --arg audit_json "$AUDIT_OUTPUT_JSON" \
    --arg contract_file "$AUDIT_CONTRACT_FILE" \
    --arg plan_file "$AUDIT_PLAN_FILE" \
    --arg workflow_file "$AUDIT_WORKFLOW_CONTRACT_FILE" \
    --arg roadmap_file "${AUDIT_ROADMAP_FILE:-}" \
    --arg prompt_file "$AUDITOR_PROMPT" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      prd_sha256: $prd_sha,
      contract_sha256: $contract_sha,
      impl_plan_sha256: $plan_sha,
      workflow_contract_sha256: $workflow_sha,
      roadmap_sha256: $roadmap_sha,
      auditor_prompt_sha256: $prompt_sha,
      audited_scope: $audited_scope,
      slice: $slice,
      decision: $decision,
      audit_json: $audit_json,
      contract_file: $contract_file,
      plan_file: $plan_file,
      workflow_contract_file: $workflow_file,
      roadmap_file: $roadmap_file,
      auditor_prompt: $prompt_file,
      timestamp: $timestamp
    }' > "$AUDIT_CACHE_FILE"
}

write_audit_cache

# Track cost with final decision
if command -v jq >/dev/null 2>&1; then
  _final_decision="UNKNOWN"
  _items_fail="$(jq -r '.summary.items_fail // empty' "$AUDIT_OUTPUT_JSON" 2>/dev/null || true)"
  _items_blocked="$(jq -r '.summary.items_blocked // empty' "$AUDIT_OUTPUT_JSON" 2>/dev/null || true)"
  if [[ "$_items_fail" =~ ^[0-9]+$ && "$_items_blocked" =~ ^[0-9]+$ ]]; then
    if (( _items_fail > 0 )); then
      _final_decision="FAIL"
    elif (( _items_blocked > 0 )); then
      _final_decision="BLOCKED"
    else
      _final_decision="PASS"
    fi
  fi
  audit_cost_end "$_final_decision"
fi
