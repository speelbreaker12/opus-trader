#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERIFY="$ROOT/plans/verify_fork.sh"
VERIFY_ENV="$ROOT/plans/lib/verify_env.sh"
RUST_GATES="$ROOT/plans/lib/rust_gates.sh"
WORKFLOW_VERIFY="$ROOT/plans/workflow_verify.sh"
WORKFLOW_ALLOWLIST="$ROOT/plans/workflow_files_allowlist.txt"
VERIFY_UTILS="$ROOT/plans/lib/verify_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    fail "missing expected token in ${file##*/}: $needle"
  fi
}

extract_fn() {
  local file="$1"
  local fn_name="$2"
  awk -v fn="$fn_name" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" { in_fn=1 }
    in_fn {
      print
      if ($0 == "}") { in_fn=0 }
    }
  ' "$file"
}

[[ -f "$VERIFY" ]] || fail "missing verify script: $VERIFY"
[[ -f "$VERIFY_ENV" ]] || fail "missing verify env script: $VERIFY_ENV"
[[ -f "$RUST_GATES" ]] || fail "missing rust gates script: $RUST_GATES"
[[ -f "$WORKFLOW_VERIFY" ]] || fail "missing workflow verify script: $WORKFLOW_VERIFY"
[[ -f "$WORKFLOW_ALLOWLIST" ]] || fail "missing workflow allowlist: $WORKFLOW_ALLOWLIST"

assert_contains "$VERIFY" 'source "$ROOT/plans/lib/verify_env.sh"'
assert_contains "$VERIFY" 'init_verify_env "verify"'
assert_contains "$VERIFY" 'source "$ROOT/plans/lib/rust_gates.sh"'
assert_contains "$VERIFY" 'run_rust_gates'

assert_contains "$VERIFY_ENV" 'init_verify_env()'
assert_contains "$VERIFY_ENV" 'init_verify_run_context()'

assert_contains "$RUST_GATES" 'run_rust_fmt_gate()'
assert_contains "$RUST_GATES" 'run_rust_clippy_gate()'
assert_contains "$RUST_GATES" 'run_rust_tests_gate()'
assert_contains "$RUST_GATES" 'run_rust_smoke_and_facade_lints_gate()'
assert_contains "$RUST_GATES" 'run_rust_gates()'
assert_contains "$RUST_GATES" 'VERIFY_USE_SCCACHE="${VERIFY_USE_SCCACHE:-0}"'
assert_contains "$RUST_GATES" 'VERIFY_TEST_RUNNER="${VERIFY_TEST_RUNNER:-cargo}"'
assert_contains "$RUST_GATES" 'VERIFY_USE_SCCACHE=1 requires sccache'
assert_contains "$RUST_GATES" 'RUSTC_WRAPPER'
assert_contains "$RUST_GATES" 'rust_runner.meta.json'
assert_contains "$RUST_GATES" 'VERIFY_TEST_RUNNER=nextest requires cargo-nextest'
assert_contains "$RUST_GATES" 'command -v cargo-nextest'
assert_contains "$RUST_GATES" 'cargo nextest run'
assert_contains "$RUST_GATES" 'rust_test_runner_fallbacks.log'
assert_contains "$RUST_GATES" 'smoke_suite_requires_cargo_test'

assert_contains "$WORKFLOW_VERIFY" 'check_script "plans/lib/verify_env.sh"'
assert_contains "$WORKFLOW_ALLOWLIST" 'plans/lib/verify_env.sh'

assert_contains "$VERIFY" 'run_logged_nonblocking_gate()'
assert_contains "$VERIFY" 'RUN_LOGGED_SUPPRESS_EXCERPT=1'
assert_contains "$VERIFY" 'if [[ "$rc" == "1" ]]; then'
assert_contains "$VERIFY" 'return "$rc"'

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fn_defs="$(extract_fn "$VERIFY" run_logged_nonblocking_gate)"
parallel_fn_defs="$(
  extract_fn "$VERIFY" parallel_group_reset
  extract_fn "$VERIFY" parallel_wait_oldest
  extract_fn "$VERIFY" start_parallel_gate
  extract_fn "$VERIFY" finish_parallel_group_or_exit
)"

[[ -n "$fn_defs" ]] || fail "failed to extract accelerator helper functions"
[[ -n "$parallel_fn_defs" ]] || fail "failed to extract parallel helper functions"

tmp_fns="$tmp_dir/fns.sh"
printf '%s\n' "$fn_defs" > "$tmp_fns"
tmp_parallel_fns="$tmp_dir/parallel_fns.sh"
printf '%s\n' "$parallel_fn_defs" > "$tmp_parallel_fns"

ENABLE_TIMEOUTS=0
TIMEOUT_BIN="${TIMEOUT_BIN:-}"
TIMEOUT_WARNED=0
VERIFY_CONSOLE="${VERIFY_CONSOLE:-quiet}"
VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
source "$VERIFY_UTILS"
source "$tmp_fns"
source "$tmp_parallel_fns"

run_nonblocking_case() {
  local case_name="$1"
  local expected_wrapper_rc="$2"
  local expected_gate_rc="$3"
  local expected_warn="$4"
  shift 4

  local case_dir="$tmp_dir/${case_name}"
  local VERIFY_ARTIFACTS_DIR="$case_dir"
  local actual_wrapper_rc
  local actual_gate_rc
  local stdout_file="$case_dir/${case_name}.stdout"
  local stderr_file="$case_dir/${case_name}.stderr"
  mkdir -p "$case_dir"

  set +e
  run_logged_nonblocking_gate "$case_name" 1s "$@" >"$stdout_file" 2>"$stderr_file"
  actual_wrapper_rc=$?
  set -e

  [[ "$actual_wrapper_rc" == "$expected_wrapper_rc" ]] || fail "${case_name}: expected wrapper rc $expected_wrapper_rc, got $actual_wrapper_rc"
  actual_gate_rc="$(cat "$case_dir/${case_name}.rc")"
  [[ "$actual_gate_rc" == "$expected_gate_rc" ]] || fail "${case_name}: expected gate rc $expected_gate_rc, got $actual_gate_rc"

  if [[ "$expected_warn" == "yes" ]]; then
    [[ -f "$case_dir/${case_name}.warn" ]] || fail "${case_name}: expected warn artifact"
    assert_contains "$case_dir/${case_name}.warn" "rc=1"
    [[ ! -f "$case_dir/FAILED_GATE" ]] || fail "${case_name}: soft finding must not mark FAILED_GATE"
  else
    [[ ! -f "$case_dir/${case_name}.warn" ]] || fail "${case_name}: infra failure must not write warn artifact"
    [[ -f "$case_dir/FAILED_GATE" ]] || fail "${case_name}: infra failure must mark FAILED_GATE"
    [[ "$(cat "$case_dir/FAILED_GATE")" == "$case_name" ]] || fail "${case_name}: FAILED_GATE must name the broken gate"
    assert_contains "$stderr_file" "infrastructure failure in quick mode (rc=${expected_gate_rc})"
  fi
}

run_nonblocking_case "soft_finding_gate" 0 1 yes bash -c 'exit 1'
run_nonblocking_case "broken_gate_runner" 2 2 no bash -c 'exit 2'
run_nonblocking_case "timeout_gate" 124 124 no bash -c 'exit 124'

missing_gate="$tmp_dir/missing_gate.sh"
run_nonblocking_case "missing_gate_runner" 127 127 no "$missing_gate"

non_exec_gate="$tmp_dir/non_exec_gate.sh"
printf '#!/usr/bin/env bash\nexit 0\n' > "$non_exec_gate"
chmod 0644 "$non_exec_gate"
run_nonblocking_case "non_exec_gate_runner" 126 126 no "$non_exec_gate"

run_nonblocking_case "killed_gate_runner" 137 137 no bash -c 'exit 137'

parallel_case_dir="$tmp_dir/parallel"
mkdir -p "$parallel_case_dir"
parallel_stdout="$parallel_case_dir/parallel.stdout"
parallel_stderr="$parallel_case_dir/parallel.stderr"
parallel_script="$parallel_case_dir/run_parallel_case.sh"
cat > "$parallel_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ENABLE_TIMEOUTS=0
TIMEOUT_BIN=""
TIMEOUT_WARNED=0
VERIFY_CONSOLE=quiet
VERIFY_LOG_CAPTURE=1
VERIFY_FAIL_TAIL_LINES=80
VERIFY_FAIL_SUMMARY_LINES=20
VERIFY_ARTIFACTS_DIR="$parallel_case_dir"
VERIFY_PARALLEL_JOBS=2
source "$VERIFY_UTILS"
source "$tmp_parallel_fns"
PARALLEL_GATE_NAMES=()
PARALLEL_GATE_TIMEOUTS=()
PARALLEL_ACTIVE_PIDS=()
PARALLEL_GATE_WAIT_RCS=()
PARALLEL_WAIT_NEXT_INDEX=0
parallel_group_reset
start_parallel_gate "parallel_primary_crash" 30s bash -c 'sleep 30'
sleep 0.2
kill -9 "\${PARALLEL_ACTIVE_PIDS[0]}"
start_parallel_gate "parallel_secondary_failure" 1s bash -c 'exit 9'
finish_parallel_group_or_exit
EOF
chmod +x "$parallel_script"
set +e
bash "$parallel_script" >"$parallel_stdout" 2>"$parallel_stderr"
parallel_rc=$?
set -e

[[ "$parallel_rc" == "137" ]] || fail "parallel diagnostics must preserve crash wait rc 137, got $parallel_rc"
[[ "$(cat "$parallel_case_dir/FAILED_GATE")" == "parallel_primary_crash" ]] \
  || fail "parallel diagnostics must record the crashed gate as FAILED_GATE"
assert_contains "$parallel_case_dir/parallel_failures.summary.log" 'parallel_primary_crash rc=137 source=wait_status_missing_rc'
assert_contains "$parallel_case_dir/parallel_failures.summary.log" 'parallel_secondary_failure rc=9 source=rc_artifact'
assert_contains "$parallel_stderr" 'secondary parallel failures:'

runtime_case_dir="$tmp_dir/rust_runtime"
mkdir -p "$runtime_case_dir"
runtime_script="$runtime_case_dir/run_rust_runtime_case.sh"
cat > "$runtime_script" <<EOF
#!/usr/bin/env bash
set -euo pipefail
ROOT="$ROOT"
MODE=quick
VERIFY_ARTIFACTS_DIR="$runtime_case_dir"
source "$RUST_GATES"
ensure_rust_runner_config
EOF
chmod +x "$runtime_script"
bash "$runtime_script"
assert_contains "$runtime_case_dir/rust_runner.meta.json" '"fallbacks": []'

direct_case_root="$tmp_dir/rust_direct_entry_root"
mkdir -p "$direct_case_root/plans/lib" "$direct_case_root/plans" "$direct_case_root/bin"
cp "$RUST_GATES" "$direct_case_root/plans/lib/rust_gates.sh"
cp "$VERIFY_UTILS" "$direct_case_root/plans/lib/verify_utils.sh"
cp "$VERIFY_ENV" "$direct_case_root/plans/lib/verify_env.sh"
for stub in \
  lint_execution_facade.sh \
  lint_risk_facade.sh \
  lint_venue_facade.sh \
  lint_soldier_infra_facade.sh
do
  cat > "$direct_case_root/plans/$stub" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$direct_case_root/plans/$stub"
done
cat > "$direct_case_root/bin/cargo" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$direct_case_root/cargo.log"
exit 0
EOF
chmod +x "$direct_case_root/bin/cargo"
direct_stdout="$tmp_dir/rust_direct_entry.stdout"
direct_stderr="$tmp_dir/rust_direct_entry.stderr"
set +e
ROOT="$direct_case_root" \
PATH="$direct_case_root/bin:$PATH" \
VERIFY_RUN_ID=direct_entry_case \
VERIFY_CONSOLE=quiet \
ENABLE_TIMEOUTS=0 \
bash "$direct_case_root/plans/lib/rust_gates.sh" >"$direct_stdout" 2>"$direct_stderr"
direct_rc=$?
set -e
[[ "$direct_rc" == "0" ]] || fail "direct rust_gates execution must bootstrap verify env, got rc=$direct_rc"
assert_contains "$direct_case_root/artifacts/verify/direct_entry_case/rust_runner.meta.json" '"effective": "cargo"'
assert_contains "$direct_case_root/cargo.log" 'fmt --all -- --check'

echo "PASS: verify accelerators"
