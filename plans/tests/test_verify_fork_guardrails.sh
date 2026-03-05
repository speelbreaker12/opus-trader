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

assert_not_contains_line() {
  local needle="$1"
  if grep -Fq "$needle" "$VERIFY"; then
    fail "unexpected fail-open token present: $needle"
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
assert_contains_line 'detect_status_fixture_hash_backend()'
assert_contains_line 'STATUS_FIXTURE_HASH_BACKEND="$(detect_status_fixture_hash_backend)"'
assert_contains_line 'status_fixture_path_hash()'
assert_contains_line 'status_fixture_gate_name()'
assert_contains_line 'status_fixture_gate_name "$fixture"'
assert_contains_line 'case "$STATUS_FIXTURE_HASH_BACKEND" in'
assert_contains_line 'sha256sum)'
assert_contains_line 'shasum)'
assert_contains_line 'python3)'
assert_contains_line 'python)'
assert_contains_line 'cksum)'
assert_contains_line 'echo "${hash:0:24}"'

# Guardrail: should_enable_csp_strict must cache changed-file set and reuse it.
assert_contains_line 'compute_csp_strict_changed_files()'
assert_contains_line 'CSP_STRICT_CHANGED_FILES_CACHE_READY=0'
assert_contains_line 'if [[ "$CSP_STRICT_CHANGED_FILES_CACHE_READY" == "0" || "$CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF" != "$base_ref" ]]; then'
assert_contains_line 'CSP_STRICT_CHANGED_FILES_CACHE="$(compute_csp_strict_changed_files "$base_ref")"'
assert_contains_line '__CSP_STRICT_STATE__:git_unavailable'
assert_contains_line '__CSP_STRICT_STATE__:no_changes'
assert_contains_line '__CSP_STRICT_STATE__:changes_present'
assert_contains_line 'cache_state_line="${CSP_STRICT_CHANGED_FILES_CACHE%%$'"'"'\n'"'"'*}"'
assert_contains_line '"__CSP_STRICT_STATE__:git_unavailable"|"__CSP_STRICT_STATE__:no_changes"'
assert_contains_line "grep -Eq '(^|/)specs/CONTRACT\\.md$|(^|/)specs/TRACE\\.yaml$' <<< \"\$CSP_STRICT_CHANGED_FILES_CACHE\""

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

# Guardrail: timing/warn summary must use builtins and preserve multiline warn payload.
assert_contains_line 'emit_timing_and_warn_summary()'
assert_contains_line 'name="${f##*/}"'
assert_contains_line 'name="${name%.time}"'
assert_contains_line 'IFS= read -r elapsed < "$f"'
assert_contains_line 'name="${wf##*/}"'
assert_contains_line 'name="${name%.warn}"'
assert_contains_line 'warn_payload="$(<"$wf")"'
assert_contains_line 'warn "$name: $warn_payload"'
assert_line_before 'emit_timing_and_warn_summary()' 'log "VERIFY OK (mode=$MODE)"'

# Guardrail: duplicate LAG-ID check must run in both serial and parallel spec validators.
assert_contains_line 'start_parallel_gate "contract_impl_lag_ids"'
assert_contains_line 'run_logged_or_exit "contract_impl_lag_ids"'
assert_contains_line 'tools/check_lag_ids.py --file docs/CONTRACT_IMPL_LAG.md'
assert_line_before 'run_logged_or_exit "contract_crossrefs"' 'run_logged_or_exit "contract_impl_lag_ids"'
assert_line_before 'run_logged_or_exit "contract_impl_lag_ids"' 'run_logged_or_exit "arch_flows"'

# Guardrail: CONTRACT.md mutations must be protected by contract-change ledger gate.
assert_contains_line 'log "02a) contract change ledger"'
assert_contains_line 'run_logged_or_exit "contract_change_ledger"'
assert_contains_line 'bash "$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md'
assert_contains_line '"$ROOT/plans/check_contract_change_ledger.sh" --base-ref "$VERIFY_BASE_REF" --contract specs/CONTRACT.md'
assert_not_contains_line 'warn "contract_change_ledger skipped (missing plans/check_contract_change_ledger.sh)"'
assert_line_before 'log "02) contract kernel"' 'log "02a) contract change ledger"'
assert_line_before 'log "02a) contract change ledger"' 'log "02b-02e) profile/invariant gates (parallel)"'

# Guardrail: recon prompt invariants must be enforced between gate integrity and doc sync.
assert_contains_line 'log "14cc) recon prompt guard"'
assert_contains_line 'run_logged_or_exit "recon_prompt_guard"'
assert_contains_line 'bash "$ROOT/plans/recon_prompt_guard.sh"'
assert_line_before 'log "14c) gate integrity lint"' 'log "14cc) recon prompt guard"'
assert_contains_line 'log "14cd) recon doc budget"'
assert_contains_line 'run_logged_or_exit "recon_doc_budget"'
assert_contains_line 'bash "$ROOT/plans/recon_doc_budget.sh"'
assert_line_before 'log "14cc) recon prompt guard"' 'log "14cd) recon doc budget"'
assert_line_before 'log "14cd) recon doc budget"' 'log "14d) doc sync check"'

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
fn_defs="$(extract_fn detect_status_fixture_hash_backend)
$(extract_fn status_fixture_path_hash)
$(extract_fn status_fixture_gate_name)
$(extract_fn run_logged_nonblocking_gate)
$(extract_fn compute_csp_strict_changed_files)
$(extract_fn should_enable_csp_strict)
$(extract_fn emit_timing_and_warn_summary)"
printf '%s\n' "$fn_defs" > "$tmp_fns"

ENABLE_TIMEOUTS="${ENABLE_TIMEOUTS:-1}"
TIMEOUT_BIN="${TIMEOUT_BIN:-}"
TIMEOUT_WARNED=0
VERIFY_CONSOLE="${VERIFY_CONSOLE:-quiet}"
VERIFY_LOG_CAPTURE="${VERIFY_LOG_CAPTURE:-1}"
source "$tmp_fns"
source "$VERIFY_UTILS"

STATUS_FIXTURE_HASH_BACKEND="$(detect_status_fixture_hash_backend)"
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

# Runtime check: multiline .warn payload must be preserved in summary output.
echo "5" > "$artifact_dir/gate_alpha.time"
cat > "$artifact_dir/gate_multiline.warn" <<'EOF'
line one
line two
EOF
summary_output="$(VERIFY_ARTIFACTS_DIR="$artifact_dir" emit_timing_and_warn_summary 2>&1)"
if ! printf '%s\n' "$summary_output" | grep -Fq "  gate_alpha: 5s"; then
  fail "timing summary must include integer-seconds output"
fi
if ! printf '%s\n' "$summary_output" | grep -Fq "WARN: gate_multiline: line one"; then
  fail "warn summary first line missing"
fi
if ! printf '%s\n' "$summary_output" | grep -Fq "line two"; then
  fail "warn summary must preserve multiline payload"
fi

# Runtime check: should_enable_csp_strict must cache changed-file set by base ref.
mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
git_call_log="$tmp_dir/git_calls.log"
cat > "$mock_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >> "${VERIFY_FORK_GIT_CALL_LOG:?}"

if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--verify" ]]; then
  exit 0
fi

if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
  if [[ "${3:-}" == "origin/main...HEAD" ]]; then
    printf '%s\n' "specs/CONTRACT.md"
  fi
  exit 0
fi

exit 0
EOF
chmod +x "$mock_bin/git"

(
  export PATH="$mock_bin:$PATH"
  export VERIFY_FORK_GIT_CALL_LOG="$git_call_log"
  CSP_STRICT_CHANGED_FILES_CACHE_READY=0
  CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF=""
  CSP_STRICT_CHANGED_FILES_CACHE=""

  if ! should_enable_csp_strict "origin/main"; then
    fail "should_enable_csp_strict should return true for CONTRACT change"
  fi
  if ! should_enable_csp_strict "origin/main"; then
    fail "should_enable_csp_strict should reuse cache for same base ref"
  fi
)

diff_calls="$(grep -c '^diff --name-only' "$git_call_log" || true)"
if [[ "$diff_calls" != "3" ]]; then
  fail "should_enable_csp_strict should compute changed-file set once per base ref (expected 3 diff calls, got $diff_calls)"
fi

# Runtime check: should_enable_csp_strict differentiates "no changes" from
# "git unavailable" via sentinel cache state.
mock_no_changes_bin="$tmp_dir/mock_no_changes_bin"
mkdir -p "$mock_no_changes_bin"
cat > "$mock_no_changes_bin/git" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--verify" ]]; then
  exit 0
fi

if [[ "${1:-}" == "diff" && "${2:-}" == "--name-only" ]]; then
  exit 0
fi

exit 0
EOF
chmod +x "$mock_no_changes_bin/git"

(
  export PATH="$mock_no_changes_bin:$PATH"
  CSP_STRICT_CHANGED_FILES_CACHE_READY=0
  CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF=""
  CSP_STRICT_CHANGED_FILES_CACHE=""

  if should_enable_csp_strict "origin/main"; then
    fail "should_enable_csp_strict should be false when no files changed"
  fi
  if [[ "$CSP_STRICT_CHANGED_FILES_CACHE" != "__CSP_STRICT_STATE__:no_changes" ]]; then
    fail "no-change sentinel missing from cache"
  fi
)

no_git_path="$tmp_dir/no_git_path"
mkdir -p "$no_git_path"
(
  export PATH="$no_git_path"
  CSP_STRICT_CHANGED_FILES_CACHE_READY=0
  CSP_STRICT_CHANGED_FILES_CACHE_BASE_REF=""
  CSP_STRICT_CHANGED_FILES_CACHE=""

  if should_enable_csp_strict "origin/main"; then
    fail "should_enable_csp_strict should be false when git is unavailable"
  fi
  if [[ "$CSP_STRICT_CHANGED_FILES_CACHE" != "__CSP_STRICT_STATE__:git_unavailable" ]]; then
    fail "git-unavailable sentinel missing from cache"
  fi
)

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
