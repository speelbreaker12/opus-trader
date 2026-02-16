#!/usr/bin/env bash
# Unified Sync Audit Orchestrator
# Validates synchronization between Contract, Implementation Plan, PRD, and Roadmap
#
# Exit codes:
#   0  All checks passed
#   1  Validation failures from prd_ref_check.sh (unresolved refs)
#   2  Infrastructure error OR validation failure from non-schema gates
#   3  Missing PRD file from prd_schema_check.sh
#   4  Invalid PRD JSON from prd_schema_check.sh
#   5  Schema violation from prd_schema_check.sh

set -euo pipefail

VERSION="1.0.0"

# Defaults
MODE="${SYNC_AUDIT_MODE:-quick}"
OUTPUT_JSON=0
NO_CACHE=0
PRD_FILE="${PRD_FILE:-plans/prd.json}"
ARTIFACTS_BASE="${SYNC_AUDIT_ARTIFACTS_DIR:-}"

# Canonical paths (no overrides allowed - prevents split-brain validation)
CONTRACT_FILE="specs/CONTRACT.md"
TRACE_FILE="specs/TRACE.yaml"
if [[ -f "specs/IMPLEMENTATION_PLAN.md" ]]; then
  PLAN_FILE="specs/IMPLEMENTATION_PLAN.md"
else
  PLAN_FILE="IMPLEMENTATION_PLAN.md"
fi

CACHE_FILE=".context/sync_audit_cache.json"
CACHE_TTL_DAYS=7

# Timing
START_TIME=$(date +%s)

# Usage
usage() {
  cat <<'USAGE'
Usage: ./plans/sync_audit.sh [OPTIONS]

Options:
  --mode quick     Schema + refs + CSP trace (default, <30s)
  --mode full      All checks including PRD audit validation
  --mode smoke     Schema + refs only (fastest, <5s)
  --json           Output JSON report to stdout
  --no-cache       Force re-run all gates (ignore cache)
  --version        Print version and exit
  -h, --help       Show this help

Environment:
  SYNC_AUDIT_MODE=quick|full|smoke      (default: quick)
  PRD_FILE=plans/prd.json               (passed to gates)
  SYNC_AUDIT_ARTIFACTS_DIR=...          (override artifacts location)

Exit codes:
  0  All checks passed
  1  Validation failures (unresolved refs)
  2  Infrastructure error or other gate failures
  3  Missing PRD file
  4  Invalid PRD JSON
  5  Schema violation
USAGE
}

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --json)
      OUTPUT_JSON=1
      shift
      ;;
    --no-cache)
      NO_CACHE=1
      shift
      ;;
    --version)
      echo "sync_audit.sh version $VERSION"
      exit 0
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

# Validate mode
case "$MODE" in
  smoke|quick|full) ;;
  *)
    echo "ERROR: Invalid mode: $MODE (expected smoke|quick|full)" >&2
    exit 2
    ;;
esac

# Find repository root first
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Convert PRD_FILE to absolute path before changing directories
if [[ -n "$PRD_FILE" && ! "$PRD_FILE" = /* ]]; then
  PRD_FILE="$(cd "$(dirname "$PRD_FILE")" 2>/dev/null && pwd)/$(basename "$PRD_FILE")" || {
    echo "ERROR: Cannot resolve PRD_FILE path: $PRD_FILE" >&2
    exit 2
  }
fi

# Validate PRD_FILE is within repository (prevent path traversal)
case "$PRD_FILE" in
  "$ROOT"*)
    # Path is within repository, OK
    ;;
  *)
    echo "ERROR: PRD_FILE must be within repository root: $ROOT" >&2
    echo "ERROR: Provided path: $PRD_FILE" >&2
    exit 2
    ;;
esac

cd "$ROOT"

# Source utilities
if [[ ! -f "$ROOT/plans/lib/sync_audit_utils.sh" ]]; then
  echo "ERROR: Missing utility file: plans/lib/sync_audit_utils.sh" >&2
  exit 2
fi
source "$ROOT/plans/lib/sync_audit_utils.sh"

# Setup run ID and artifacts directory
RUN_ID=$(date -u +"%Y%m%d_%H%M%S")
if [[ -z "$ARTIFACTS_BASE" ]]; then
  ARTIFACTS_DIR="$ROOT/artifacts/sync_audit/$RUN_ID"
else
  ARTIFACTS_DIR="$ARTIFACTS_BASE"
fi

# Cleanup function - removes temp files on exit
cleanup_on_exit() {
  local exit_code=$?
  # Remove temp cache file if it exists
  rm -f "$CACHE_FILE.tmp" 2>/dev/null || true
  return $exit_code
}
trap cleanup_on_exit EXIT ERR

# Preflight validation (mode-aware)
preflight_checks() {
  local mode="$1"

  # Tool validation
  if ! validate_tools "$mode"; then
    exit 2
  fi

  # Disk space check (require 10MB free)
  if ! check_disk_space "$ROOT/artifacts" 10; then
    exit 2
  fi

  # Check write permissions
  if ! mkdir -p "$ARTIFACTS_DIR" 2>/dev/null; then
    echo "ERROR: Cannot create artifacts directory: $ARTIFACTS_DIR" >&2
    exit 2
  fi

  # Validate required files exist
  local required_files=("$PRD_FILE" "$CONTRACT_FILE" "$PLAN_FILE")

  if [[ "$mode" == "quick" || "$mode" == "full" ]]; then
    required_files+=("$TRACE_FILE")
  fi

  for file in "${required_files[@]}"; do
    if [[ ! -f "$file" ]]; then
      echo "ERROR: Required file missing: $file" >&2
      exit 2
    fi
  done
}

# Cache check
check_cache() {
  if [[ $NO_CACHE -eq 1 ]]; then
    return 1  # Cache invalid
  fi

  if [[ ! -f "$CACHE_FILE" ]]; then
    return 1  # Cache missing
  fi

  # Validate JSON first
  if ! jq -e . "$CACHE_FILE" >/dev/null 2>&1; then
    echo "WARN: Corrupted cache file, regenerating" >&2
    return 1
  fi

  # Check TTL
  local cached_at=$(jq -r '.cached_at // empty' "$CACHE_FILE")
  if [[ -z "$cached_at" ]]; then
    return 1  # Missing timestamp
  fi

  local cache_age_days=$(get_cache_age_days "$cached_at")
  if [[ $cache_age_days -gt $CACHE_TTL_DAYS ]]; then
    echo "WARN: Cache older than ${CACHE_TTL_DAYS} days, regenerating" >&2
    return 1
  fi

  # Verify SHA256 fingerprints (invalidate cache if hashing fails)
  local prd_sha
  local contract_sha
  local plan_sha

  prd_sha=$(hash_file "$PRD_FILE") || {
    echo "WARN: Failed to hash PRD file, invalidating cache" >&2
    return 1
  }
  contract_sha=$(hash_file "$CONTRACT_FILE") || {
    echo "WARN: Failed to hash contract file, invalidating cache" >&2
    return 1
  }
  plan_sha=$(hash_file "$PLAN_FILE") || {
    echo "WARN: Failed to hash plan file, invalidating cache" >&2
    return 1
  }

  local cached_prd_sha=$(jq -r '.fingerprints.prd_file // empty' "$CACHE_FILE")
  local cached_contract_sha=$(jq -r '.fingerprints.contract_file // empty' "$CACHE_FILE")
  local cached_plan_sha=$(jq -r '.fingerprints.plan_file // empty' "$CACHE_FILE")

  if [[ "$prd_sha" != "$cached_prd_sha" || "$contract_sha" != "$cached_contract_sha" || "$plan_sha" != "$cached_plan_sha" ]]; then
    return 1  # Input files changed
  fi

  # Check TRACE file for quick/full modes
  if [[ "$MODE" == "quick" || "$MODE" == "full" ]]; then
    local trace_sha
    trace_sha=$(hash_file "$TRACE_FILE") || {
      echo "WARN: Failed to hash trace file, invalidating cache" >&2
      return 1
    }
    local cached_trace_sha=$(jq -r '.fingerprints.trace_file // empty' "$CACHE_FILE")
    if [[ "$trace_sha" != "$cached_trace_sha" ]]; then
      return 1
    fi
  fi

  return 0  # Cache valid
}

# Write cache (atomic write with temp file)
write_cache() {
  local temp_cache="${CACHE_FILE}.tmp"

  mkdir -p "$(dirname "$CACHE_FILE")"

  local prd_sha
  local contract_sha
  local plan_sha
  local trace_sha=""

  # Hash all input files (skip cache write if any fail)
  prd_sha=$(hash_file "$PRD_FILE") || {
    echo "WARN: Failed to hash PRD file, skipping cache write" >&2
    return 1
  }
  contract_sha=$(hash_file "$CONTRACT_FILE") || {
    echo "WARN: Failed to hash contract file, skipping cache write" >&2
    return 1
  }
  plan_sha=$(hash_file "$PLAN_FILE") || {
    echo "WARN: Failed to hash plan file, skipping cache write" >&2
    return 1
  }

  if [[ -f "$TRACE_FILE" ]]; then
    trace_sha=$(hash_file "$TRACE_FILE") || {
      echo "WARN: Failed to hash trace file, skipping cache write" >&2
      return 1
    }
  fi

  local now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

  cat > "$temp_cache" <<JSON
{
  "cached_at": "$now",
  "mode": "$MODE",
  "fingerprints": {
    "prd_file": "$prd_sha",
    "contract_file": "$contract_sha",
    "plan_file": "$plan_sha",
    "trace_file": "$trace_sha"
  },
  "gate_results": {
    "prd_schema_check": $1,
    "prd_ref_check": $2,
    "check_csp_trace": $3
  }
}
JSON

  # Atomic rename
  mv "$temp_cache" "$CACHE_FILE"
}

# Run gate with timeout
run_gate() {
  local gate_name="$1"
  local timeout_seconds="$2"
  shift 2
  local cmd=("$@")

  local gate_log="$ARTIFACTS_DIR/${gate_name}.log"
  local gate_rc="$ARTIFACTS_DIR/${gate_name}.rc"
  local gate_time="$ARTIFACTS_DIR/${gate_name}.time"

  local gate_start=$(date +%s)

  # Determine timeout command (portable: Linux/macOS)
  local timeout_cmd=""
  if command -v timeout >/dev/null 2>&1; then
    timeout_cmd="timeout ${timeout_seconds}s"
  elif command -v gtimeout >/dev/null 2>&1; then
    timeout_cmd="gtimeout ${timeout_seconds}s"
  fi

  # Run gate with timeout
  local rc=0
  if [[ -n "$timeout_cmd" ]]; then
    $timeout_cmd "${cmd[@]}" >"$gate_log" 2>&1 || rc=$?
  else
    "${cmd[@]}" >"$gate_log" 2>&1 || rc=$?
  fi

  # Check for timeout exit codes
  if [[ $rc -eq 124 || $rc -eq 137 ]]; then
    echo "TIMEOUT: gate exceeded ${timeout_seconds}s" >> "$gate_log"
  fi

  local gate_end=$(date +%s)
  local gate_duration=$((gate_end - gate_start))

  # Handle clock skew (negative duration)
  if [[ $gate_duration -lt 0 ]]; then
    echo "WARN: Clock skew detected (negative duration), using 0" >&2
    gate_duration=0
  fi

  echo "$rc" > "$gate_rc"
  echo "$gate_duration" > "$gate_time"

  return $rc
}

# Run gate with cache support (reduces duplication)
run_or_cache_gate() {
  local gate_name="$1"
  local cache_key="$2"
  local timeout_seconds="$3"
  shift 3
  local cmd=("$@")

  # Check if using cached results
  if [[ $use_cache -eq 1 ]]; then
    local cached_rc=$(jq -r ".gate_results.$cache_key // 999" "$CACHE_FILE")
    echo "$cached_rc" > "$ARTIFACTS_DIR/${gate_name}.rc"
    echo "0" > "$ARTIFACTS_DIR/${gate_name}.time"
    echo "(cached)" > "$ARTIFACTS_DIR/${gate_name}.log"
    return 0
  fi

  # Run gate fresh
  if ! run_gate "$gate_name" "$timeout_seconds" "${cmd[@]}"; then
    local rc=$(cat "$ARTIFACTS_DIR/${gate_name}.rc")
    first_failed_gate="$gate_name"
    exit_code=$rc
    echo "$first_failed_gate" > "$ARTIFACTS_DIR/FAILED_GATE"
    return $rc
  fi

  return 0
}

# Main execution flow
main() {
  # Preflight validation
  preflight_checks "$MODE"

  # Cache check
  local use_cache=0
  if check_cache; then
    use_cache=1
    echo "INFO: Using cached results (run with --no-cache to force re-run)" >&2
  fi

  # Track first failure for fail-fast
  local first_failed_gate=""
  local exit_code=0

  # Phase 1: Schema & Structure (fast validation)

  # Gate 1: prd_schema_check
  run_or_cache_gate "prd_schema_check" "prd_schema_check" 30 ./plans/prd_schema_check.sh "$PRD_FILE"
  if [[ -n "$first_failed_gate" ]]; then
    write_report
    exit $exit_code
  fi

  # Gate 2: prd_ref_check
  run_or_cache_gate "prd_ref_check" "prd_ref_check" 60 ./plans/prd_ref_check.sh "$PRD_FILE"
  if [[ -n "$first_failed_gate" ]]; then
    write_report
    exit $exit_code
  fi

  # Phase 2: Contract Traceability (only in quick/full modes)

  # Gate 3: check_csp_trace (skip in smoke mode)
  if [[ "$MODE" == "smoke" ]]; then
    echo "999" > "$ARTIFACTS_DIR/check_csp_trace.rc"
    echo "0" > "$ARTIFACTS_DIR/check_csp_trace.time"
    echo "(skipped in smoke mode)" > "$ARTIFACTS_DIR/check_csp_trace.log"
  else
    run_or_cache_gate "check_csp_trace" "check_csp_trace" 120 python3 ./scripts/check_csp_trace.py --contract "$CONTRACT_FILE" --trace "$TRACE_FILE" --json
  fi

  if [[ -n "$first_failed_gate" ]]; then
    write_report
    exit $exit_code
  fi

  # Phase 3: Content Validation (only in full mode)

  # Gate 4: prd_audit_check (skip in smoke/quick modes)
  if [[ "$MODE" != "full" ]]; then
    echo "999" > "$ARTIFACTS_DIR/prd_audit_check.rc"
    echo "0" > "$ARTIFACTS_DIR/prd_audit_check.time"
    echo "(skipped - mode=$MODE)" > "$ARTIFACTS_DIR/prd_audit_check.log"
  else
    # PRD audit check is never cached (LLM-based, non-deterministic)
    # Hard-fail if required artifacts missing
    if [[ ! -f "plans/prd_audit.json" || ! -f ".context/prd_auditor_stdout.log" ]]; then
      echo "ERROR: PRD audit artifacts missing. Run ./plans/run_prd_auditor.sh first." >&2
      echo "2" > "$ARTIFACTS_DIR/prd_audit_check.rc"
      echo "0" > "$ARTIFACTS_DIR/prd_audit_check.time"
      echo "ERROR: Missing PRD audit artifacts" > "$ARTIFACTS_DIR/prd_audit_check.log"
      first_failed_gate="prd_audit_check"
      exit_code=2
      echo "$first_failed_gate" > "$ARTIFACTS_DIR/FAILED_GATE"
    else
      if ! run_gate "prd_audit_check" 30 ./plans/prd_audit_check.sh; then
        local rc=$(cat "$ARTIFACTS_DIR/prd_audit_check.rc")
        first_failed_gate="prd_audit_check"
        exit_code=$rc
        echo "$first_failed_gate" > "$ARTIFACTS_DIR/FAILED_GATE"
      fi
    fi
  fi

  if [[ -n "$first_failed_gate" ]]; then
    write_report
    exit $exit_code
  fi

  # All gates passed - update cache (if not using cached results)
  if [[ $use_cache -eq 0 ]]; then
    local schema_rc=$(cat "$ARTIFACTS_DIR/prd_schema_check.rc")
    local ref_rc=$(cat "$ARTIFACTS_DIR/prd_ref_check.rc")
    local trace_rc=$(cat "$ARTIFACTS_DIR/check_csp_trace.rc")
    # Attempt to write cache, but don't fail if it doesn't work
    write_cache "$schema_rc" "$ref_rc" "$trace_rc" || true
  fi

  # Generate reports
  write_report

  exit 0
}

# Write report (both text and JSON)
write_report() {
  local end_time=$(date +%s)
  local duration_seconds=$((end_time - START_TIME))

  # Determine overall status
  local schema_rc=$(cat "$ARTIFACTS_DIR/prd_schema_check.rc" 2>/dev/null || echo "999")
  local ref_rc=$(cat "$ARTIFACTS_DIR/prd_ref_check.rc" 2>/dev/null || echo "999")
  local trace_rc=$(cat "$ARTIFACTS_DIR/check_csp_trace.rc" 2>/dev/null || echo "999")
  local audit_rc=$(cat "$ARTIFACTS_DIR/prd_audit_check.rc" 2>/dev/null || echo "999")

  local status="pass"
  if [[ $schema_rc -ne 0 && $schema_rc -ne 999 ]]; then
    status="fail"
  elif [[ $ref_rc -ne 0 && $ref_rc -ne 999 ]]; then
    status="fail"
  elif [[ $trace_rc -ne 0 && $trace_rc -ne 999 ]]; then
    status="fail"
  elif [[ $audit_rc -ne 0 && $audit_rc -ne 999 ]]; then
    status="fail"
  fi

  # Extract coverage stats
  local csp_coverage_json=$(extract_csp_coverage "$ARTIFACTS_DIR/check_csp_trace.log")
  local prd_audit_json=$(extract_prd_audit_summary "plans/prd_audit.json")

  # Write metadata
  local meta_file="$ARTIFACTS_DIR/sync_audit.meta.json"
  format_json_report "$RUN_ID" "$MODE" "$duration_seconds" "$status" "$ARTIFACTS_DIR" "$csp_coverage_json" "$prd_audit_json" > "$meta_file"

  # Write text report to artifacts
  local text_report_file="$ARTIFACTS_DIR/sync_audit.report.txt"
  format_text_report "$RUN_ID" "$MODE" "$duration_seconds" "$status" "$ARTIFACTS_DIR" "$csp_coverage_json" "$prd_audit_json" > "$text_report_file"

  # Output to stdout based on --json flag
  if [[ $OUTPUT_JSON -eq 1 ]]; then
    cat "$meta_file"
  else
    cat "$text_report_file"
  fi
}

# Run main
main
