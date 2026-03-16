#!/usr/bin/env bash
# =============================================================================
# plans/preflight.sh
# -----------------------------------------------------------------------------
# Purpose:
#   Lightweight preflight checks that run before verify.sh. Catches common
#   issues early (postmortem, schema, shell syntax) without the full verify cost.
#
# Usage:
#   ./plans/preflight.sh          # Run checks (smoke fixture profile by default)
#   ./plans/preflight.sh --strict # Fail on warnings (e.g., missing BASE_REF)
#
# Environment:
#   PREFLIGHT_FIXTURE_MODE=smoke|full|quick|none
#     smoke: fast fixture subset (default)
#     quick: alias for smoke (fast fixture subset)
#     full: full fixture matrix (used by verify full)
#     none: skip fixtures entirely
#   PREFLIGHT_NO_CACHE=1  Force re-run of fixture tests (ignore cache)
#
# Exit codes:
#   0 = all checks passed
#   1 = validation failed
#   2 = setup error (missing tools/files)
#
# Runtime target (smoke/quick): <60 seconds
# Runtime target (full): may take several minutes depending on fixture matrix
# =============================================================================

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# --- Parse arguments ---
STRICT_MODE=0
for arg in "$@"; do
  case "$arg" in
    --strict) STRICT_MODE=1 ;;
    --census|--census-json)
      echo "Unknown argument: $arg (census mode removed in fork; use ./plans/verify.sh quick|full)" >&2
      exit 2
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

PREFLIGHT_FIXTURE_MODE="${PREFLIGHT_FIXTURE_MODE:-smoke}"
case "$PREFLIGHT_FIXTURE_MODE" in
  quick) PREFLIGHT_FIXTURE_MODE="smoke" ;;
  none) ;;
  smoke|full) ;;
  *)
    echo "[FAIL] Invalid PREFLIGHT_FIXTURE_MODE='$PREFLIGHT_FIXTURE_MODE' (expected smoke|full|quick|none)" >&2
    exit 2
    ;;
esac

# --- Timeout detection (portable: timeout on Linux, gtimeout on macOS) ---
PREFLIGHT_GUARD_TIMEOUT="${PREFLIGHT_GUARD_TIMEOUT:-30}"
_TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  _TIMEOUT_BIN="gtimeout"
fi

supports_wait_n() {
  local wait_help_text=""

  if [[ "${BASH_VERSINFO[0]:-0}" -lt 4 ]]; then
    return 1
  fi
  if [[ "${BASH_VERSINFO[0]:-0}" -eq 4 ]] && [[ "${BASH_VERSINFO[1]:-0}" -lt 3 ]]; then
    return 1
  fi
  # Use the builtin explicitly so BASH_ENV function shadowing cannot spoof
  # wait -n support detection.
  if builtin help wait >/dev/null 2>&1; then
    wait_help_text="$(builtin help wait 2>/dev/null || true)"
    grep -Eq '(^|[[:space:]])-n([[:space:][:punct:]]|$)' <<< "$wait_help_text"
    return $?
  fi
  # If help text is unavailable on an otherwise compatible bash version,
  # trust version gating above.
  return 0
}

select_monotonic_backend() {
  local ns=""

  ns="$(date +%s%N 2>/dev/null || true)"
  if [[ "$ns" =~ ^[0-9]+$ ]] && [[ ${#ns} -gt 10 ]]; then
    echo "date_ns"
    return 0
  fi

  if command -v python3 >/dev/null 2>&1; then
    echo "python3"
    return 0
  fi

  if command -v python >/dev/null 2>&1; then
    echo "python"
    return 0
  fi

  if command -v perl >/dev/null 2>&1; then
    echo "perl"
    return 0
  fi

  echo "epoch_seconds"
}

detect_parallel_jobs() {
  local cpu_count=""
  local max_parallel_jobs=8

  if command -v sysctl >/dev/null 2>&1; then
    cpu_count="$(sysctl -n hw.ncpu 2>/dev/null || true)"
  fi

  if [[ ! "$cpu_count" =~ ^[1-9][0-9]*$ ]] && command -v getconf >/dev/null 2>&1; then
    cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"
  fi

  if [[ "$cpu_count" =~ ^[1-9][0-9]*$ ]]; then
    if (( cpu_count > max_parallel_jobs )); then
      cpu_count="$max_parallel_jobs"
    fi
    echo "$cpu_count"
  else
    echo 4
  fi
}

MONOTONIC_BACKEND="$(select_monotonic_backend)"
MONOTONIC_BACKEND_INIT_MARKER="monotonic_backend=$MONOTONIC_BACKEND"

now_monotonic_ns() {
  case "$MONOTONIC_BACKEND" in
    date_ns)
      date +%s%N 2>/dev/null || printf '%s000000000\n' "$(date +%s)"
      ;;
    python3)
      python3 -c 'import time; print(time.monotonic_ns())'
      ;;
    python)
      python -c 'import time; print(int(time.monotonic() * 1000000000))'
      ;;
    perl)
      perl -MTime::HiRes=time -e 'printf("%.0f\n", time() * 1000000000)'
      ;;
    *)
      printf '%s000000000\n' "$(date +%s)"
      ;;
  esac
}

# --- Counters ---
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0
SETUP_FAIL_COUNT=0

# --- Output helpers ---
pass() {
  echo "[PASS] $*"
  ((PASS_COUNT++)) || true
}

fail() {
  echo "[FAIL] $*" >&2
  ((FAIL_COUNT++)) || true
}

setup_fail() {
  echo "[FAIL] $*" >&2
  ((FAIL_COUNT++)) || true
  ((SETUP_FAIL_COUNT++)) || true
}

warn() {
  echo "[WARN] $*" >&2
  ((WARN_COUNT++)) || true
}

PREFLIGHT_DIAG_SCHEMA_VERSION=1
PREFLIGHT_DIAG_FIXTURE_MODE="$PREFLIGHT_FIXTURE_MODE"
PREFLIGHT_DIAG_FIXTURE_TEST_COUNT=0
PREFLIGHT_DIAG_CACHE_STATE="not_evaluated"
PREFLIGHT_DIAG_HASH_STRATEGY="not_evaluated"
PREFLIGHT_DIAG_CACHE_REASONS=()
PREFLIGHT_DIAG_PARALLEL_JOBS=0
PREFLIGHT_DIAG_FIXTURE_TIMEOUT_SECONDS=0
PREFLIGHT_DIAG_FIXTURE_RUNTIME_SECONDS=0
PREFLIGHT_DIAG_CACHE_FILE=""
PREFLIGHT_DIAG_ARTIFACT_PATH=""
if [[ -n "${VERIFY_ARTIFACTS_DIR:-}" ]]; then
  PREFLIGHT_DIAG_ARTIFACT_PATH="${VERIFY_ARTIFACTS_DIR}/preflight_diagnostics.json"
fi

preflight_diag_add_reason() {
  local reason="$1"
  local existing=""
  [[ -n "$reason" ]] || return 0
  for existing in "${PREFLIGHT_DIAG_CACHE_REASONS[@]-}"; do
    [[ -n "$existing" ]] || continue
    if [[ "$existing" == "$reason" ]]; then
      return 0
    fi
  done
  PREFLIGHT_DIAG_CACHE_REASONS+=("$reason")
}

preflight_diag_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

preflight_diag_json_array() {
  local item=""
  local first=1
  printf '['
  for item in "$@"; do
    [[ -n "$item" ]] || continue
    if [[ "$first" -eq 0 ]]; then
      printf ', '
    fi
    printf '"%s"' "$(preflight_diag_json_escape "$item")"
    first=0
  done
  printf ']'
}

preflight_diag_join_reasons() {
  local joined=""
  local item=""
  for item in "${PREFLIGHT_DIAG_CACHE_REASONS[@]-}"; do
    [[ -n "$item" ]] || continue
    if [[ -n "$joined" ]]; then
      joined="${joined},"
    fi
    joined="${joined}${item}"
  done
  if [[ -z "$joined" ]]; then
    joined="none"
  fi
  printf '%s\n' "$joined"
}

preflight_diag_emit() {
  local reasons_summary=""
  reasons_summary="$(preflight_diag_join_reasons)"

  if [[ -n "$PREFLIGHT_DIAG_ARTIFACT_PATH" ]]; then
    mkdir -p "$(dirname "$PREFLIGHT_DIAG_ARTIFACT_PATH")"
    cat > "$PREFLIGHT_DIAG_ARTIFACT_PATH" <<EOF
{
  "schema_version": $PREFLIGHT_DIAG_SCHEMA_VERSION,
  "fixture_mode": "$(preflight_diag_json_escape "$PREFLIGHT_DIAG_FIXTURE_MODE")",
  "fixture_test_count": $PREFLIGHT_DIAG_FIXTURE_TEST_COUNT,
  "cache_state": "$(preflight_diag_json_escape "$PREFLIGHT_DIAG_CACHE_STATE")",
  "hash_strategy": "$(preflight_diag_json_escape "$PREFLIGHT_DIAG_HASH_STRATEGY")",
  "cache_reasons": $(preflight_diag_json_array "${PREFLIGHT_DIAG_CACHE_REASONS[@]-}"),
  "parallel_jobs": $PREFLIGHT_DIAG_PARALLEL_JOBS,
  "fixture_timeout_seconds": $PREFLIGHT_DIAG_FIXTURE_TIMEOUT_SECONDS,
  "fixture_runtime_seconds": $PREFLIGHT_DIAG_FIXTURE_RUNTIME_SECONDS,
  "cache_file": "$(preflight_diag_json_escape "$PREFLIGHT_DIAG_CACHE_FILE")"
}
EOF
  fi

  echo "preflight diagnostics: fixture_mode=$PREFLIGHT_DIAG_FIXTURE_MODE tests=$PREFLIGHT_DIAG_FIXTURE_TEST_COUNT cache=$PREFLIGHT_DIAG_CACHE_STATE hash=$PREFLIGHT_DIAG_HASH_STRATEGY reasons=$reasons_summary"
}

PREFLIGHT_WAIT_N_MODE="${PREFLIGHT_WAIT_N_MODE:-auto}"
case "$PREFLIGHT_WAIT_N_MODE" in
  auto|force_on|force_off) ;;
  *)
    setup_fail "Invalid PREFLIGHT_WAIT_N_MODE='$PREFLIGHT_WAIT_N_MODE' (expected auto|force_on|force_off)"
    ;;
esac

PREFLIGHT_WAIT_N_SUPPORTED=0
if supports_wait_n; then
  PREFLIGHT_WAIT_N_SUPPORTED=1
fi

PREFLIGHT_WAIT_N_USE=0
if [[ "$PREFLIGHT_WAIT_N_MODE" == "force_on" ]]; then
  if [[ "$PREFLIGHT_WAIT_N_SUPPORTED" == "1" ]]; then
    PREFLIGHT_WAIT_N_USE=1
  else
    setup_fail "PREFLIGHT_WAIT_N_MODE=force_on requires wait -n support"
  fi
elif [[ "$PREFLIGHT_WAIT_N_MODE" == "force_off" ]]; then
  PREFLIGHT_WAIT_N_USE=0
elif [[ "$PREFLIGHT_WAIT_N_SUPPORTED" == "1" ]]; then
  PREFLIGHT_WAIT_N_USE=1
fi

prune_fixture_pids_once() {
  local alive=()
  local pid=""
  for pid in "${fixture_pids[@]}"; do
    if kill -0 "$pid" 2>/dev/null; then
      alive+=("$pid")
    fi
  done
  if [[ ${#alive[@]} -gt 0 ]]; then
    fixture_pids=("${alive[@]}")
  else
    fixture_pids=()
  fi
}

shift_fixture_pid_queue() {
  if [[ ${#fixture_pids[@]} -gt 1 ]]; then
    fixture_pids=("${fixture_pids[@]:1}")
  else
    fixture_pids=()
  fi
}

wait_for_fixture_slot() {
  local errexit=0
  local pid=""

  case "$-" in
    *e*) errexit=1 ;;
  esac

  if [[ "$PREFLIGHT_WAIT_N_USE" == "1" ]]; then
    if [[ ${#fixture_pids[@]} -gt 0 ]]; then
      set +e
      wait -n "${fixture_pids[@]}" 2>/dev/null || true
      if [[ "$errexit" == "1" ]]; then
        set -e
      fi
    fi
    prune_fixture_pids_once
    return 0
  fi

  while [[ ${#fixture_pids[@]} -ge $PREFLIGHT_PARALLEL_JOBS ]]; do
    prune_fixture_pids_once
    if [[ ${#fixture_pids[@]} -lt $PREFLIGHT_PARALLEL_JOBS ]]; then
      break
    fi

    while true; do
      for pid in "${fixture_pids[@]}"; do
        if ! kill -0 "$pid" 2>/dev/null; then
          prune_fixture_pids_once
          break 2
        fi
      done
      sleep 0.05
    done
  done
}

wait_for_all_fixture_jobs() {
  local pid=""
  local errexit=0

  case "$-" in
    *e*) errexit=1 ;;
  esac

  while [[ ${#fixture_pids[@]} -gt 0 ]]; do
    pid="${fixture_pids[0]}"
    set +e
    wait "$pid"
    if [[ "$errexit" == "1" ]]; then
      set -e
    fi
    shift_fixture_pid_queue
  done
}

# =============================================================================
# Tier 1: Instant checks (<5s)
# =============================================================================

# 1. Git repository check
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  pass "Git repository"
else
  setup_fail "Not a git repository: $ROOT"
fi

# 2. Required tools: git, jq, bash
check_tool() {
  local tool="$1"
  if command -v "$tool" >/dev/null 2>&1; then
    pass "Tool: $tool"
  else
    setup_fail "Missing required tool: $tool"
  fi
}

check_tool git
check_tool jq
check_tool bash

# 3. Required files
check_file() {
  local path="$1"
  local desc="${2:-$path}"
  if [[ -f "$path" ]]; then
    pass "File: $desc"
  else
    setup_fail "Missing required file: $path"
  fi
}

check_file "plans/prd.json" "PRD file"

# Honor CONTRACT_FILE override (consistent with verify.sh)
CONTRACT_FILE="${CONTRACT_FILE:-specs/CONTRACT.md}"
check_file "$CONTRACT_FILE" "Contract spec"

# 3b-3g. Fail-closed guards (parallel)
# These guards are independent — run them concurrently to reduce wall-clock time.
# Pre-check ensures all scripts exist and are executable before backgrounding (fail-closed).
PREFLIGHT_GUARD_SCRIPTS=(
  "plans/legacy_layout_guard.sh:Legacy layout guard"
  "plans/premortem_path_guard.sh:Premortem path canonicalization guard"
  "plans/readme_ci_parity_check.sh:README/CI parity guard"
  "plans/slice_completion_review_guard.sh:Slice completion review guard"
  "plans/story_review_findings_guard.sh:Story findings-review guard"
  "plans/stoic_cli_invariant_check.sh:stoic-cli invariants guard"
  "plans/toggle_policy_check.sh:Toggle policy wiring guard"
)

# Pre-check: all scripts must exist and be executable (fail-closed)
for _guard_entry in "${PREFLIGHT_GUARD_SCRIPTS[@]}"; do
  _guard_script="${_guard_entry%%:*}"
  if [[ ! -f "$_guard_script" ]]; then
    echo "[FAIL] Missing guard: $_guard_script (setup error)" >&2
    exit 2
  fi
  if [[ ! -x "$_guard_script" ]]; then
    echo "[FAIL] Guard not executable: $_guard_script (setup error)" >&2
    exit 2
  fi
done

# Run guards in parallel, capturing output to per-guard log files for debuggability.
_guard_results_dir="$(mktemp -d)"
_preflight_cleanup_dirs=("$_guard_results_dir")
trap 'rm -rf "${_preflight_cleanup_dirs[@]}"' EXIT
_guard_pids=()
_guard_idx=0
for _guard_entry in "${PREFLIGHT_GUARD_SCRIPTS[@]}"; do
  _guard_script="${_guard_entry%%:*}"
  _idx=$_guard_idx
  (
    if [[ -n "$_TIMEOUT_BIN" ]]; then
      _guard_cmd=("$_TIMEOUT_BIN" "$PREFLIGHT_GUARD_TIMEOUT" bash "$_guard_script")
    else
      _guard_cmd=(bash "$_guard_script")
    fi
    if "${_guard_cmd[@]}" > "$_guard_results_dir/${_idx}.log" 2>&1; then
      echo "PASS" > "$_guard_results_dir/$_idx"
    else
      echo "FAIL" > "$_guard_results_dir/$_idx"
    fi
  ) &
  _guard_pids+=($!)
  ((_guard_idx++)) || true
done
wait "${_guard_pids[@]}" 2>/dev/null || true

# Collect results in original order; on failure, emit the guard's captured log
_guard_idx=0
for _guard_entry in "${PREFLIGHT_GUARD_SCRIPTS[@]}"; do
  _guard_desc="${_guard_entry#*:}"
  _guard_result="$(cat "$_guard_results_dir/$_guard_idx" 2>/dev/null || echo "FAIL")"
  if [[ "$_guard_result" == "PASS" ]]; then
    pass "$_guard_desc"
  else
    fail "$_guard_desc failed"
    # Emit captured output so the developer can see why the guard failed
    if [[ -s "$_guard_results_dir/${_guard_idx}.log" ]]; then
      echo "--- guard output (${_guard_entry%%:*}) ---" >&2
      cat "$_guard_results_dir/${_guard_idx}.log" >&2
      echo "--- end guard output ---" >&2
    fi
  fi
  ((_guard_idx++)) || true
done

# =============================================================================
# Tier 2: Fast checks (<30s)
# =============================================================================

# 4. Shell syntax: authoritative per-file parse (fail-closed on setup errors)
SHELL_SYNTAX_OK=1
SHELL_ERRORS=()
if compgen -G "plans/*.sh" >/dev/null; then
  SHELL_SYNTAX_CHECKER=""
  if ! SHELL_SYNTAX_CHECKER="$(command -v bash 2>/dev/null)"; then
    SHELL_SYNTAX_CHECKER=""
  fi
  if [[ -z "$SHELL_SYNTAX_CHECKER" ]]; then
    setup_fail "Shell syntax setup failed (missing bash)"
    SHELL_ERRORS+=("<shell-syntax-setup>")
    SHELL_SYNTAX_OK=0
  else
    # Authoritative check: every plans/*.sh file must parse on its own.
    for f in plans/*.sh; do
      if "$SHELL_SYNTAX_CHECKER" -n "$f" >/dev/null 2>&1; then
        _shell_syntax_rc=0
      else
        _shell_syntax_rc=$?
      fi
      if [[ "$_shell_syntax_rc" -eq 0 ]]; then
        continue
      fi
      case "$_shell_syntax_rc" in
        2)
          SHELL_SYNTAX_OK=0
          SHELL_ERRORS+=("$f")
          ;;
        *)
          setup_fail "Shell syntax setup failed while checking $f (bash -n rc=$_shell_syntax_rc)"
          SHELL_ERRORS+=("<shell-syntax-setup>")
          SHELL_SYNTAX_OK=0
          break
          ;;
      esac
    done
  fi
fi

if [[ "$SHELL_SYNTAX_OK" == "1" ]]; then
  pass "Shell syntax (plans/*.sh)"
else
  fail "Shell syntax errors in: ${SHELL_ERRORS[*]}"
fi

# 5. PRD schema: plans/prd_schema_check.sh
PRD_SCHEMA_CHECK="plans/prd_schema_check.sh"
if [[ -x "$PRD_SCHEMA_CHECK" ]]; then
  if "$PRD_SCHEMA_CHECK" "plans/prd.json" >/dev/null 2>&1; then
    pass "PRD schema validation"
  else
    fail "PRD schema validation failed (run $PRD_SCHEMA_CHECK for details)"
  fi
elif [[ -f "$PRD_SCHEMA_CHECK" ]]; then
  echo "[FAIL] PRD schema check not executable: $PRD_SCHEMA_CHECK (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing PRD schema check: $PRD_SCHEMA_CHECK (setup error)" >&2
  exit 2
fi

# 6. Fixture checks for review tooling scripts (fail-closed)
# Split into fast smoke checks (default) vs full matrix checks (full verify).
SMOKE_REVIEW_FIXTURE_TESTS=(
  "plans/tests/test_run_prd_auditor_invocation.sh"
  "plans/tests/test_slice_review_gate.sh"
  "plans/tests/test_guard_no_command_substitution.sh"
  "plans/tests/test_story_review_findings_guard.sh"
  "plans/tests/test_fork_attestation_remediation_verify.sh"
  "plans/tests/test_fork_attestation_mirror.sh"
  "plans/tests/test_workflow_quick_step.sh"
  "plans/tests/test_toggle_policy_check.sh"
  "plans/tests/test_stoic_cli_invariant_check.sh"
  "plans/tests/test_verify_timeout_policy.sh"
  "plans/tests/test_live_enable_preflight.sh"
  "plans/tests/test_fail_closed_gate_map_paths.sh"
  "plans/tests/test_rust_gates_smoke_targets.sh"
  "plans/tests/test_rust_gates_quick_clippy.sh"
  "plans/tests/test_contract_kernel_drift_message.sh"
  "plans/tests/test_recon_handoff_sources.sh"
  "plans/tests/test_roadmap_evidence_audit.sh"
  "plans/tests/test_crossref_invariants.sh"
  "plans/tests/test_premortem_path_guard.sh"
)

FULL_ONLY_REVIEW_FIXTURE_TESTS=(
  "plans/tests/test_adversarial_gate.sh"
  "plans/tests/test_codex_review_digest.sh"
  "plans/tests/test_run_prd_auditor_timeout_fallback.sh"
  "plans/tests/test_audit_parallel_empty_cache_arrays.sh"
  "plans/tests/test_slice_completion_review_guard.sh"
  "plans/tests/test_slice_completion_enforce.sh"
  "plans/tests/test_pre_pr_review_gate.sh"
  # Heavy recon integration fixtures stay in verify coverage, but not in quick smoke.
  "plans/tests/test_preflight_fixture_timeout_controls.sh"
  "plans/tests/test_recon_bundle.sh"
  "plans/tests/test_recon_operator_runner.sh"
  "plans/tests/test_recon_scoreboard.sh"
)
FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS=(
  # This pass-gate fixture still flakes when it shares the parallel preflight
  # batch with other review-gate tests. Keep it in full coverage, but drain it
  # serially after the parallel batch.
  "plans/tests/test_prd_set_pass.sh"
)
# NOTE: heavy workflow integration fixtures run in verify_fork.sh gate 14g
# (parallel with rust compilation) instead of preflight smoke so the cheap
# preflight loop stays within the quick-mode timeout budget.

REVIEW_FIXTURE_TESTS=("${SMOKE_REVIEW_FIXTURE_TESTS[@]}")
SERIAL_REVIEW_FIXTURE_TESTS=()
if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then
  REVIEW_FIXTURE_TESTS+=("${FULL_ONLY_REVIEW_FIXTURE_TESTS[@]}")
  SERIAL_REVIEW_FIXTURE_TESTS+=("${FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS[@]}")
fi
PREFLIGHT_DIAG_FIXTURE_TEST_COUNT=$(( ${#REVIEW_FIXTURE_TESTS[@]} + ${#SERIAL_REVIEW_FIXTURE_TESTS[@]} ))
PREFLIGHT_PARALLEL_JOBS_RAW="${PREFLIGHT_PARALLEL_JOBS-}"
if [[ -z "$PREFLIGHT_PARALLEL_JOBS_RAW" ]]; then
  PREFLIGHT_DIAG_PARALLEL_JOBS="$(detect_parallel_jobs)"
  PREFLIGHT_PARALLEL_JOBS=""
elif [[ "$PREFLIGHT_PARALLEL_JOBS_RAW" =~ ^[1-9][0-9]*$ ]]; then
  PREFLIGHT_DIAG_PARALLEL_JOBS="$PREFLIGHT_PARALLEL_JOBS_RAW"
  PREFLIGHT_PARALLEL_JOBS="$PREFLIGHT_PARALLEL_JOBS_RAW"
else
  setup_fail "Invalid PREFLIGHT_PARALLEL_JOBS='$PREFLIGHT_PARALLEL_JOBS_RAW' (expected positive integer worker count)"
  PREFLIGHT_DIAG_PARALLEL_JOBS=1
  PREFLIGHT_PARALLEL_JOBS=1
fi
fixture_diag_started_ns="$(now_monotonic_ns)"

if [[ "$PREFLIGHT_FIXTURE_MODE" == "none" ]]; then
  PREFLIGHT_DIAG_CACHE_STATE="skipped"
  PREFLIGHT_DIAG_HASH_STRATEGY="skipped"
  pass "Fixture tests skipped (mode=none)"
else
  pass "Fixture profile: $PREFLIGHT_FIXTURE_MODE (${#REVIEW_FIXTURE_TESTS[@]} tests)"

  fixture_timeout_default=240
  if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then
    fixture_timeout_default=300
  fi
  PREFLIGHT_FIXTURE_TIMEOUT_INVALID=0
  PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW="${PREFLIGHT_FIXTURE_TEST_TIMEOUT:-$fixture_timeout_default}"
  PREFLIGHT_FIXTURE_TEST_TIMEOUT="$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW"
  PREFLIGHT_DIAG_FIXTURE_TIMEOUT_SECONDS="$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW"
  # 0 means explicit no-timeout for fixture jobs.
  if [[ ! "$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW" =~ ^[0-9]+$ ]]; then
    setup_fail "Invalid PREFLIGHT_FIXTURE_TEST_TIMEOUT='$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW' (expected non-negative integer seconds)"
    PREFLIGHT_FIXTURE_TIMEOUT_INVALID=1
    PREFLIGHT_FIXTURE_TEST_TIMEOUT=0
    PREFLIGHT_DIAG_FIXTURE_TIMEOUT_SECONDS=0
  fi

  # --- Fixture cache ---
  # Cache key = SHA256 of all workflow/tool/spec files that fixture tests depend on.
  # Broad scope prevents stale cache from missed dependencies.
  PREFLIGHT_NO_CACHE="${PREFLIGHT_NO_CACHE:-0}"
  if [[ "$PREFLIGHT_NO_CACHE" == "1" ]]; then
    preflight_diag_add_reason "requested_no_cache"
  fi
  # --strict implies thoroughness: disable cache to ensure all tests actually run
  if [[ "$STRICT_MODE" == "1" ]]; then
    preflight_diag_add_reason "strict_mode"
    PREFLIGHT_NO_CACHE=1
  fi
  if [[ "$PREFLIGHT_FIXTURE_TIMEOUT_INVALID" == "1" ]]; then
    preflight_diag_add_reason "invalid_fixture_timeout"
    PREFLIGHT_NO_CACHE=1
  fi
  _cache_dir="$ROOT/.cache"
  _cache_file="$_cache_dir/preflight_fixtures_${PREFLIGHT_FIXTURE_MODE}.hash"
  PREFLIGHT_DIAG_CACHE_FILE="${_cache_file#$ROOT/}"
  _cache_hit=0
  PREFLIGHT_COMPUTED_FIXTURE_HASH=""

  _compute_fixture_hash_from_list() {
    local _file_list="$1"
    local _normalized_list=""
    local _hash=""

    _normalized_list="$(printf '%s\n' "$_file_list" | LC_ALL=C sort -u | sed '/^[[:space:]]*$/d')" || return 1
    [[ -n "$_normalized_list" ]] || return 1

    _hash="$(
      printf '%s\n' "$_normalized_list" \
        | xargs shasum -a 256 2>/dev/null \
        | shasum -a 256 \
        | cut -d' ' -f1
    )" || return 1

    [[ "$_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$_hash"
  }

  _compute_fixture_hash_fallback() {
    local _fallback_file_list=""
    local _fallback_hash=""

    # Deterministic fallback: sorted file list, content-addressed.
    # Broad scope: includes all files that fixture tests may depend on —
    #   plans/ (all file types: .sh, .json, .txt, .md), specs/, SKILLS/,
    #   tools/, scripts/. This prevents stale cache when non-code config
    #   files (allowlists, evidence sources, workflow contract, etc.) change.
    _fallback_file_list="$(
      {
      [[ -d plans ]] && find plans -maxdepth 1 -type f 2>/dev/null
      [[ -d plans/lib ]] && find plans/lib -name '*.sh' -type f 2>/dev/null
      [[ -d plans/tests ]] && find plans/tests -name '*.sh' -type f 2>/dev/null
      [[ -d plans/config ]] && find plans/config -type f 2>/dev/null
      [[ -d specs ]] && find specs -type f 2>/dev/null
      [[ -d SKILLS ]] && find SKILLS -type f 2>/dev/null
      [[ -d tools ]] && find tools -name '*.py' -type f 2>/dev/null
      [[ -d scripts ]] && find scripts -name '*.py' -type f 2>/dev/null
      } | LC_ALL=C sort -u | sed '/^[[:space:]]*$/d'
    )" || return 1
    [[ -n "$_fallback_file_list" ]] || return 1

    _fallback_hash="$(
      printf '%s\n' "$_fallback_file_list" \
        | xargs shasum -a 256 2>/dev/null \
        | shasum -a 256 \
        | cut -d' ' -f1
    )" || return 1
    [[ "$_fallback_hash" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s\n' "$_fallback_hash"
  }

  _compute_fixture_hash() {
    local fast_file_list=""
    local fast_hash=""
    local fallback_hash=""
    local untracked_scoped=""
    PREFLIGHT_COMPUTED_FIXTURE_HASH=""

    if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      if ! git diff --quiet --cached --; then
        preflight_diag_add_reason "dirty_index"
      fi
      if ! git diff --quiet --; then
        preflight_diag_add_reason "dirty_worktree"
      fi
      untracked_scoped="$(git ls-files --others --exclude-standard -- plans specs SKILLS tools scripts 2>/dev/null || true)"
      if [[ -n "$untracked_scoped" ]]; then
        preflight_diag_add_reason "scoped_untracked_files_present"
      fi
      if git diff --quiet --cached -- \
        && git diff --quiet -- \
        && untracked_scoped="$(git ls-files --others --exclude-standard -- plans specs SKILLS tools scripts 2>/dev/null)" \
        && [[ -z "$untracked_scoped" ]]; then
        fast_file_list="$(git ls-files -- plans specs SKILLS tools scripts 2>/dev/null || true)"
        if [[ -n "$fast_file_list" ]]; then
          if fast_hash="$(_compute_fixture_hash_from_list "$fast_file_list")"; then
            if [[ "$fast_hash" =~ ^[0-9a-f]{64}$ ]]; then
              PREFLIGHT_DIAG_HASH_STRATEGY="fast_git_tracked"
              PREFLIGHT_COMPUTED_FIXTURE_HASH="$fast_hash"
              return 0
            fi
          fi
        fi
      else
        PREFLIGHT_DIAG_HASH_STRATEGY="fallback_scan"
      fi
    else
      preflight_diag_add_reason "git_unavailable"
    fi

    # Falling back to full fixture hash scan
    PREFLIGHT_DIAG_HASH_STRATEGY="fallback_scan"
    if fallback_hash="$(_compute_fixture_hash_fallback)"; then
      PREFLIGHT_COMPUTED_FIXTURE_HASH="$fallback_hash"
      return 0
    fi

    PREFLIGHT_COMPUTED_FIXTURE_HASH="$(printf '%s\n' "preflight-fixture-hash-empty" | shasum -a 256 | cut -d' ' -f1)"
    return 0
  }

  # Validate shasum is available (fail-closed: if missing, skip cache entirely)
  if ! command -v shasum >/dev/null 2>&1; then
    preflight_diag_add_reason "missing_shasum"
    PREFLIGHT_NO_CACHE=1
  fi

  if [[ "$PREFLIGHT_NO_CACHE" != "1" ]]; then
    _compute_fixture_hash
    _current_hash="$PREFLIGHT_COMPUTED_FIXTURE_HASH"
    if [[ -f "$_cache_file" ]]; then
      _cached_hash="$(cat "$_cache_file" 2>/dev/null || true)"
      # Guard against degenerate hash (empty or all-zeros from broken shasum)
      if [[ -n "$_current_hash" && ${#_current_hash} -ge 60 && -n "$_cached_hash" && "$_cached_hash" == "$_current_hash" ]]; then
        _cache_hit=1
        pass "Fixture tests (cached, ${#REVIEW_FIXTURE_TESTS[@]} tests)"
      else
        preflight_diag_add_reason "cache_hash_mismatch"
      fi
    else
      preflight_diag_add_reason "cache_file_missing"
    fi
  fi

  if [[ "$PREFLIGHT_NO_CACHE" == "1" ]]; then
    PREFLIGHT_DIAG_CACHE_STATE="disabled"
    if [[ "$PREFLIGHT_DIAG_HASH_STRATEGY" == "not_evaluated" ]]; then
      PREFLIGHT_DIAG_HASH_STRATEGY="skipped"
    fi
  elif [[ "$_cache_hit" == "1" ]]; then
    PREFLIGHT_DIAG_CACHE_STATE="hit"
  else
    PREFLIGHT_DIAG_CACHE_STATE="miss"
  fi

  if [[ "$_cache_hit" == "0" ]]; then
    # Run fixture tests in parallel (up to PREFLIGHT_PARALLEL_JOBS workers).
    # Each test is isolated (own tmpdir) so parallel execution is safe.
    # Results collected via temp files to preserve pass()/fail() counter semantics.
    PREFLIGHT_PARALLEL_JOBS="${PREFLIGHT_PARALLEL_JOBS:-$(detect_parallel_jobs)}"
    if [[ -z "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then
      setup_fail "PREFLIGHT fixture timeout requested (${PREFLIGHT_FIXTURE_TEST_TIMEOUT}s) but timeout command missing (install coreutils timeout or gtimeout)"
    fi
    fixture_results_dir="$(mktemp -d)"
    _preflight_cleanup_dirs+=("$fixture_results_dir")
    fixture_pids=()
    fixture_idx=0
    timeout_ns=$((PREFLIGHT_FIXTURE_TEST_TIMEOUT * 1000000000))

    for fixture_test in "${REVIEW_FIXTURE_TESTS[@]}"; do
      if [[ ! -f "$fixture_test" ]]; then
        echo "MISSING|0|127" > "$fixture_results_dir/$fixture_idx"
        ((fixture_idx++)) || true
        continue
      fi
      # Run in background, write result to index-keyed file.
      # idx captured by value in the subshell fork.
      idx=$fixture_idx
      (
        start_ns="$(now_monotonic_ns)"
        used_timeout=0
        if [[ -n "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then
          used_timeout=1
          if "$_TIMEOUT_BIN" "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" bash "$fixture_test" >/dev/null 2>&1; then
            rc=0
          else
            rc=$?
          fi
        else
          if bash "$fixture_test" >/dev/null 2>&1; then
            rc=0
          else
            rc=$?
          fi
        fi
        end_ns="$(now_monotonic_ns)"
        if [[ "$start_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" -ge "$start_ns" ]]; then
          duration_ns=$((end_ns - start_ns))
        else
          duration_ns=0
        fi
        duration_s=$((duration_ns / 1000000000))
        status="FAIL"
        if [[ "$rc" -eq 0 ]]; then
          status="PASS"
        elif [[ "$used_timeout" -eq 1 ]] && [[ "$rc" -eq 124 || "$rc" -eq 137 ]] \
          && [[ "$duration_ns" -ge "$timeout_ns" ]]; then
          status="TIMEOUT"
        fi
        echo "${status}|${duration_s}|${rc}" > "$fixture_results_dir/$idx"
      ) &
      fixture_pids+=($!)
      ((fixture_idx++)) || true
      # Throttle: wait for a slot if at concurrency limit.
      # wait -n is used when available/allowed; polling remains the fallback.
      if [[ ${#fixture_pids[@]} -ge $PREFLIGHT_PARALLEL_JOBS ]]; then
        wait_for_fixture_slot
      fi
    done

    # Wait for all remaining without letting an individual child rc abort
    # preflight before result-file collection/classification runs.
    wait_for_all_fixture_jobs

    # Collect results in original order (deterministic output, counters in parent shell)
    _fixture_all_passed=1
    fixture_idx=0
    for fixture_test in "${REVIEW_FIXTURE_TESTS[@]}"; do
      result="$(cat "$fixture_results_dir/$fixture_idx" 2>/dev/null || echo "MISSING|0|127")"
      status="${result%%|*}"
      if [[ "$status" == "$result" ]]; then
        duration_s=0
        rc=127
      else
        rest="${result#*|}"
        duration_s="${rest%%|*}"
        rc="${rest##*|}"
      fi
      case "$status" in
        PASS) pass "Fixture test: $(basename "$fixture_test") (${duration_s}s)" ;;
        FAIL)
          fail "Fixture test failed: $fixture_test (rc=$rc, ${duration_s}s; run 'bash $fixture_test' for details)"
          _fixture_all_passed=0
          ;;
        TIMEOUT)
          fail "Fixture test timed out: $fixture_test (${duration_s}s, limit=${PREFLIGHT_FIXTURE_TEST_TIMEOUT}s, rc=$rc)"
          _fixture_all_passed=0
          ;;
        MISSING)
          setup_fail "Missing fixture test: $fixture_test"
          _fixture_all_passed=0
          ;;
      esac
      ((fixture_idx++)) || true
    done

    if [[ "${#SERIAL_REVIEW_FIXTURE_TESTS[@]}" -gt 0 ]]; then
      for fixture_test in "${SERIAL_REVIEW_FIXTURE_TESTS[@]}"; do
        if [[ ! -f "$fixture_test" ]]; then
          setup_fail "Missing fixture test: $fixture_test"
          _fixture_all_passed=0
          continue
        fi

        start_ns="$(now_monotonic_ns)"
        used_timeout=0
        if [[ -n "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then
          used_timeout=1
          if "$_TIMEOUT_BIN" "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" bash "$fixture_test" >/dev/null 2>&1; then
            rc=0
          else
            rc=$?
          fi
        else
          if bash "$fixture_test" >/dev/null 2>&1; then
            rc=0
          else
            rc=$?
          fi
        fi
        end_ns="$(now_monotonic_ns)"
        if [[ "$start_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" =~ ^[0-9]+$ ]] && [[ "$end_ns" -ge "$start_ns" ]]; then
          duration_ns=$((end_ns - start_ns))
        else
          duration_ns=0
        fi
        duration_s=$((duration_ns / 1000000000))
        status="FAIL"
        if [[ "$rc" -eq 0 ]]; then
          status="PASS"
        elif [[ "$used_timeout" -eq 1 ]] && [[ "$rc" -eq 124 || "$rc" -eq 137 ]] \
          && [[ "$duration_ns" -ge "$timeout_ns" ]]; then
          status="TIMEOUT"
        fi

        case "$status" in
          PASS) pass "Fixture test: $(basename "$fixture_test") (${duration_s}s)" ;;
          FAIL)
            fail "Fixture test failed: $fixture_test (rc=$rc, ${duration_s}s; run 'bash $fixture_test' for details)"
            _fixture_all_passed=0
            ;;
          TIMEOUT)
            fail "Fixture test timed out: $fixture_test (${duration_s}s, limit=${PREFLIGHT_FIXTURE_TEST_TIMEOUT}s, rc=$rc)"
            _fixture_all_passed=0
            ;;
        esac
      done
    fi

    # Update cache: write on success, invalidate on failure.
    # Cache write is best-effort — failure must not kill a passing preflight run.
    if [[ "$_fixture_all_passed" == "1" && "$PREFLIGHT_NO_CACHE" != "1" ]]; then
      if mkdir -p "$_cache_dir" 2>/dev/null; then
        if [[ -z "${_current_hash:-}" ]]; then
          _compute_fixture_hash
          _current_hash="$PREFLIGHT_COMPUTED_FIXTURE_HASH"
        fi
        if [[ -n "$_current_hash" && ${#_current_hash} -ge 60 ]]; then
          _tmp_cache="$(mktemp "$_cache_dir/preflight_cache.XXXXXX" 2>/dev/null)" || true
          if [[ -n "${_tmp_cache:-}" ]]; then
            echo "$_current_hash" > "$_tmp_cache"
            mv "$_tmp_cache" "$_cache_file" 2>/dev/null || rm -f "$_tmp_cache" 2>/dev/null
          fi
        fi
      fi
    else
      rm -f "$_cache_file" 2>/dev/null || true
    fi
  fi
fi

fixture_diag_finished_ns="$(now_monotonic_ns)"
if [[ "$fixture_diag_started_ns" =~ ^[0-9]+$ ]] && [[ "$fixture_diag_finished_ns" =~ ^[0-9]+$ ]] \
  && [[ "$fixture_diag_finished_ns" -ge "$fixture_diag_started_ns" ]]; then
  PREFLIGHT_DIAG_FIXTURE_RUNTIME_SECONDS=$(((fixture_diag_finished_ns - fixture_diag_started_ns) / 1000000000))
else
  PREFLIGHT_DIAG_FIXTURE_RUNTIME_SECONDS=0
fi
preflight_diag_emit

# 7. Postmortem check: plans/postmortem_check.sh
POSTMORTEM_CHECK="plans/postmortem_check.sh"
POSTMORTEM_GATE="${POSTMORTEM_GATE:-0}"

# Fork default: postmortem is non-blocking unless explicitly enabled.
if [[ "$POSTMORTEM_GATE" == "0" ]]; then
  warn "POSTMORTEM_GATE=0 (postmortem check skipped)"
elif [[ -x "$POSTMORTEM_CHECK" ]]; then
  # Check if BASE_REF is resolvable
  BASE_REF="${BASE_REF:-origin/main}"
  if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
    if [[ "$STRICT_MODE" == "1" ]]; then
      fail "Cannot verify BASE_REF=$BASE_REF (required in --strict mode)"
    else
      warn "Cannot verify BASE_REF=$BASE_REF (postmortem check skipped)"
    fi
  else
    # Run the postmortem check
    if BASE_REF="$BASE_REF" "$POSTMORTEM_CHECK" >/dev/null 2>&1; then
      pass "Postmortem check"
    else
      fail "Postmortem check failed (run $POSTMORTEM_CHECK for details)"
    fi
  fi
elif [[ -f "$POSTMORTEM_CHECK" ]]; then
  echo "[FAIL] Postmortem check not executable: $POSTMORTEM_CHECK (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing postmortem check: $POSTMORTEM_CHECK (setup error)" >&2
  exit 2
fi

# =============================================================================
# Summary
# =============================================================================

echo ""
echo "preflight: $PASS_COUNT passed, $FAIL_COUNT failed, $WARN_COUNT warnings"

# Determine exit code
if [[ "$SETUP_FAIL_COUNT" -gt 0 ]]; then
  exit 2
fi

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

if [[ "$STRICT_MODE" == "1" && "$WARN_COUNT" -gt 0 ]]; then
  echo "Exiting with failure due to --strict mode" >&2
  exit 1
fi

exit 0
