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

assert_list_contains "$smoke_list" "plans/tests/test_preflight_fixture_profiles.sh"
assert_list_contains "$smoke_list" "plans/tests/test_verify_timeout_policy.sh"
assert_list_contains "$smoke_list" "plans/tests/test_contract_profile_parity.sh"
assert_list_contains "$smoke_list" "plans/tests/test_roadmap_evidence_audit.sh"
assert_list_contains "$smoke_list" "plans/tests/test_crossref_invariants.sh"
assert_list_contains "$smoke_list" "plans/tests/test_crossref_gate.sh"
assert_list_contains "$smoke_list" "plans/tests/test_story_review_findings_guard.sh"
assert_list_contains "$smoke_list" "plans/tests/test_story_review_equivalence_check.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fork_attestation_remediation_verify.sh"
assert_list_contains "$smoke_list" "plans/tests/test_fork_attestation_mirror.sh"
assert_list_contains "$smoke_list" "plans/tests/test_workflow_quick_step.sh"
assert_list_contains "$smoke_list" "plans/tests/test_toggle_policy_check.sh"
assert_list_contains "$full_only_list" "plans/tests/test_story_review_gate.sh"
assert_list_contains "$full_only_list" "plans/tests/test_pr_gate.sh"
assert_list_contains "$full_only_list" "plans/tests/test_prd_set_pass.sh"

assert_list_absent "$smoke_list" "plans/tests/test_pr_gate.sh"
assert_list_absent "$full_only_list" "plans/tests/test_preflight_fixture_profiles.sh"

overlap="$(
  comm -12 \
    <(printf '%s\n' "$smoke_list" | sort -u) \
    <(printf '%s\n' "$full_only_list" | sort -u)
)"
[[ -z "$overlap" ]] || fail "smoke/full fixture lists overlap: $overlap"

smoke_count="$(printf '%s\n' "$smoke_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
full_only_count="$(printf '%s\n' "$full_only_list" | sed '/^$/d' | wc -l | tr -d '[:space:]')"
[[ "$smoke_count" == "20" ]] || fail "unexpected smoke fixture count: $smoke_count (expected 20)"
[[ "$full_only_count" == "9" ]] || fail "unexpected full-only fixture count: $full_only_count (expected 9)"

echo "PASS: preflight fixture profile mapping"
