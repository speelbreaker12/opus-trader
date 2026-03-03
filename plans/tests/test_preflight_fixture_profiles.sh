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
  ' "$PREFLIGHT"
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq "$needle" "$PREFLIGHT"; then
    fail "missing expected preflight line: $needle"
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

[[ -n "$smoke_list" ]] || fail "SMOKE_REVIEW_FIXTURE_TESTS is empty"
[[ -n "$full_only_list" ]] || fail "FULL_ONLY_REVIEW_FIXTURE_TESTS is empty"

assert_contains_line 'quick) PREFLIGHT_FIXTURE_MODE="smoke" ;;'
assert_contains_line 'if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" ]]; then'
assert_contains_line 'pass "Fixture profile: $PREFLIGHT_FIXTURE_MODE (${#REVIEW_FIXTURE_TESTS[@]} tests)"'
assert_contains_line 'PREFLIGHT_FIXTURE_TEST_TIMEOUT="${PREFLIGHT_FIXTURE_TEST_TIMEOUT:-180}"'
assert_contains_line 'PREFLIGHT_FIXTURE_TEST_TIMEOUT_WAS_SET=0'
assert_contains_line 'if [[ "$PREFLIGHT_FIXTURE_MODE" == "full" && "$PREFLIGHT_FIXTURE_TEST_TIMEOUT_WAS_SET" -eq 0 ]]; then'
assert_contains_line 'PREFLIGHT_FIXTURE_TEST_TIMEOUT=360'
assert_contains_line 'if [[ ! "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" =~ ^[0-9]+$ ]]; then'
assert_contains_line 'if [[ -n "$_TIMEOUT_BIN" ]] && [[ "$PREFLIGHT_FIXTURE_TEST_TIMEOUT" -gt 0 ]]; then'
assert_contains_line 'start_ns="$(now_monotonic_ns)"'
assert_contains_line 'timeout_ns=$((PREFLIGHT_FIXTURE_TEST_TIMEOUT * 1000000000))'
assert_contains_line 'echo "${status}|${duration_s}|${rc}" > "$fixture_results_dir/$idx"'
assert_contains_line 'pass "Fixture test: $(basename "$fixture_test") (${duration_s}s)"'

assert_list_contains "$smoke_list" "plans/tests/test_preflight_fixture_profiles.sh"
assert_list_contains "$smoke_list" "plans/tests/test_verify_timeout_policy.sh"
assert_list_contains "$smoke_list" "plans/tests/test_verify_fork_guardrails.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fail_closed_gate_map_paths.sh"
assert_list_contains "$smoke_list" "plans/tests/test_rust_gates_smoke_targets.sh"
assert_list_contains "$smoke_list" "plans/tests/test_review_logged_timeout_fallback.sh"
assert_list_contains "$smoke_list" "plans/tests/test_review_logged_timeout_retry_noncodex.sh"
assert_list_contains "$smoke_list" "plans/tests/test_review_logged_timeout_binary_unavailable.sh"
assert_list_contains "$smoke_list" "plans/tests/test_contract_profile_parity.sh"
assert_list_contains "$smoke_list" "plans/tests/test_contract_review_emit.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_bundle.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_precheck.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_operator_trace.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_operator_runner.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_scoreboard.sh"
assert_list_contains "$smoke_list" "plans/tests/test_recon_evidence_ledger.sh"
assert_list_contains "$smoke_list" "plans/tests/test_premortem_ready_ownership_conflict.sh"
assert_list_contains "$smoke_list" "plans/tests/test_wf_step_stop_on_blocker.sh"
assert_list_contains "$smoke_list" "plans/tests/test_wf_step_path_signal_scan.sh"
assert_list_contains "$smoke_list" "plans/tests/test_wf_step_review_provenance.sh"
assert_list_contains "$smoke_list" "plans/tests/test_code_review_expert_guard.sh"
assert_list_contains "$smoke_list" "plans/tests/test_roadmap_evidence_audit.sh"
assert_list_contains "$smoke_list" "plans/tests/test_crossref_invariants.sh"
assert_list_contains "$smoke_list" "plans/tests/test_crossref_gate.sh"
assert_list_contains "$smoke_list" "plans/tests/test_artifact_lint.sh"
assert_list_contains "$smoke_list" "plans/tests/test_story_review_findings_guard.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fork_attestation_remediation_verify.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fork_attestation_mirror.sh"
assert_list_contains "$smoke_list" "plans/tests/test_workflow_quick_step.sh"
assert_list_contains "$smoke_list" "plans/tests/test_toggle_policy_check.sh"
assert_list_contains "$smoke_list" "plans/tests/test_preflight_fixture_timeout_controls.sh"
assert_list_contains "$smoke_list" "plans/tests/test_prd_ref_check_status_lite_markers.sh"
assert_list_contains "$full_only_list" "plans/tests/test_prd_set_pass.sh"

# Heavy tests moved to verify_fork.sh gate 14g — must be absent from both arrays
assert_list_absent "$full_only_list" "plans/tests/test_story_review_gate.sh"
assert_list_absent "$full_only_list" "plans/tests/test_pr_gate.sh"
assert_list_absent "$smoke_list" "plans/tests/test_story_review_gate.sh"
assert_list_absent "$smoke_list" "plans/tests/test_pr_gate.sh"
assert_list_absent "$full_only_list" "plans/tests/test_preflight_fixture_profiles.sh"

# Verify moved tests are actually present in verify_fork.sh gate 14g
VERIFY_FORK="$ROOT/plans/verify_fork.sh"
[[ -f "$VERIFY_FORK" ]] || fail "missing verify_fork.sh: $VERIFY_FORK"
grep -q 'start_parallel_gate "wf_test_story_review_gate"' "$VERIFY_FORK" \
  || fail "test_story_review_gate.sh not found in verify_fork.sh gate 14g"
grep -q 'start_parallel_gate "wf_test_pr_gate"' "$VERIFY_FORK" \
  || fail "test_pr_gate.sh not found in verify_fork.sh gate 14g"

overlap="$(
  comm -12 \
    <(printf '%s\n' "$smoke_list" | sort -u) \
    <(printf '%s\n' "$full_only_list" | sort -u)
)"
[[ -z "$overlap" ]] || fail "smoke/full fixture lists overlap: $overlap"

smoke_count="$(printf '%s\n' "$smoke_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
full_only_count="$(printf '%s\n' "$full_only_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
[[ "$smoke_count" == "34" ]] || fail "unexpected smoke fixture count: $smoke_count (expected 34)"
[[ "$full_only_count" == "8" ]] || fail "unexpected full-only fixture count: $full_only_count (expected 8)"

echo "PASS: preflight fixture profile mapping"
