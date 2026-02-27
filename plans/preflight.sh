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

# 4. Shell syntax: bash -n plans/*.sh
SHELL_SYNTAX_OK=1
SHELL_ERRORS=()
if compgen -G "plans/*.sh" >/dev/null; then
  for f in plans/*.sh; do
    if ! bash -n "$f" 2>/dev/null; then
      SHELL_SYNTAX_OK=0
      SHELL_ERRORS+=("$f")
    fi
  done
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
  "plans/tests/test_codex_review_logged.sh"
  "plans/tests/test_slice_review_gate.sh"
  "plans/tests/test_guard_no_command_substitution.sh"
  "plans/tests/test_story_review_findings_guard.sh"
  "plans/tests/test_fork_attestation_remediation_verify.sh"
  "plans/tests/test_fork_attestation_mirror.sh"
  "plans/tests/test_workflow_quick_step.sh"
  "plans/tests/test_toggle_policy_check.sh"
  "plans/tests/test_preflight_fixture_profiles.sh"
  "plans/tests/test_stoic_cli_invariant_check.sh"
  "plans/tests/test_verify_timeout_policy.sh"
  "plans/tests/test_verify_fork_guardrails.sh"
  "plans/tests/test_contract_profile_parity.sh"
  "plans/tests/test_contract_review_emit.sh"
  "plans/tests/test_recon_bundle.sh"
  "plans/tests/test_recon_precheck.sh"
  "plans/tests/test_recon_scoreboard.sh"
  "plans/tests/test_recon_evidence_ledger.sh"
  "plans/tests/test_premortem_ready_ownership_conflict.sh"
  "plans/tests/test_wf_step_stop_on_blocker.sh"
  "plans/tests/test_wf_step_path_signal_scan.sh"
  "plans/tests/test_code_review_expert_guard.sh"
  "plans/tests/test_roadmap_evidence_audit.sh"
  "plans/tests/test_crossref_invariants.sh"
  "plans/tests/test_crossref_gate.sh"
  "plans/tests/test_artifact_lint.sh"
)

FULL_ONLY_REVIEW_FIXTURE_TESTS=(
  "plans/tests/test_adversarial_gate.sh"
  "plans/tests/test_codex_review_digest.sh"
  "plans/tests/test_run_prd_auditor_timeout_fallback.sh"
  "plans/tests/test_audit_parallel_empty_cache_arrays.sh"
  "plans/tests/test_slice_completion_review_guard.sh"
  "plans/tests/test_slice_completion_enforce.sh"
  "plans/tests/test_prd_set_pass.sh"
  "plans/tests/test_pre_pr_review_gate.sh"
)
# NOTE: test_story_review_gate.sh and test_pr_gate.sh moved to verify_fork.sh
# gate 14g (overlaps with rust compilation for better wall-clock performance).

REVIEW_FIXTURE_TESTS=("${SMOKE_REVIEW_FIXTURE_TESTS[@]}")
if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then
  REVIEW_FIXTURE_TESTS+=("${FULL_ONLY_REVIEW_FIXTURE_TESTS[@]}")
fi

if [[ "$PREFLIGHT_FIXTURE_MODE" == "none" ]]; then
  pass "Fixture tests skipped (mode=none)"
else
  pass "Fixture profile: $PREFLIGHT_FIXTURE_MODE (${#REVIEW_FIXTURE_TESTS[@]} tests)"

  # --- Fixture cache ---
  # Cache key = SHA256 of all workflow/tool/spec files that fixture tests depend on.
  # Broad scope prevents stale cache from missed dependencies.
  PREFLIGHT_NO_CACHE="${PREFLIGHT_NO_CACHE:-0}"
  # --strict implies thoroughness: disable cache to ensure all tests actually run
  if [[ "$STRICT_MODE" == "1" ]]; then
    PREFLIGHT_NO_CACHE=1
  fi
  _cache_dir="$ROOT/.cache"
  _cache_file="$_cache_dir/preflight_fixtures_${PREFLIGHT_FIXTURE_MODE}.hash"
  _cache_hit=0

  _compute_fixture_hash() {
    # Deterministic: sorted file list, content-addressed.
    # Uses xargs to batch shasum calls (avoids per-file process spawn).
    # Broad scope: includes all files that fixture tests may depend on —
    #   plans/ (all file types: .sh, .json, .txt, .md), specs/, SKILLS/,
    #   tools/, scripts/. This prevents stale cache when non-code config
    #   files (allowlists, evidence sources, workflow contract, etc.) change.
    {
      find plans -maxdepth 1 -type f 2>/dev/null
      find plans/lib -name '*.sh' -type f 2>/dev/null
      find plans/tests -name '*.sh' -type f 2>/dev/null
      find plans/config -type f 2>/dev/null
      find specs -type f 2>/dev/null
      find SKILLS -type f 2>/dev/null
      find tools -name '*.py' -type f 2>/dev/null
      find scripts -name '*.py' -type f 2>/dev/null
    } | LC_ALL=C sort -u | xargs shasum -a 256 2>/dev/null | shasum -a 256 | cut -d' ' -f1
  }

  # Validate shasum is available (fail-closed: if missing, skip cache entirely)
  if ! command -v shasum >/dev/null 2>&1; then
    PREFLIGHT_NO_CACHE=1
  fi

  if [[ "$PREFLIGHT_NO_CACHE" != "1" && -f "$_cache_file" ]]; then
    _cached_hash="$(cat "$_cache_file" 2>/dev/null || true)"
    _current_hash="$(_compute_fixture_hash)"
    # Guard against degenerate hash (empty or all-zeros from broken shasum)
    if [[ -n "$_current_hash" && ${#_current_hash} -ge 60 && -n "$_cached_hash" && "$_cached_hash" == "$_current_hash" ]]; then
      _cache_hit=1
      pass "Fixture tests (cached, ${#REVIEW_FIXTURE_TESTS[@]} tests)"
    fi
  fi

  if [[ "$_cache_hit" == "0" ]]; then
    # Run fixture tests in parallel (up to PREFLIGHT_PARALLEL_JOBS workers).
    # Each test is isolated (own tmpdir) so parallel execution is safe.
    # Results collected via temp files to preserve pass()/fail() counter semantics.
    PREFLIGHT_PARALLEL_JOBS="${PREFLIGHT_PARALLEL_JOBS:-8}"
    fixture_results_dir="$(mktemp -d)"
    _preflight_cleanup_dirs+=("$fixture_results_dir")
    fixture_pids=()
    fixture_idx=0

    for fixture_test in "${REVIEW_FIXTURE_TESTS[@]}"; do
      if [[ ! -f "$fixture_test" ]]; then
        echo "MISSING" > "$fixture_results_dir/$fixture_idx"
        ((fixture_idx++)) || true
        continue
      fi
      # Run in background, write result to index-keyed file.
      # idx captured by value in the subshell fork.
      idx=$fixture_idx
      (
        if bash "$fixture_test" >/dev/null 2>&1; then
          echo "PASS" > "$fixture_results_dir/$idx"
        else
          echo "FAIL" > "$fixture_results_dir/$idx"
        fi
      ) &
      fixture_pids+=($!)
      ((fixture_idx++)) || true
      # Throttle: wait for a slot if at concurrency limit
      # Uses kill -0 polling (compatible with bash 3.2 which lacks wait -n)
      if [[ ${#fixture_pids[@]} -ge $PREFLIGHT_PARALLEL_JOBS ]]; then
        # Poll until at least one slot opens
        while true; do
          alive=()
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
          if [[ ${#fixture_pids[@]} -lt $PREFLIGHT_PARALLEL_JOBS ]]; then
            break
          fi
          sleep 0.2
        done
      fi
    done

    # Wait for all remaining
    wait

    # Collect results in original order (deterministic output, counters in parent shell)
    _fixture_all_passed=1
    fixture_idx=0
    for fixture_test in "${REVIEW_FIXTURE_TESTS[@]}"; do
      result="$(cat "$fixture_results_dir/$fixture_idx" 2>/dev/null || echo "MISSING")"
      case "$result" in
        PASS) pass "Fixture test: $(basename "$fixture_test")" ;;
        FAIL)
          fail "Fixture test failed: $fixture_test (run 'bash $fixture_test' for details)"
          _fixture_all_passed=0
          ;;
        MISSING)
          setup_fail "Missing fixture test: $fixture_test"
          _fixture_all_passed=0
          ;;
      esac
      ((fixture_idx++)) || true
    done

    # Update cache: write on success, invalidate on failure.
    # Cache write is best-effort — failure must not kill a passing preflight run.
    if [[ "$_fixture_all_passed" == "1" && "$PREFLIGHT_NO_CACHE" != "1" ]]; then
      if mkdir -p "$_cache_dir" 2>/dev/null; then
        _current_hash="${_current_hash:-$(_compute_fixture_hash)}"
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
