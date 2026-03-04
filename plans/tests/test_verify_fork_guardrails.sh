#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$ROOT/plans/verify_fork.sh"
VERIFY_WRAPPER="$ROOT/plans/verify.sh"
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

line_number_for() {
  local needle="$1"
  local line
  line="$(grep -nF "$needle" "$VERIFY" | head -n1 | cut -d: -f1 || true)"
  [[ -n "$line" ]] || fail "missing expected guardrail token: $needle"
  echo "$line"
}

assert_line_before() {
  local first="$1"
  local second="$2"
  local first_line second_line
  first_line="$(line_number_for "$first")"
  second_line="$(line_number_for "$second")"
  if (( first_line >= second_line )); then
    fail "unexpected guardrail order: '$first' (line $first_line) must appear before '$second' (line $second_line)"
  fi
}

[[ -f "$VERIFY" ]] || fail "missing verify script: $VERIFY"
[[ -f "$VERIFY_WRAPPER" ]] || fail "missing verify wrapper: $VERIFY_WRAPPER"

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
assert_contains_line 'log "12f) status reason codegen"'
assert_contains_line 'run_logged_or_exit "status_reason_codegen"'
assert_line_before 'log "12f) status reason codegen"' 'log "13) status fixtures"'
assert_contains_line 'log "13b) status reason leak guard"'
assert_contains_line 'run_logged_or_exit "status_reason_leak_guard"'
assert_contains_line 'tools/check_status_reason_string_leaks.py'
assert_contains_line 'status_reason_owner_allow_path="crates/soldier_core/src/status_codes_generated.rs"'
assert_contains_line 'status_reason_leak_cmd+=(--allow-path "$status_reason_owner_allow_path")'
assert_line_before 'log "13) status fixtures"' 'log "13b) status reason leak guard"'

# Guardrail: duplicate LAG-ID check must run in both serial and parallel spec validators.
assert_contains_line 'start_parallel_gate "contract_impl_lag_ids"'
assert_contains_line 'run_logged_or_exit "contract_impl_lag_ids"'
assert_contains_line 'tools/check_lag_ids.py --file docs/CONTRACT_IMPL_LAG.md'
assert_line_before 'run_logged_or_exit "contract_crossrefs"' 'run_logged_or_exit "contract_impl_lag_ids"'
assert_line_before 'run_logged_or_exit "contract_impl_lag_ids"' 'run_logged_or_exit "arch_flows"'

# Guardrail: CONTRACT.md mutations must be protected by contract-change ledger gate.
assert_contains_line 'log "02a) contract change ledger"'
assert_contains_line 'run_logged_or_exit "contract_change_ledger"'
assert_contains_line '"$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md'
assert_line_before 'log "02) contract kernel"' 'log "02a) contract change ledger"'
assert_line_before 'log "02a) contract change ledger"' 'log "02b-02e) profile/invariant gates (parallel)"'

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
tmp_verify_wrapper_root="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" "$tmp_verify_wrapper_root"' EXIT
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

# Wrapper-level integration proof: plans/verify.sh must delegate to verify_fork.sh and
# forward the selected mode argument.
mkdir -p "$tmp_verify_wrapper_root/plans"
cp "$VERIFY_WRAPPER" "$tmp_verify_wrapper_root/plans/verify.sh"
cat > "$tmp_verify_wrapper_root/plans/verify_fork.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" > "$VERIFY_WRAPPER_ARGS_FILE"
exit 0
EOF
chmod +x "$tmp_verify_wrapper_root/plans/verify.sh" "$tmp_verify_wrapper_root/plans/verify_fork.sh"

verify_wrapper_args_file="$tmp_verify_wrapper_root/verify_wrapper.args"
VERIFY_WRAPPER_ARGS_FILE="$verify_wrapper_args_file" \
  "$tmp_verify_wrapper_root/plans/verify.sh" quick >/dev/null 2>&1 \
  || fail "verify wrapper fixture invocation failed"
[[ -f "$verify_wrapper_args_file" ]] || fail "verify wrapper did not delegate to verify_fork fixture"
verify_wrapper_args="$(cat "$verify_wrapper_args_file")"
[[ "$verify_wrapper_args" == "quick" ]] \
  || fail "verify wrapper must forward quick mode to verify_fork (got '$verify_wrapper_args')"

echo "PASS: verify fork guardrails test"
