#!/usr/bin/env bash
# Fork verification contract runner.
# - Single stable gate entrypoint for quick/full.
# - Contract-first gates always run.
# - No Ralph/workflow acceptance/checkpoint orchestration.

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./plans/verify.sh [quick|full]

Modes:
  quick  Fast iteration checks (default locally)
  full   Story completion checks (default in CI)

Environment:
  VERIFY_RUN_ID=...           Override verify run id (default: UTC timestamp)
  VERIFY_ARTIFACTS_DIR=...    Override artifacts dir (default: artifacts/verify/<run_id>)
  BASE_REF=origin/main        Diff base used for conditional csp_trace --strict
  VERIFY_CONSOLE=auto|quiet|verbose
  VERIFY_LOG_CAPTURE=0|1
USAGE
}

MODE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    quick|full)
      if [[ -n "$MODE" ]]; then
        echo "FAIL: multiple modes provided (already set to '$MODE')" >&2
        exit 2
      fi
      MODE="$1"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "FAIL: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$MODE" ]]; then
  if [[ -n "${CI:-}" ]]; then
    MODE="full"
  else
    MODE="quick"
  fi
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

source "$ROOT/plans/lib/verify_utils.sh"

CONTRACT_COVERAGE_CI_SENTINEL="${CONTRACT_COVERAGE_CI_SENTINEL:-plans/contract_coverage_ci_strict}"
CONTRACT_COVERAGE_STRICT_EFFECTIVE="${CONTRACT_COVERAGE_STRICT:-0}"
if [[ "$CONTRACT_COVERAGE_STRICT_EFFECTIVE" != "1" && -f "$CONTRACT_COVERAGE_CI_SENTINEL" ]]; then
  CONTRACT_COVERAGE_STRICT_EFFECTIVE="1"
fi

VERIFY_CONSOLE="${VERIFY_CONSOLE:-auto}"
case "$VERIFY_CONSOLE" in
  auto)
    if is_ci; then
      VERIFY_CONSOLE="quiet"
    else
      VERIFY_CONSOLE="verbose"
    fi
    ;;
  quiet|verbose) ;;
  *)
    warn "Unknown VERIFY_CONSOLE=$VERIFY_CONSOLE (expected auto|quiet|verbose); defaulting to verbose"
    VERIFY_CONSOLE="verbose"
    ;;
esac

VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
VERIFY_FAIL_TAIL_LINES="${VERIFY_FAIL_TAIL_LINES:-80}"
VERIFY_FAIL_SUMMARY_LINES="${VERIFY_FAIL_SUMMARY_LINES:-20}"
ENABLE_TIMEOUTS="${ENABLE_TIMEOUTS:-1}"
TIMEOUT_WARNED=0

TIMEOUT_BIN=""
if command -v timeout >/dev/null 2>&1; then
  TIMEOUT_BIN="timeout"
elif command -v gtimeout >/dev/null 2>&1; then
  TIMEOUT_BIN="gtimeout"
fi

# Timeout defaults (fork contract)
PREFLIGHT_TIMEOUT="${PREFLIGHT_TIMEOUT:-300s}"
CONTRACT_KERNEL_TIMEOUT="${CONTRACT_KERNEL_TIMEOUT:-30s}"
CONTRACT_COVERAGE_TIMEOUT="${CONTRACT_COVERAGE_TIMEOUT:-2m}"
SPEC_LINT_TIMEOUT="${SPEC_LINT_TIMEOUT:-2m}"
CSP_TRACE_TIMEOUT="${CSP_TRACE_TIMEOUT:-2m}"
STATUS_FIXTURE_TIMEOUT="${STATUS_FIXTURE_TIMEOUT:-30s}"
VENDOR_DOCS_LINT_TIMEOUT="${VENDOR_DOCS_LINT_TIMEOUT:-1m}"
RUST_FMT_TIMEOUT="${RUST_FMT_TIMEOUT:-2m}"
RUST_CLIPPY_TIMEOUT="${RUST_CLIPPY_TIMEOUT:-15m}"
RUST_TEST_TIMEOUT="${RUST_TEST_TIMEOUT:-45m}"
RUFF_TIMEOUT="${RUFF_TIMEOUT:-2m}"
PYTEST_TIMEOUT="${PYTEST_TIMEOUT:-15m}"
MYPY_TIMEOUT="${MYPY_TIMEOUT:-10m}"
NODE_LINT_TIMEOUT="${NODE_LINT_TIMEOUT:-5m}"
NODE_TYPECHECK_TIMEOUT="${NODE_TYPECHECK_TIMEOUT:-10m}"
NODE_TEST_TIMEOUT="${NODE_TEST_TIMEOUT:-10m}"

VERIFY_RUN_ID="${VERIFY_RUN_ID:-$(date +%Y%m%d_%H%M%S)}"
VERIFY_ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-$ROOT/artifacts/verify/$VERIFY_RUN_ID}"
mkdir -p "$VERIFY_ARTIFACTS_DIR"

VERIFY_STARTED_AT="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
VERIFY_BASE_REF="${BASE_REF:-origin/main}"

write_verify_meta() {
  local status="$1"
  local ended_at="$2"
  local failed_gate="$3"
  local head_sha
  local worktree_path

  head_sha="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  worktree_path="$(pwd)"

  cat > "$VERIFY_ARTIFACTS_DIR/verify.meta.json" <<META
{
  "schema_version": 1,
  "tool": "verify_fork.sh",
  "run_id": "$VERIFY_RUN_ID",
  "mode": "$MODE",
  "status": "$status",
  "base_ref": "$VERIFY_BASE_REF",
  "started_at": "$VERIFY_STARTED_AT",
  "ended_at": "$ended_at",
  "worktree": "$worktree_path",
  "head_sha": "$head_sha",
  "failed_gate": "$failed_gate"
}
META
}

on_exit() {
  local rc="${1:-0}"
  local ended_at
  local status="ok"
  local failed_gate=""

  trap - EXIT

  if [[ "$rc" -ne 0 ]]; then
    status="failed"
  fi

  if [[ -f "$VERIFY_ARTIFACTS_DIR/FAILED_GATE" ]]; then
    failed_gate="$(cat "$VERIFY_ARTIFACTS_DIR/FAILED_GATE")"
  fi

  ended_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  write_verify_meta "$status" "$ended_at" "$failed_gate"

  exit "$rc"
}
trap 'on_exit $?' EXIT

should_enable_csp_strict() {
  local base_ref="$1"
  local changed=""

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  if git rev-parse --verify "$base_ref" >/dev/null 2>&1; then
    changed="$(
      {
        git diff --name-only "$base_ref"...HEAD 2>/dev/null || true
        git diff --name-only --cached 2>/dev/null || true
        git diff --name-only 2>/dev/null || true
      } | sed '/^$/d' | sort -u
    )"
  else
    changed="$(
      {
        git diff --name-only --cached 2>/dev/null || true
        git diff --name-only 2>/dev/null || true
      } | sed '/^$/d' | sort -u
    )"
  fi

  if [[ -z "$changed" ]]; then
    return 1
  fi

  if echo "$changed" | grep -Eq '(^|/)specs/CONTRACT\.md$|(^|/)specs/TRACE\.yaml$'; then
    return 0
  fi

  return 1
}

detect_node_pm() {
  NODE_PM=""
  if [[ -f pnpm-lock.yaml ]]; then
    NODE_PM="pnpm"
  elif [[ -f package-lock.json ]]; then
    NODE_PM="npm"
  elif [[ -f yarn.lock ]]; then
    NODE_PM="yarn"
  fi
  export NODE_PM
}

log "0) Verify context"
echo "mode=$MODE"
echo "root=$ROOT"
echo "verify_run_id=$VERIFY_RUN_ID"
echo "artifacts_dir=$VERIFY_ARTIFACTS_DIR"
echo "base_ref=$VERIFY_BASE_REF"

if command -v git >/dev/null 2>&1; then
  dirty_status="$(git status --porcelain 2>/dev/null || true)"
  if [[ -n "$dirty_status" ]]; then
    warn "Working tree is dirty"
  fi
fi

ensure_python

log "01) preflight"
run_logged_or_exit "preflight" "$PREFLIGHT_TIMEOUT" env POSTMORTEM_GATE=0 ./plans/preflight.sh

log "01b) verify gate contract"
run_logged_or_exit "verify_gate_contract" "$PREFLIGHT_TIMEOUT" ./plans/verify_gate_contract_check.sh

if [[ -f "docs/contract_kernel.json" ]]; then
  log "02) contract kernel"
  run_logged_or_exit "contract_kernel" "$CONTRACT_KERNEL_TIMEOUT" \
    "$PYTHON_BIN" scripts/check_contract_kernel.py --kernel docs/contract_kernel.json
fi

if [[ "$MODE" == "full" ]]; then
  log "03) contract coverage"
  if [[ "$CONTRACT_COVERAGE_STRICT_EFFECTIVE" == "1" ]]; then
    echo "contract_coverage_strict=1 (sentinel/env enabled)"
  else
    echo "contract_coverage_strict=0"
  fi
  run_logged_or_exit "contract_coverage" "$CONTRACT_COVERAGE_TIMEOUT" \
    env CONTRACT_COVERAGE_STRICT="$CONTRACT_COVERAGE_STRICT_EFFECTIVE" \
    "$PYTHON_BIN" plans/contract_coverage_matrix.py
else
  warn "Skipping contract_coverage in quick mode (full-only gate)"
fi

log "04) contract crossrefs"
run_logged_or_exit "contract_crossrefs" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_contract_crossrefs.py --contract specs/CONTRACT.md --check-at --strict --include-bare-section-refs

log "05) arch flows"
run_logged_or_exit "arch_flows" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_arch_flows.py --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml --strict

log "06) state machines"
run_logged_or_exit "state_machines" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_state_machines.py --dir specs/state_machines --contract specs/CONTRACT.md --flows specs/flows/ARCH_FLOWS.yaml --invariants specs/invariants/GLOBAL_INVARIANTS.md --strict

log "07) global invariants"
run_logged_or_exit "global_invariants" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_global_invariants.py --file specs/invariants/GLOBAL_INVARIANTS.md --contract specs/CONTRACT.md

log "08) time freshness"
run_logged_or_exit "time_freshness" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_time_freshness.py --contract specs/CONTRACT.md --spec specs/flows/TIME_FRESHNESS.yaml --strict

log "09) crash matrix"
run_logged_or_exit "crash_matrix" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_crash_matrix.py --contract specs/CONTRACT.md --matrix specs/flows/CRASH_MATRIX.md

log "10) crash replay idempotency"
run_logged_or_exit "crash_replay_idempotency" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_crash_replay_idempotency.py --contract specs/CONTRACT.md --spec specs/flows/CRASH_REPLAY_IDEMPOTENCY.yaml --strict

log "11) reconciliation matrix"
run_logged_or_exit "reconciliation_matrix" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" scripts/check_reconciliation_matrix.py --contract specs/CONTRACT.md --matrix specs/flows/RECONCILIATION_MATRIX.md --strict

log "12) csp trace"
if should_enable_csp_strict "$VERIFY_BASE_REF"; then
  run_logged_or_exit "csp_trace" "$CSP_TRACE_TIMEOUT" \
    "$PYTHON_BIN" scripts/check_csp_trace.py --contract specs/CONTRACT.md --trace specs/TRACE.yaml --strict
else
  run_logged_or_exit "csp_trace" "$CSP_TRACE_TIMEOUT" \
    "$PYTHON_BIN" scripts/check_csp_trace.py --contract specs/CONTRACT.md --trace specs/TRACE.yaml
fi

if [[ -d tests/fixtures/status ]]; then
  log "13) status fixtures"
  fixture_count=0
  while IFS= read -r fixture; do
    [[ -f "$fixture" ]] || continue
    rel="${fixture#tests/fixtures/status/}"
    gate="status_fixture_${rel%.json}"
    gate="$(echo "$gate" | sed 's#[/.-]#_#g; s/[^A-Za-z0-9_]/_/g')"

    run_logged_or_exit "$gate" "$STATUS_FIXTURE_TIMEOUT" \
      "$PYTHON_BIN" tools/validate_status.py --file "$fixture" --strict

    fixture_count=$((fixture_count + 1))
  done < <(find tests/fixtures/status -type f -name '*.json' | LC_ALL=C sort)

  echo "validated_status_fixtures=$fixture_count"
else
  warn "status fixtures directory missing: tests/fixtures/status"
fi

if [[ -f Cargo.toml ]]; then
  if [[ -f specs/vendor_docs/rust/CRATES_OF_INTEREST.yaml && -f tools/vendor_docs_lint_rust.py ]]; then
    log "14) vendor docs lint"
    run_logged_or_exit "vendor_docs_lint" "$VENDOR_DOCS_LINT_TIMEOUT" \
      "$PYTHON_BIN" tools/vendor_docs_lint_rust.py
  else
    warn "vendor docs lint skipped (missing tools/vendor_docs_lint_rust.py or specs/vendor_docs/rust/CRATES_OF_INTEREST.yaml)"
  fi
fi

log "14b) phase0 meta-test"
run_logged_or_exit "phase0_meta_test" "$SPEC_LINT_TIMEOUT" \
  "$PYTHON_BIN" tools/phase0_meta_test.py --root "$ROOT"

export ROOT MODE VERIFY_ARTIFACTS_DIR VERIFY_CONSOLE VERIFY_LOG_CAPTURE
export TIMEOUT_BIN ENABLE_TIMEOUTS VERIFY_FAIL_TAIL_LINES VERIFY_FAIL_SUMMARY_LINES TIMEOUT_WARNED
export RUST_FMT_TIMEOUT RUST_CLIPPY_TIMEOUT RUST_TEST_TIMEOUT
export RUFF_TIMEOUT PYTEST_TIMEOUT MYPY_TIMEOUT
export NODE_LINT_TIMEOUT NODE_TYPECHECK_TIMEOUT NODE_TEST_TIMEOUT

if [[ -f Cargo.toml ]]; then
  log "15) rust gates"
  bash "$ROOT/plans/lib/rust_gates.sh"
fi

if [[ -f pyproject.toml || -f requirements.txt ]]; then
  log "16) python gates"
  bash "$ROOT/plans/lib/python_gates.sh"
fi

if [[ -f package.json ]]; then
  detect_node_pm
  log "17) node gates"
  bash "$ROOT/plans/lib/node_gates.sh"
fi

if [[ "$MODE" == "full" ]]; then
  log "18) slice completion enforcement"
  run_logged_or_exit "slice_completion_enforce" "$SPEC_LINT_TIMEOUT" \
    ./plans/slice_completion_enforce.sh --head "$(git rev-parse HEAD)"
fi

log "Timing Summary"
for f in "$VERIFY_ARTIFACTS_DIR"/*.time; do
  [[ -f "$f" ]] || continue
  name="$(basename "$f" .time)"
  elapsed="$(cat "$f")"
  echo "  $name: ${elapsed}s"
done

log "VERIFY OK (mode=$MODE)"
