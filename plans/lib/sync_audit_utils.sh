#!/usr/bin/env bash
# Utility functions for sync_audit.sh orchestrator

if [[ -n "${__SYNC_AUDIT_UTILS_SOURCED:-}" ]]; then
  return 0
fi
__SYNC_AUDIT_UTILS_SOURCED=1

# Hash computation (portable: Linux/macOS)
hash_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo "ERROR: File not found for hashing: $file" >&2
    return 1
  fi

  local hash_output
  if command -v sha256sum >/dev/null 2>&1; then
    hash_output=$(sha256sum "$file" 2>/dev/null | awk '{print $1}')
  elif command -v shasum >/dev/null 2>&1; then
    hash_output=$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')
  else
    echo "ERROR: neither sha256sum nor shasum available" >&2
    return 1
  fi

  if [[ -z "$hash_output" ]]; then
    echo "ERROR: Hash computation failed for $file" >&2
    return 1
  fi

  echo "$hash_output"
}

# Tool validation (mode-aware)
validate_tools() {
  local mode="$1"
  local errors=()

  if ! command -v jq >/dev/null 2>&1; then
    errors+=("jq")
  fi

  if ! command -v python3 >/dev/null 2>&1; then
    errors+=("python3")
  fi

  # PyYAML required for quick/full modes (check_csp_trace.py)
  if [[ "$mode" == "quick" || "$mode" == "full" ]]; then
    if ! python3 -c 'import yaml' >/dev/null 2>&1; then
      errors+=("python3 PyYAML module (pip install pyyaml)")
    fi
  fi

  if [[ ${#errors[@]} -gt 0 ]]; then
    echo "ERROR: Missing required tools: ${errors[*]}" >&2
    return 1
  fi
  return 0
}

# Disk space check (requires at least N MB free)
check_disk_space() {
  local dir="$1"
  local required_mb="$2"

  # Create dir if needed to check parent space
  mkdir -p "$dir" 2>/dev/null || true

  if command -v df >/dev/null 2>&1; then
    # Use POSIX-compliant df with explicit format (-P for portability)
    local available_kb
    available_kb=$(df -Pk "$dir" 2>/dev/null | awk 'NR==2 {print $4}')

    # Validate we got a number
    if [[ -z "$available_kb" || ! "$available_kb" =~ ^[0-9]+$ ]]; then
      echo "WARN: Could not determine disk space, skipping check" >&2
      return 0  # Fail open (don't block on measurement failure)
    fi

    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt $required_mb ]]; then
      echo "ERROR: Insufficient disk space in $dir (need ${required_mb}MB, have ${available_mb}MB)" >&2
      return 1
    fi
  else
    # df not available, skip check
    echo "WARN: df command not available, skipping disk space check" >&2
    return 0
  fi

  return 0
}

# Cache age calculation (returns days since cached_at timestamp)
get_cache_age_days() {
  local cached_at="$1"  # ISO8601 UTC timestamp

  # Convert ISO8601 to epoch (portable approach)
  local cached_epoch
  if command -v date >/dev/null 2>&1; then
    # Try GNU date first
    cached_epoch=$(date -d "$cached_at" +%s 2>/dev/null || date -j -f "%Y-%m-%dT%H:%M:%SZ" "$cached_at" +%s 2>/dev/null || echo "0")
    local now_epoch=$(date +%s)
    local age_seconds=$((now_epoch - cached_epoch))
    local age_days=$((age_seconds / 86400))
    echo "$age_days"
  else
    # Fallback: assume stale if we can't compute age
    echo "999"
  fi
}

# Extract CSP coverage from check_csp_trace.py JSON output
extract_csp_coverage() {
  local trace_log="$1"

  # check_csp_trace.py outputs JSON to stdout when --json flag is used
  # The orchestrator should run: check_csp_trace.py --json

  # Parse the JSON from the log file
  if [[ ! -f "$trace_log" ]]; then
    echo '{"total":0,"mapped":0,"partial":0,"unmapped":0,"pct":0.0}'
    return
  fi

  # Extract JSON output (check_csp_trace.py writes JSON directly when --json used)
  local json_output
  json_output=$(cat "$trace_log" 2>/dev/null || echo '{}')

  # Validate JSON and extract coverage fields with null-safety
  if ! echo "$json_output" | jq -e . >/dev/null 2>&1; then
    echo '{"total":0,"mapped":0,"partial":0,"unmapped":0,"pct":0.0}'
    return
  fi

  # check_csp_trace.py --json outputs .coverage.total (not .coverage.csp_trace.total)
  local total=$(echo "$json_output" | jq -r '.coverage.total // 0')
  local mapped=$(echo "$json_output" | jq -r '.coverage.mapped // 0')
  local partial=$(echo "$json_output" | jq -r '.coverage.partial // 0')
  local unmapped=$(echo "$json_output" | jq -r '.coverage.unmapped // 0')

  # Calculate percentage (avoid division by zero)
  local pct=0.0
  if [[ $total -gt 0 ]]; then
    if command -v bc >/dev/null 2>&1; then
      pct=$(echo "scale=1; ($mapped * 100.0) / $total" | bc 2>/dev/null || echo "0.0")
    else
      # Fallback to integer math if bc not available
      pct=$((mapped * 100 / total))
    fi
  fi

  cat <<JSON
{
  "total": $total,
  "mapped": $mapped,
  "partial": $partial,
  "unmapped": $unmapped,
  "pct": $pct
}
JSON
}

# Extract PRD audit summary from plans/prd_audit.json
extract_prd_audit_summary() {
  local audit_file="${1:-plans/prd_audit.json}"

  if [[ ! -f "$audit_file" ]]; then
    echo '{"total_items":0,"pass_items":0,"fail_items":0,"blocked_items":0}'
    return
  fi

  if ! jq -e . "$audit_file" >/dev/null 2>&1; then
    echo '{"total_items":0,"pass_items":0,"fail_items":0,"blocked_items":0}'
    return
  fi

  local total=$(jq -r '.summary.items_total // 0' "$audit_file")
  local pass=$(jq -r '.summary.items_pass // 0' "$audit_file")
  local fail=$(jq -r '.summary.items_fail // 0' "$audit_file")
  local blocked=$(jq -r '.summary.items_blocked // 0' "$audit_file")

  cat <<JSON
{
  "total_items": $total,
  "pass_items": $pass,
  "fail_items": $fail,
  "blocked_items": $blocked
}
JSON
}

# Format text report
format_text_report() {
  local run_id="$1"
  local mode="$2"
  local duration_seconds="$3"
  local status="$4"
  local artifacts_dir="$5"

  local csp_coverage_json="$6"
  local prd_audit_json="$7"

  # Parse coverage data
  local csp_total=$(echo "$csp_coverage_json" | jq -r '.total // 0')
  local csp_mapped=$(echo "$csp_coverage_json" | jq -r '.mapped // 0')
  local csp_unmapped=$(echo "$csp_coverage_json" | jq -r '.unmapped // 0')
  local csp_pct=$(echo "$csp_coverage_json" | jq -r '.pct // 0.0')

  # Read gate statuses from .rc files
  local schema_rc=$(cat "$artifacts_dir/prd_schema_check.rc" 2>/dev/null || echo "999")
  local ref_rc=$(cat "$artifacts_dir/prd_ref_check.rc" 2>/dev/null || echo "999")
  local trace_rc=$(cat "$artifacts_dir/check_csp_trace.rc" 2>/dev/null || echo "999")
  local audit_rc=$(cat "$artifacts_dir/prd_audit_check.rc" 2>/dev/null || echo "999")

  local schema_time=$(cat "$artifacts_dir/prd_schema_check.time" 2>/dev/null || echo "0")
  local ref_time=$(cat "$artifacts_dir/prd_ref_check.time" 2>/dev/null || echo "0")
  local trace_time=$(cat "$artifacts_dir/check_csp_trace.time" 2>/dev/null || echo "0")
  local audit_time=$(cat "$artifacts_dir/prd_audit_check.time" 2>/dev/null || echo "0")

  cat <<REPORT
=== Sync Audit Report ===
Run ID: $run_id
Mode: $mode
Duration: ${duration_seconds}s

GATE RESULTS:
  [$(gate_status_label $schema_rc)] prd_schema_check (${schema_time}s)
  [$(gate_status_label $ref_rc)] prd_ref_check (${ref_time}s)
  [$(gate_status_label $trace_rc)] check_csp_trace (${trace_time}s)
  [$(gate_status_label $audit_rc)] prd_audit_check (${audit_time}s)

CONTRACT ALIGNMENT STATUS:
  $(alignment_check_symbol $schema_rc) PRD Schema: $(alignment_status $schema_rc "valid" "invalid")
  $(alignment_check_symbol $ref_rc) PRD References: $(alignment_status $ref_rc "resolved" "unresolved")
  $(alignment_check_symbol $trace_rc) CSP Trace Coverage: ${csp_pct}% ($csp_mapped/$csp_total clauses mapped)
REPORT

  if [[ $csp_unmapped -gt 0 ]]; then
    echo "      ($csp_unmapped unmapped: see check_csp_trace.log for details)"
  fi

  if [[ "$mode" == "full" && "$audit_rc" != "999" ]]; then
    local audit_total=$(echo "$prd_audit_json" | jq -r '.total_items // 0')
    local audit_pass=$(echo "$prd_audit_json" | jq -r '.pass_items // 0')
    echo "  $(alignment_check_symbol $audit_rc) PRD Audit: ${audit_pass}/${audit_total} items passed"
  fi

  echo ""
  echo "OVERALL STATUS: $status"
  echo "Artifacts: $artifacts_dir"
}

# Format JSON report
format_json_report() {
  local run_id="$1"
  local mode="$2"
  local duration_seconds="$3"
  local status="$4"
  local artifacts_dir="$5"
  local csp_coverage_json="$6"
  local prd_audit_json="$7"

  # Read gate statuses
  local schema_rc=$(cat "$artifacts_dir/prd_schema_check.rc" 2>/dev/null || echo "999")
  local ref_rc=$(cat "$artifacts_dir/prd_ref_check.rc" 2>/dev/null || echo "999")
  local trace_rc=$(cat "$artifacts_dir/check_csp_trace.rc" 2>/dev/null || echo "999")
  local audit_rc=$(cat "$artifacts_dir/prd_audit_check.rc" 2>/dev/null || echo "999")

  local schema_time=$(cat "$artifacts_dir/prd_schema_check.time" 2>/dev/null || echo "0")
  local ref_time=$(cat "$artifacts_dir/prd_ref_check.time" 2>/dev/null || echo "0")
  local trace_time=$(cat "$artifacts_dir/check_csp_trace.time" 2>/dev/null || echo "0")
  local audit_time=$(cat "$artifacts_dir/prd_audit_check.time" 2>/dev/null || echo "0")

  # Calculate drift indicators
  local csp_unmapped=$(echo "$csp_coverage_json" | jq -r '.unmapped // 0')
  local schema_valid=$([ "$schema_rc" -eq 0 ] && echo "true" || echo "false")
  local refs_valid=$([ "$ref_rc" -eq 0 ] && echo "true" || echo "false")

  cat <<JSON
{
  "schema_version": 1,
  "run_id": "$run_id",
  "mode": "$mode",
  "status": "$status",
  "duration_seconds": $duration_seconds,
  "gates": [
    {"name": "prd_schema_check", "status": "$(gate_status_name $schema_rc)", "rc": $schema_rc, "duration_seconds": $schema_time},
    {"name": "prd_ref_check", "status": "$(gate_status_name $ref_rc)", "rc": $ref_rc, "duration_seconds": $ref_time},
    {"name": "check_csp_trace", "status": "$(gate_status_name $trace_rc)", "rc": $trace_rc, "duration_seconds": $trace_time},
    {"name": "prd_audit_check", "status": "$(gate_status_name $audit_rc)", "rc": $audit_rc, "duration_seconds": $audit_time}
  ],
  "coverage": {
    "csp_trace": $csp_coverage_json,
    "prd_audit": $prd_audit_json
  },
  "drift_detected": {
    "contract_unmapped_csp_clauses": $csp_unmapped,
    "prd_schema_valid": $schema_valid,
    "refs_valid": $refs_valid
  }
}
JSON
}

# Helper functions for status display
gate_status_label() {
  local rc="$1"
  case "$rc" in
    0) echo "PASS" ;;
    999) echo "SKIP" ;;
    124|137) echo "TIMEOUT" ;;
    *) echo "FAIL" ;;
  esac
}

gate_status_name() {
  local rc="$1"
  case "$rc" in
    0) echo "pass" ;;
    999) echo "skip" ;;
    124|137) echo "timeout" ;;
    *) echo "fail" ;;
  esac
}

alignment_check_symbol() {
  local rc="$1"
  case "$rc" in
    0) echo "✓" ;;
    999) echo "○" ;;
    *) echo "✗" ;;
  esac
}

alignment_status() {
  local rc="$1"
  local pass_msg="$2"
  local fail_msg="$3"
  if [[ $rc -eq 0 ]]; then
    echo "$pass_msg"
  elif [[ $rc -eq 999 ]]; then
    echo "skipped"
  else
    echo "$fail_msg"
  fi
}

# M-11: Show cache status command
show_cache_status() {
  local cache_file="${CACHE_FILE:-.context/sync_audit_cache.json}"

  echo "=== Sync Audit Cache Status ==="
  echo ""

  if [[ ! -f "$cache_file" ]]; then
    echo "Status: No cache exists"
    echo "Next run: Will execute all gates fresh"
    return 0
  fi

  if ! jq -e . "$cache_file" >/dev/null 2>&1; then
    echo "Status: Cache corrupted (invalid JSON)"
    echo "Next run: Will regenerate cache"
    return 0
  fi

  local schema_version=$(jq -r '.schema_version // 0' "$cache_file")
  local cached_at=$(jq -r '.cached_at // "unknown"' "$cache_file")
  local cache_mode=$(jq -r '.mode // "unknown"' "$cache_file")
  local cache_age_days=$(get_cache_age_days "$cached_at")

  echo "Status: Cache exists"
  echo "Schema version: v$schema_version (current: v${CACHE_SCHEMA_VERSION:-1})"
  echo "Created: $cached_at ($cache_age_days days ago)"
  echo "Mode: $cache_mode"
  echo "TTL: ${CACHE_TTL_DAYS:-7} days"
  echo ""

  # Check validity
  local valid=1
  local reasons=()

  if [[ "$schema_version" != "${CACHE_SCHEMA_VERSION:-1}" ]]; then
    valid=0
    reasons+=("Schema version mismatch")
  fi

  if [[ $cache_age_days -gt ${CACHE_TTL_DAYS:-7} ]]; then
    valid=0
    reasons+=("Expired (age > TTL)")
  fi

  # Check fingerprints
  local prd_file="${PRD_FILE:-plans/prd.json}"
  local contract_file="${CONTRACT_FILE:-specs/CONTRACT.md}"
  local plan_file="${PLAN_FILE:-specs/IMPLEMENTATION_PLAN.md}"

  if [[ -f "$prd_file" ]]; then
    local current_prd_sha=$(hash_file "$prd_file" 2>/dev/null || echo "ERROR")
    local cached_prd_sha=$(jq -r '.fingerprints.prd_file // "missing"' "$cache_file")
    if [[ "$current_prd_sha" != "$cached_prd_sha" ]]; then
      valid=0
      reasons+=("PRD file changed")
    fi
  fi

  if [[ -f "$contract_file" ]]; then
    local current_contract_sha=$(hash_file "$contract_file" 2>/dev/null || echo "ERROR")
    local cached_contract_sha=$(jq -r '.fingerprints.contract_file // "missing"' "$cache_file")
    if [[ "$current_contract_sha" != "$cached_contract_sha" ]]; then
      valid=0
      reasons+=("Contract file changed")
    fi
  fi

  if [[ $valid -eq 1 ]]; then
    echo "Validity: ✓ Valid (next run will use cached results)"
  else
    echo "Validity: ✗ Invalid"
    for reason in "${reasons[@]}"; do
      echo "  - $reason"
    done
    echo "Next run: Will execute all gates fresh"
  fi

  echo ""
  echo "Cached gate results:"
  jq -r '.gate_results | to_entries[] | "  \(.key): exit \(.value)"' "$cache_file" 2>/dev/null || echo "  (none)"

  echo ""
  echo "Notes:"
  echo "  - Cache is per-working-directory, not per-git-branch"
  echo "  - Cache does NOT track tool versions (Python, jq, system packages)"
  echo "  - Run with --no-cache to force fresh execution"
  echo "  - Run with --no-cache after environment changes (upgrades, installs)"
}

# M-14: Simple mode - run gates without cache/artifacts (30-line equivalent)
run_simple_mode() {
  echo "=== Running sync audit in simple mode (no cache/artifacts) ===" >&2

  local prd_file="${PRD_FILE:-plans/prd.json}"
  local contract_file="${CONTRACT_FILE:-specs/CONTRACT.md}"
  local plan_file
  if [[ -f "specs/IMPLEMENTATION_PLAN.md" ]]; then
    plan_file="specs/IMPLEMENTATION_PLAN.md"
  else
    plan_file="IMPLEMENTATION_PLAN.md"
  fi
  local trace_file="${TRACE_FILE:-specs/TRACE.yaml}"

  # Phase 1: Schema & Structure
  ./plans/prd_schema_check.sh "$prd_file" || return $?
  ./plans/prd_ref_check.sh "$prd_file" || return $?

  # Phase 2: Contract Traceability (skip in smoke mode)
  if [[ "${MODE:-quick}" != "smoke" ]]; then
    python3 ./scripts/check_csp_trace.py --contract "$contract_file" --trace "$trace_file" --json || return $?
  fi

  # Phase 3: Content Validation (only in full mode)
  if [[ "${MODE:-quick}" == "full" ]]; then
    if [[ ! -f "plans/prd_audit.json" || ! -f ".context/prd_auditor_stdout.log" ]]; then
      echo "ERROR: PRD audit artifacts missing. Run ./plans/run_prd_auditor.sh first." >&2
      return 2
    fi
    ./plans/prd_audit_check.sh || return $?
  fi

  echo "=== All checks passed ===" >&2
  return 0
}

# M-7: Cleanup old artifacts (retention policy)
cleanup_old_artifacts() {
  local artifacts_base="$1"
  local retention_days="$2"

  # Safety checks
  if [[ -z "$artifacts_base" || ! -d "$artifacts_base" ]]; then
    return 0  # Nothing to clean
  fi

  if [[ ! "$retention_days" =~ ^[0-9]+$ ]]; then
    echo "WARN: Invalid retention days: $retention_days, skipping cleanup" >&2
    return 0
  fi

  # Find and remove directories older than retention period
  # Use mtime (modification time) for age check
  local count_before=$(find "$artifacts_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo 0)

  # Portable find command (works on macOS and Linux)
  # -mtime +N means "modified more than N days ago"
  if command -v find >/dev/null 2>&1; then
    find "$artifacts_base" -mindepth 1 -maxdepth 1 -type d -mtime "+$retention_days" -exec rm -rf {} + 2>/dev/null || true
  fi

  local count_after=$(find "$artifacts_base" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo 0)
  local count_removed=$((count_before - count_after))

  if [[ $count_removed -gt 0 ]]; then
    echo "INFO: Cleaned up $count_removed artifact directories older than $retention_days days" >&2
  fi
}
