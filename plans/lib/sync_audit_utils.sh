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
    echo "" >&2
    return 1
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
  else
    echo "ERROR: neither sha256sum nor shasum available" >&2
    return 1
  fi
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

  local available_kb
  if command -v df >/dev/null 2>&1; then
    # Use df -k for portability (macOS/Linux)
    available_kb=$(df -k "$dir" | awk 'NR==2 {print $4}')
    local available_mb=$((available_kb / 1024))

    if [[ $available_mb -lt $required_mb ]]; then
      echo "ERROR: Insufficient disk space in $dir (need ${required_mb}MB, have ${available_mb}MB)" >&2
      return 1
    fi
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
    pct=$(echo "scale=1; ($mapped * 100.0) / $total" | bc 2>/dev/null || echo "0.0")
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
