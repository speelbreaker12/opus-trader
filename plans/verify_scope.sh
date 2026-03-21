#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/verify_scope.sh contract
  ./plans/verify_scope.sh workflow
  ./plans/verify_scope.sh rust clippy
  ./plans/verify_scope.sh rust tests

Local-only iteration tool. This is not authoritative verify evidence.
Scoped runs default to artifacts/verify_scope/<run_id>.
USAGE
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODE="${MODE:-quick}"
VERIFY_SCOPE_SLICE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    contract|workflow)
      if [[ -n "$VERIFY_SCOPE_SLICE" ]]; then
        echo "FAIL: scope already selected: $VERIFY_SCOPE_SLICE" >&2
        exit 2
      fi
      VERIFY_SCOPE_SLICE="$1"
      shift
      ;;
    rust)
      if [[ -n "$VERIFY_SCOPE_SLICE" ]]; then
        echo "FAIL: scope already selected: $VERIFY_SCOPE_SLICE" >&2
        exit 2
      fi
      [[ $# -ge 2 ]] || {
        echo "FAIL: rust scope requires a subcommand (clippy|tests)" >&2
        usage >&2
        exit 2
      }
      case "$2" in
        clippy)
          VERIFY_SCOPE_SLICE="rust.clippy"
          ;;
        tests)
          VERIFY_SCOPE_SLICE="rust.tests"
          ;;
        *)
          echo "FAIL: unknown rust scope: $2" >&2
          usage >&2
          exit 2
          ;;
      esac
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "FAIL: unknown scope: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$VERIFY_SCOPE_SLICE" ]]; then
  usage >&2
  exit 2
fi

source "$ROOT/plans/lib/verify_env.sh"
init_verify_env "verify_scope"
source "$ROOT/plans/lib/verify_scope_gates.sh"
source "$ROOT/plans/lib/rust_gates.sh"

verify_scope_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

write_verify_scope_meta() {
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
  "tool": "verify_scope.sh",
  "run_id": "$(verify_scope_json_escape "$VERIFY_RUN_ID")",
  "mode": "scope",
  "status": "$(verify_scope_json_escape "$status")",
  "base_ref": "$(verify_scope_json_escape "$VERIFY_BASE_REF")",
  "started_at": "$(verify_scope_json_escape "$VERIFY_STARTED_AT")",
  "ended_at": "$(verify_scope_json_escape "$ended_at")",
  "worktree": "$(verify_scope_json_escape "$worktree_path")",
  "head_sha": "$(verify_scope_json_escape "$head_sha")",
  "failed_gate": "$(verify_scope_json_escape "$failed_gate")",
  "authoritative": false,
  "scope": "$(verify_scope_json_escape "$VERIFY_SCOPE_SLICE")",
  "run_root": "$(verify_scope_json_escape "$VERIFY_RUN_ROOT")"
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
  write_verify_scope_meta "$status" "$ended_at" "$failed_gate"

  exit "$rc"
}
trap 'on_exit $?' EXIT

log "0) Verify scope context"
echo "scope=$VERIFY_SCOPE_SLICE"
echo "mode=$MODE"
echo "root=$ROOT"
echo "verify_run_id=$VERIFY_RUN_ID"
echo "artifacts_dir=$VERIFY_ARTIFACTS_DIR"
echo "authoritative=false"

case "$VERIFY_SCOPE_SLICE" in
  contract)
    run_contract_scope_gates
    ;;
  workflow)
    run_workflow_scope_gates
    ;;
  rust.clippy)
    need cargo
    run_rust_clippy_gate
    ;;
  rust.tests)
    need cargo
    run_rust_tests_gate
    ;;
  *)
    echo "FAIL: unsupported scope: $VERIFY_SCOPE_SLICE" >&2
    exit 2
    ;;
esac

log "VERIFY SCOPE OK ($VERIFY_SCOPE_SLICE)"
