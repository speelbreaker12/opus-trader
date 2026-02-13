#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/toggle_policy_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local out=""
  set +e
  out="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$out" | grep -Fq "$pattern" || fail "$label missing expected error '$pattern'"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

default_out="$("$SCRIPT")"
printf '%s\n' "$default_out" | grep -Fq "WORKFLOW_SEQUENCE_ENFORCEMENT=warn" || fail "default workflow sequence toggle missing"
printf '%s\n' "$default_out" | grep -Fq "CODEX_STAGE_POLICY=warn" || fail "default codex stage toggle missing"
printf '%s\n' "$default_out" | grep -Fq "CI_REPO_ONLY_ENFORCEMENT=off" || fail "default ci repo-only toggle missing"
printf '%s\n' "$default_out" | grep -Fq "TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=require" || fail "default trusted-context toggle missing"
printf '%s\n' "$default_out" | grep -Fq "PASS: toggle policy wiring" || fail "missing pass banner"

valid_out="$(
  WORKFLOW_SEQUENCE_ENFORCEMENT=block \
  CODEX_STAGE_POLICY=require \
  CI_REPO_ONLY_ENFORCEMENT=on \
  TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=fallback_runtime_fail_closed \
  "$SCRIPT"
)"
printf '%s\n' "$valid_out" | grep -Fq "WORKFLOW_SEQUENCE_ENFORCEMENT=block" || fail "valid workflow sequence toggle missing"
printf '%s\n' "$valid_out" | grep -Fq "CODEX_STAGE_POLICY=require" || fail "valid codex stage toggle missing"
printf '%s\n' "$valid_out" | grep -Fq "CI_REPO_ONLY_ENFORCEMENT=on" || fail "valid ci repo-only toggle missing"
printf '%s\n' "$valid_out" | grep -Fq "TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=fallback_runtime_fail_closed" || fail "valid trusted-context toggle missing"

expect_fail "invalid workflow sequence" "INVALID_WORKFLOW_SEQUENCE_ENFORCEMENT" env WORKFLOW_SEQUENCE_ENFORCEMENT=oops "$SCRIPT"
expect_fail "invalid codex stage" "INVALID_CODEX_STAGE_POLICY" env CODEX_STAGE_POLICY=oops "$SCRIPT"
expect_fail "invalid ci repo only" "INVALID_CI_REPO_ONLY_ENFORCEMENT" env CI_REPO_ONLY_ENFORCEMENT=oops "$SCRIPT"
expect_fail "invalid trusted context policy" "INVALID_TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY" env TRUSTED_CONTEXT_SOURCE_SCOPE_POLICY=oops "$SCRIPT"

echo "PASS: toggle_policy_check"
