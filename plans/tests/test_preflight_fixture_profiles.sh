#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
PREFLIGHT="$ROOT/plans/preflight.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$PREFLIGHT" ]] || fail "missing preflight script: $PREFLIGHT"

extract_array() {
  local name="$1"
  local source_file="${2:-$PREFLIGHT}"
  awk -v name="$name" '
    $0 ~ "^" name "=\\(" {in_array=1; next}
    in_array && $0 ~ "^\\)" {exit}
    in_array {
      line=$0
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
      if (line ~ /^"[^"]+"$/) {
        gsub(/^"|"$/, "", line)
        print line
      }
    }
  ' "$source_file"
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$PREFLIGHT"; then
    fail "missing expected preflight line: $needle"
  fi
}

assert_file_contains_line() {
  local file="$1"
  local needle="$2"
  if ! grep -Fq "$needle" "$file"; then
    fail "missing expected line in $(basename "$file"): $needle"
  fi
}

assert_text_contains_line() {
  local text="$1"
  local needle="$2"
  if ! grep -Fq "$needle" <<< "$text"; then
    fail "missing expected block line: $needle"
  fi
}

line_number_in_text() {
  local text="$1"
  local needle="$2"
  local line
  line="$(grep -nF "$needle" <<< "$text" | head -n1 | cut -d: -f1 || true)"
  [[ -n "$line" ]] || fail "missing expected block line: $needle"
  echo "$line"
}

assert_text_line_before() {
  local text="$1"
  local first="$2"
  local second="$3"
  local first_line second_line
  first_line="$(line_number_in_text "$text" "$first")"
  second_line="$(line_number_in_text "$text" "$second")"
  if (( first_line >= second_line )); then
    fail "unexpected block order: '$first' (line $first_line) must appear before '$second' (line $second_line)"
  fi
}

assert_list_contains() {
  local list="$1"
  local item="$2"
  if ! printf '%s\n' "$list" | grep -Fxq "$item"; then
    fail "missing expected fixture entry: $item"
  fi
}

assert_list_absent() {
  local list="$1"
  local item="$2"
  if printf '%s\n' "$list" | grep -Fxq "$item"; then
    fail "fixture entry should not be present: $item"
  fi
}

smoke_list="$(extract_array "SMOKE_REVIEW_FIXTURE_TESTS")"
full_only_list="$(extract_array "FULL_ONLY_REVIEW_FIXTURE_TESTS")"
full_only_serial_list="$(extract_array "FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS")"

[[ -n "$smoke_list" ]] || fail "SMOKE_REVIEW_FIXTURE_TESTS is empty"
[[ -n "$full_only_list" ]] || fail "FULL_ONLY_REVIEW_FIXTURE_TESTS is empty"

assert_contains_line 'quick) PREFLIGHT_FIXTURE_MODE="smoke" ;;'
assert_contains_line 'if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then'
assert_contains_line 'pass "Fixture profile: $PREFLIGHT_FIXTURE_MODE (${#REVIEW_FIXTURE_TESTS[@]} tests)"'
assert_contains_line 'fixture_timeout_default=240'
assert_contains_line 'fixture_timeout_default=300'
assert_contains_line 'PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW="${PREFLIGHT_FIXTURE_TEST_TIMEOUT:-$fixture_timeout_default}"'
assert_contains_line 'PREFLIGHT_FIXTURE_TEST_TIMEOUT="$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW"'
assert_contains_line 'if [[ ! "$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW" =~ ^[0-9]+$ ]]; then'
assert_contains_line 'setup_fail "Invalid PREFLIGHT_FIXTURE_TEST_TIMEOUT='"'"'$PREFLIGHT_FIXTURE_TEST_TIMEOUT_RAW'"'"' (expected non-negative integer seconds)"'
assert_contains_line 'supports_wait_n() {'
assert_contains_line 'if builtin help wait >/dev/null 2>&1; then'
assert_contains_line 'wait_help_text="$(builtin help wait 2>/dev/null || true)"'
assert_contains_line "grep -Eq '(^|[[:space:]])-n([[:space:][:punct:]]|$)' <<< \"\$wait_help_text\""
assert_contains_line 'return 0'
assert_contains_line 'PREFLIGHT_WAIT_N_MODE="${PREFLIGHT_WAIT_N_MODE:-auto}"'
assert_contains_line 'case "$PREFLIGHT_WAIT_N_MODE" in'
assert_contains_line 'auto|force_on|force_off) ;;'
assert_contains_line 'setup_fail "Invalid PREFLIGHT_WAIT_N_MODE='"'"'$PREFLIGHT_WAIT_N_MODE'"'"' (expected auto|force_on|force_off)"'
assert_contains_line 'PREFLIGHT_WAIT_N_SUPPORTED=0'
assert_contains_line 'if supports_wait_n; then'
assert_contains_line 'if [[ "$PREFLIGHT_WAIT_N_MODE" == "force_on" ]]; then'
assert_contains_line 'if [[ "$PREFLIGHT_WAIT_N_USE" == "1" ]]; then'
assert_contains_line 'if [[ ${#fixture_pids[@]} -gt 0 ]]; then'
assert_contains_line 'wait -n "${fixture_pids[@]}" 2>/dev/null || true'
assert_contains_line 'if [[ -n "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then'
assert_contains_line 'MONOTONIC_BACKEND="$(select_monotonic_backend)"'
assert_contains_line 'MONOTONIC_BACKEND_INIT_MARKER="monotonic_backend=$MONOTONIC_BACKEND"'
assert_contains_line 'detect_parallel_jobs() {'
assert_contains_line 'cpu_count="$(sysctl -n hw.ncpu 2>/dev/null || true)"'
assert_contains_line 'cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || true)"'
assert_contains_line 'PREFLIGHT_PARALLEL_JOBS_RAW="${PREFLIGHT_PARALLEL_JOBS-}"'
assert_contains_line 'if [[ -z "$PREFLIGHT_PARALLEL_JOBS_RAW" ]]; then'
assert_contains_line 'elif [[ "$PREFLIGHT_PARALLEL_JOBS_RAW" =~ ^[1-9][0-9]*$ ]]; then'
assert_contains_line 'setup_fail "Invalid PREFLIGHT_PARALLEL_JOBS='"'"'$PREFLIGHT_PARALLEL_JOBS_RAW'"'"' (expected positive integer worker count)"'
assert_contains_line 'start_ns="$(now_monotonic_ns)"'
assert_contains_line 'timeout_ns=$((PREFLIGHT_FIXTURE_TEST_TIMEOUT * 1000000000))'
assert_contains_line 'PREFLIGHT_PARALLEL_JOBS="${PREFLIGHT_PARALLEL_JOBS:-$(detect_parallel_jobs)}"'
assert_contains_line 'if [[ -z "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then'
assert_contains_line 'setup_fail "PREFLIGHT fixture timeout requested (${PREFLIGHT_FIXTURE_TEST_TIMEOUT}s) but timeout command missing (install coreutils timeout or gtimeout)"'
assert_contains_line 'echo "${status}|${duration_s}|${rc}" > "$fixture_results_dir/$idx"'
assert_contains_line 'pass "Fixture test: $(basename "$fixture_test") (${duration_s}s)"'
assert_contains_line 'SHELL_SYNTAX_CHECKER=""'
assert_contains_line 'if ! SHELL_SYNTAX_CHECKER="$(command -v bash 2>/dev/null)"; then'
assert_contains_line 'setup_fail "Shell syntax setup failed (missing bash)"'
assert_contains_line 'for f in plans/*.sh; do'
assert_contains_line '# Authoritative check: every plans/*.sh file must parse on its own.'
assert_contains_line 'if "$SHELL_SYNTAX_CHECKER" -n "$f" >/dev/null 2>&1; then'
assert_contains_line '_shell_syntax_rc=$?'
assert_contains_line 'case "$_shell_syntax_rc" in'
assert_contains_line '2)'
assert_contains_line 'setup_fail "Shell syntax setup failed while checking $f (bash -n rc=$_shell_syntax_rc)"'
assert_contains_line 'if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then'
assert_contains_line '&& untracked_scoped="$(git ls-files --others --exclude-standard -- plans specs SKILLS tools scripts 2>/dev/null)" \'
assert_contains_line '&& [[ -z "$untracked_scoped" ]]; then'
assert_contains_line 'git ls-files -- plans specs SKILLS tools scripts'
assert_contains_line '_normalized_list="$(printf '"'"'%s\n'"'"' "$_file_list" | LC_ALL=C sort -u | sed '"'"'/^[[:space:]]*$/d'"'"')" || return 1'
assert_contains_line 'if fast_hash="$(_compute_fixture_hash_from_list "$fast_file_list")"; then'
assert_contains_line 'Falling back to full fixture hash scan'

assert_list_contains "$smoke_list" "plans/tests/test_verify_timeout_policy.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fail_closed_gate_map_paths.sh"
assert_list_contains "$smoke_list" "plans/tests/test_rust_gates_quick_clippy.sh"
assert_list_contains "$smoke_list" "plans/tests/test_rust_gates_smoke_targets.sh"
assert_list_contains "$smoke_list" "plans/tests/test_lint_execution_facade.sh"
assert_list_contains "$smoke_list" "plans/tests/test_lint_risk_facade.sh"
assert_list_contains "$smoke_list" "plans/tests/test_lint_venue_facade.sh"
assert_list_contains "$smoke_list" "plans/tests/test_lint_soldier_infra_facade.sh"
assert_list_contains "$smoke_list" "plans/tests/test_contract_kernel_drift_message.sh"
assert_list_contains "$smoke_list" "plans/tests/test_check_skills_index.sh"
assert_list_contains "$full_only_list" "plans/tests/test_recon_bundle.sh"
assert_list_contains "$full_only_list" "plans/tests/test_recon_scoreboard.sh"
assert_list_absent "$full_only_list" "plans/tests/test_recon_operator_runner.sh"
assert_list_absent "$full_only_list" "plans/tests/test_preflight_fixture_timeout_controls.sh"
assert_list_absent "$full_only_serial_list" "plans/tests/test_prd_set_pass.sh"

# Verify moved tests are actually present in verify_fork.sh gate 14g
VERIFY_FORK="$ROOT/plans/verify_fork.sh"
[[ -f "$VERIFY_FORK" ]] || fail "missing verify_fork.sh: $VERIFY_FORK"
workflow_verify_list="$(extract_array "WORKFLOW_INTEGRATION_TESTS" "$VERIFY_FORK")"
full_mode_workflow_verify_list="$(extract_array "FULL_MODE_WORKFLOW_INTEGRATION_TESTS" "$VERIFY_FORK")"
[[ -n "$workflow_verify_list" ]] || fail "WORKFLOW_INTEGRATION_TESTS is empty"
[[ -n "$full_mode_workflow_verify_list" ]] || fail "FULL_MODE_WORKFLOW_INTEGRATION_TESTS is empty"

assert_list_contains "$full_mode_workflow_verify_list" "plans/tests/test_preflight_fixture_timeout_controls.sh"
assert_list_contains "$full_mode_workflow_verify_list" "plans/tests/test_recon_operator_runner.sh"
assert_list_contains "$full_mode_workflow_verify_list" "plans/tests/test_prd_set_pass.sh"

workflow_gate_block="$(
  awk '
    /log "14g\) workflow integration tests/ { in_block=1 }
    in_block { print }
    in_block && /^finish_parallel_group_or_exit$/ { exit }
  ' "$VERIFY_FORK"
)"
[[ -n "$workflow_gate_block" ]] || fail "missing workflow integration gate block"

assert_file_contains_line "$VERIFY_FORK" 'start_parallel_workflow_test() {'
assert_file_contains_line "$VERIFY_FORK" 'finish_parallel_group_or_exit() {'
assert_text_contains_line "$workflow_gate_block" 'parallel_group_reset'
assert_text_contains_line "$workflow_gate_block" 'for workflow_test in "${WORKFLOW_INTEGRATION_TESTS[@]}"; do'
assert_text_contains_line "$workflow_gate_block" 'start_parallel_workflow_test "$workflow_test"'
assert_text_contains_line "$workflow_gate_block" 'if [[ "$MODE" == "full" ]]; then'
assert_text_contains_line "$workflow_gate_block" 'for workflow_test in "${FULL_MODE_WORKFLOW_INTEGRATION_TESTS[@]}"; do'
assert_text_contains_line "$workflow_gate_block" 'log "15) rust gates"'
assert_text_contains_line "$workflow_gate_block" 'finish_parallel_group_or_exit'
assert_text_line_before "$workflow_gate_block" 'for workflow_test in "${WORKFLOW_INTEGRATION_TESTS[@]}"; do' 'if [[ "$MODE" == "full" ]]; then'
assert_text_line_before "$workflow_gate_block" 'log "15) rust gates"' 'finish_parallel_group_or_exit'

parallel_gate_tests=(
  "plans/tests/test_codex_review_logged.sh"
  "plans/tests/test_review_logged_timeout_fallback.sh"
  "plans/tests/test_review_logged_timeout_retry_noncodex.sh"
  "plans/tests/test_review_logged_timeout_binary_unavailable.sh"
  "plans/tests/test_review_logged_prompt_literalization.sh"
  "plans/tests/test_pr_review_gate_hook.sh"
  "plans/tests/test_external_review_generic.sh"
  "plans/tests/test_preflight_diagnostics.sh"
  "plans/tests/test_preflight_fixture_profiles.sh"
  "plans/tests/test_workflow_allowlist_coverage.sh"
  "plans/tests/test_preflight_shell_syntax_setup_failure.sh"
  "plans/tests/test_preflight_shell_syntax_cross_file_masking.sh"
  "plans/tests/test_verify_fork_guardrails.sh"
  "plans/tests/test_verify_gate_contract_check_batching.sh"
  "plans/tests/test_slice_review_gate.sh"
  "plans/tests/test_story_review_findings_guard.sh"
  "plans/tests/test_fork_attestation_remediation_verify.sh"
  "plans/tests/test_fork_attestation_mirror.sh"
  "plans/tests/test_workflow_quick_step.sh"
  "plans/tests/test_toggle_policy_check.sh"
  "plans/tests/test_stoic_cli_invariant_check.sh"
  "plans/tests/test_live_enable_preflight.sh"
  "plans/tests/test_recon_handoff_sources.sh"
  "plans/tests/test_roadmap_evidence_audit.sh"
  "plans/tests/test_crossref_invariants.sh"
  "plans/tests/test_premortem_path_guard.sh"
  "plans/tests/test_lint_execution_facade.sh"
  "plans/tests/test_lint_risk_facade.sh"
  "plans/tests/test_lint_venue_facade.sh"
  "plans/tests/test_lint_soldier_infra_facade.sh"
  "plans/tests/test_contract_profile_parity.sh"
  "plans/tests/test_contract_review_emit.sh"
  "plans/tests/test_contract_change_ledger.sh"
  "plans/tests/test_recon_precheck.sh"
  "plans/tests/test_recon_operator_trace.sh"
  "plans/tests/test_recon_evidence_ledger.sh"
  "plans/tests/test_premortem_ready_ownership_conflict.sh"
  "plans/tests/test_premortem_gate_trading_hard_gate.sh"
  "plans/tests/test_review_command_wrappers.sh"
  "plans/tests/test_wf_step_stop_on_blocker.sh"
  "plans/tests/test_wf_step_path_signal_scan.sh"
  "plans/tests/test_wf_step_review_provenance.sh"
  "plans/tests/test_code_review_expert_guard.sh"
  "plans/tests/test_crossref_gate.sh"
  "plans/tests/test_artifact_lint.sh"
  "plans/tests/test_bidi_control_guard.sh"
)
full_mode_parallel_gate_tests=(
  "plans/tests/test_story_review_gate.sh"
  "plans/tests/test_pr_gate.sh"
)
for heavy_verify_test in "${parallel_gate_tests[@]}"; do
  assert_list_absent "$smoke_list" "$heavy_verify_test"
  assert_list_absent "$full_only_list" "$heavy_verify_test"
  assert_list_contains "$workflow_verify_list" "$heavy_verify_test"
  assert_list_absent "$full_mode_workflow_verify_list" "$heavy_verify_test"
done
for heavy_verify_test in "${full_mode_parallel_gate_tests[@]}"; do
  assert_list_absent "$smoke_list" "$heavy_verify_test"
  assert_list_absent "$full_only_list" "$heavy_verify_test"
  assert_list_contains "$full_mode_workflow_verify_list" "$heavy_verify_test"
  assert_list_absent "$workflow_verify_list" "$heavy_verify_test"
done
assert_list_absent "$smoke_list" "plans/tests/test_recon_bundle.sh"
assert_list_absent "$smoke_list" "plans/tests/test_recon_operator_runner.sh"
assert_list_absent "$smoke_list" "plans/tests/test_recon_scoreboard.sh"
assert_list_absent "$smoke_list" "plans/tests/test_preflight_fixture_timeout_controls.sh"

overlap="$(
  comm -12 \
    <(printf '%s\n' "$smoke_list" | sort -u) \
    <(printf '%s\n' "$full_only_list" | sort -u)
)"
[[ -z "$overlap" ]] || fail "smoke/full fixture lists overlap: $overlap"

serial_overlap="$(
  comm -12 \
    <(printf '%s\n' "$full_only_list" | sort -u) \
    <(printf '%s\n' "$full_only_serial_list" | sort -u)
)"
[[ -z "$serial_overlap" ]] || fail "parallel/serial full-only fixture lists overlap: $serial_overlap"

smoke_count="$(printf '%s\n' "$smoke_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
full_only_count="$(printf '%s\n' "$full_only_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
full_only_serial_count="$(printf '%s\n' "$full_only_serial_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
[[ "$smoke_count" == "11" ]] || fail "unexpected smoke fixture count: $smoke_count (expected 11)"
[[ "$full_only_count" == "9" ]] || fail "unexpected full-only fixture count: $full_only_count (expected 9)"
[[ "$full_only_serial_count" == "0" ]] || fail "unexpected full-only serial fixture count: $full_only_serial_count (expected 0)"

# Verify 14g dispatch loop pattern exists in verify_fork.sh
grep -Eq 'for workflow_test in "\$\{WORKFLOW_INTEGRATION_TESTS\[@\]\}"' "$VERIFY_FORK" \
  || fail "14g dispatch loop for WORKFLOW_INTEGRATION_TESTS missing"
grep -Eq 'start_parallel_workflow_test "\$workflow_test"' "$VERIFY_FORK" \
  || fail "start_parallel_workflow_test call missing in 14g loop"

echo "PASS: preflight fixture profile mapping"
