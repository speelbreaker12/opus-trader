#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$ROOT/plans/verify_fork.sh"
VERIFY_UTILS="$ROOT/plans/lib/verify_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$VERIFY"; then
    fail "missing expected guardrail token: $needle"
  fi
}

[[ -f "$VERIFY" ]] || fail "missing verify script: $VERIFY"

# Guardrail: status fixture gate names must use deterministic hash-based naming helper.
assert_contains_line 'status_fixture_path_hash()'
assert_contains_line 'status_fixture_gate_name()'
assert_contains_line 'status_fixture_gate_name "$fixture"'
assert_contains_line 'sha256sum >/dev/null 2>&1'
assert_contains_line 'shasum -a 256'
assert_contains_line 'python3 -c '
assert_contains_line 'echo "${hash:0:24}"'

# Guardrail: quick-mode fail_closed_coverage must be non-blocking and explicit about timeout behavior.
assert_contains_line 'run_logged_nonblocking_gate "fail_closed_coverage"'
assert_contains_line 'RUN_LOGGED_SUPPRESS_TIMEOUT_FAIL=1'
assert_contains_line 'RUN_LOGGED_SKIP_FAILED_GATE=1'
assert_contains_line '"${VERIFY_ARTIFACTS_DIR}/${gate_name}.warn"'
assert_contains_line 'run_logged_or_exit "fail_closed_coverage"'

# Guardrail: status reason leak checker must be wired after status fixtures.
assert_contains_line 'log "13b) status reason leak guard"'
assert_contains_line 'run_logged_or_exit "status_reason_leak_guard"'
assert_contains_line 'tools/check_status_reason_string_leaks.py'

# Behavior checks: the helpers must be invocable and deterministic where possible.
extract_fn() {
  local fn_name="$1"
  awk -v fn="$fn_name" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" { in_fn=1 }
    in_fn {
      print
      if ($0 == "}") { in_fn=0 }
    }
  ' "$VERIFY"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
tmp_fns="$tmp_dir/verify_fork_fns.sh"
fn_defs="$(extract_fn status_fixture_path_hash)
$(extract_fn status_fixture_gate_name)
$(extract_fn run_logged_nonblocking_gate)"
printf '%s\n' "$fn_defs" > "$tmp_fns"

ENABLE_TIMEOUTS="${ENABLE_TIMEOUTS:-1}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"
TIMEOUT_WARNED=0
VERIFY_CONSOLE="${VERIFY_CONSOLE:-quiet}"
VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
source "$tmp_fns"
source "$VERIFY_UTILS"

fixture_name_1="tests/fixtures/status/alpha/beta.json"
fixture_name_2="tests/fixtures/status/alpha/beta.json"
gate1="$(status_fixture_gate_name "$fixture_name_1")"
gate2="$(status_fixture_gate_name "$fixture_name_2")"
if [[ "$gate1" != "$gate2" ]]; then
  fail "status fixture gate name generation must be deterministic: $gate1 != $gate2"
fi
if [[ "$gate1" != status_fixture_* ]]; then
  fail "status fixture gate name has unexpected prefix: $gate1"
fi
if [[ "$gate1" == *"/"* || "$gate1" == *".."* ]]; then
  fail "status fixture gate name contains unsafe characters: $gate1"
fi

artifact_dir="$tmp_dir/artifacts"
mkdir -p "$artifact_dir"
VERIFY_ARTIFACTS_DIR="$artifact_dir"
run_logged_nonblocking_gate "status_fixture_test_gate" 1s bash -c "exit 7"
if [[ ! -f "$artifact_dir/status_fixture_test_gate.warn" ]]; then
  fail "run_logged_nonblocking_gate must emit .warn artifact on failure"
fi
if ! grep -Fq "failed in quick mode with rc=7" "$artifact_dir/status_fixture_test_gate.warn"; then
  fail "run_logged_nonblocking_gate .warn artifact content missing"
fi

echo "PASS: verify fork guardrails test"
