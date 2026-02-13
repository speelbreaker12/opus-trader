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
#   PREFLIGHT_FIXTURE_MODE=smoke|full|quick
#     smoke/quick: fast fixture subset (default)
#     full: full fixture matrix (used by verify full)
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
  smoke|full) ;;
  *)
    echo "[FAIL] Invalid PREFLIGHT_FIXTURE_MODE='$PREFLIGHT_FIXTURE_MODE' (expected smoke|full|quick)" >&2
    exit 2
    ;;
esac

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

# 3b. Legacy workflow/docs layout guard (fail-closed)
LEGACY_LAYOUT_GUARD="plans/legacy_layout_guard.sh"
if [[ -x "$LEGACY_LAYOUT_GUARD" ]]; then
  if "$LEGACY_LAYOUT_GUARD"; then
    pass "Legacy layout guard"
  else
    fail "Legacy layout guard failed"
  fi
elif [[ -f "$LEGACY_LAYOUT_GUARD" ]]; then
  echo "[FAIL] Legacy layout guard not executable: $LEGACY_LAYOUT_GUARD (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing legacy layout guard: $LEGACY_LAYOUT_GUARD (setup error)" >&2
  exit 2
fi

# 3c. README/CI parity guard (fail-closed)
README_CI_PARITY_GUARD="plans/readme_ci_parity_check.sh"
if [[ -x "$README_CI_PARITY_GUARD" ]]; then
  if "$README_CI_PARITY_GUARD"; then
    pass "README/CI parity guard"
  else
    fail "README/CI parity guard failed"
  fi
elif [[ -f "$README_CI_PARITY_GUARD" ]]; then
  echo "[FAIL] README/CI parity guard not executable: $README_CI_PARITY_GUARD (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing README/CI parity guard: $README_CI_PARITY_GUARD (setup error)" >&2
  exit 2
fi

# 3d. Slice completion review guard (fail-closed)
SLICE_COMPLETION_REVIEW_GUARD="plans/slice_completion_review_guard.sh"
if [[ -x "$SLICE_COMPLETION_REVIEW_GUARD" ]]; then
  if "$SLICE_COMPLETION_REVIEW_GUARD"; then
    pass "Slice completion review guard"
  else
    fail "Slice completion review guard failed"
  fi
elif [[ -f "$SLICE_COMPLETION_REVIEW_GUARD" ]]; then
  echo "[FAIL] Slice completion review guard not executable: $SLICE_COMPLETION_REVIEW_GUARD (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing slice completion review guard: $SLICE_COMPLETION_REVIEW_GUARD (setup error)" >&2
  exit 2
fi

# 3e. Story findings-review guard (fail-closed)
STORY_REVIEW_FINDINGS_GUARD="plans/story_review_findings_guard.sh"
if [[ -x "$STORY_REVIEW_FINDINGS_GUARD" ]]; then
  if "$STORY_REVIEW_FINDINGS_GUARD"; then
    pass "Story findings-review guard"
  else
    fail "Story findings-review guard failed"
  fi
elif [[ -f "$STORY_REVIEW_FINDINGS_GUARD" ]]; then
  echo "[FAIL] Story findings-review guard not executable: $STORY_REVIEW_FINDINGS_GUARD (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing story findings-review guard: $STORY_REVIEW_FINDINGS_GUARD (setup error)" >&2
  exit 2
fi

# 3f. stoic-cli critical invariants guard (fail-closed)
STOIC_CLI_INVARIANT_GUARD="plans/stoic_cli_invariant_check.sh"
if [[ -x "$STOIC_CLI_INVARIANT_GUARD" ]]; then
  if "$STOIC_CLI_INVARIANT_GUARD"; then
    pass "stoic-cli invariants guard"
  else
    fail "stoic-cli invariants guard failed"
  fi
elif [[ -f "$STOIC_CLI_INVARIANT_GUARD" ]]; then
  echo "[FAIL] stoic-cli invariants guard not executable: $STOIC_CLI_INVARIANT_GUARD (setup error)" >&2
  exit 2
else
  echo "[FAIL] Missing stoic-cli invariants guard: $STOIC_CLI_INVARIANT_GUARD (setup error)" >&2
  exit 2
fi

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
  "plans/tests/test_kimi_review_logged.sh"
  "plans/tests/test_code_review_expert_logged.sh"
  "plans/tests/test_thinking_review_logged.sh"
  "plans/tests/test_slice_review_gate.sh"
  "plans/tests/test_guard_no_command_substitution.sh"
  "plans/tests/test_story_review_findings_guard.sh"
  "plans/tests/test_preflight_fixture_profiles.sh"
  "plans/tests/test_stoic_cli_invariant_check.sh"
)

FULL_ONLY_REVIEW_FIXTURE_TESTS=(
  "plans/tests/test_story_review_gate.sh"
  "plans/tests/test_codex_review_digest.sh"
  "plans/tests/test_run_prd_auditor_timeout_fallback.sh"
  "plans/tests/test_audit_parallel_empty_cache_arrays.sh"
  "plans/tests/test_slice_completion_review_guard.sh"
  "plans/tests/test_slice_completion_enforce.sh"
  "plans/tests/test_pr_gate.sh"
  "plans/tests/test_pre_pr_review_gate.sh"
)

REVIEW_FIXTURE_TESTS=("${SMOKE_REVIEW_FIXTURE_TESTS[@]}")
if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then
  REVIEW_FIXTURE_TESTS+=("${FULL_ONLY_REVIEW_FIXTURE_TESTS[@]}")
fi

pass "Fixture profile: $PREFLIGHT_FIXTURE_MODE (${#REVIEW_FIXTURE_TESTS[@]} tests)"

for fixture_test in "${REVIEW_FIXTURE_TESTS[@]}"; do
  if [[ -f "$fixture_test" ]]; then
    if bash "$fixture_test" >/dev/null 2>&1; then
      pass "Fixture test: $(basename "$fixture_test")"
    else
      fail "Fixture test failed: $fixture_test (run 'bash $fixture_test' for details)"
    fi
  else
    setup_fail "Missing fixture test: $fixture_test"
  fi
done

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
