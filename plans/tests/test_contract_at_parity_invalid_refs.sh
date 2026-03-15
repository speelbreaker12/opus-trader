#!/usr/bin/env bash
# Test: contract-plan AT parity gate (prd_ref_check.sh AT integrity checks).
# Name includes "invalid" keyword for fail-closed coverage scanning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/prd_ref_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -f "$SCRIPT" ]] || fail "missing prd_ref_check.sh: $SCRIPT"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup_fixture_repo() {
  local dir="$1"
  mkdir -p "$dir"
  cd "$dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
}

write_contract() {
  local dir="$1"
  shift
  mkdir -p "$dir/specs"
  cat > "$dir/specs/CONTRACT.md" <<'CONTRACTEOF'
# Contract

## 1 Foundation

Acceptance tests:
CONTRACTEOF
  for at in "$@"; do
    echo "- $at: Some acceptance test" >> "$dir/specs/CONTRACT.md"
  done
}

write_plan() {
  local dir="$1"
  mkdir -p "$dir/specs" "$dir/docs"
  cat > "$dir/specs/IMPLEMENTATION_PLAN.md" <<'PLANEOF'
# Implementation Plan

## 1 Foundation
PLANEOF
  # prd_ref_check.sh appends docs/contract_kernel.json to EXTRA_CONTRACT_FILES;
  # without at least one file the array expansion fails under set -u.
  echo '{}' > "$dir/docs/contract_kernel.json"
}

write_prd() {
  local dir="$1"
  local prd_json="$2"
  mkdir -p "$dir/plans"
  echo "$prd_json" > "$dir/plans/prd.json"
}

write_deferred() {
  local dir="$1"
  local content="$2"
  echo "$content" > "$dir/specs/contract_deferred_ats.yml"
}

test1_dir="$TMPDIR_BASE/test1"
setup_fixture_repo "$test1_dir"
write_contract "$test1_dir" "AT-100" "AT-200"
write_plan "$test1_dir"
write_prd "$test1_dir" '{
  "items": [
    {"id":"S1-001","contract_refs":["1 Foundation"],"plan_refs":["1 Foundation"],"enforcing_contract_ats":["AT-100","AT-200"]}
  ]
}'
git add -A && git commit -q -m "init"

cd "$test1_dir"
rc=0
bash "$SCRIPT" plans/prd.json >/dev/null 2>&1 || rc=$?
[[ "$rc" == "0" ]] || fail "test1: expected exit 0, got $rc"
pass "test1: clean state -> exit 0"

test2_dir="$TMPDIR_BASE/test2"
setup_fixture_repo "$test2_dir"
write_contract "$test2_dir" "AT-100"
write_plan "$test2_dir"
write_prd "$test2_dir" '{
  "items": [
    {"id":"S1-001","contract_refs":["1 Foundation"],"plan_refs":["1 Foundation"],"enforcing_contract_ats":["AT-100","AT-999"]}
  ]
}'
git add -A && git commit -q -m "init"

cd "$test2_dir"
rc=0
output="$(bash "$SCRIPT" plans/prd.json 2>&1)" || rc=$?
[[ "$rc" == "1" ]] || fail "test2: expected exit 1 (dangling AT-999), got $rc"
echo "$output" | grep -q "AT-999" || fail "test2: expected AT-999 in error output"
pass "test2: dangling AT ref -> exit 1"

test3_dir="$TMPDIR_BASE/test3"
setup_fixture_repo "$test3_dir"
write_contract "$test3_dir" "AT-100" "AT-200" "AT-300"
write_plan "$test3_dir"
write_prd "$test3_dir" '{
  "items": [
    {"id":"S1-001","contract_refs":["1 Foundation"],"plan_refs":["1 Foundation"],"enforcing_contract_ats":["AT-100"]}
  ]
}'
git add -A && git commit -q -m "init"

cd "$test3_dir"
rc=0
output="$(bash "$SCRIPT" plans/prd.json 2>&1)" || rc=$?
[[ "$rc" == "0" ]] || fail "test3: expected exit 0 (uncovered is WARN only), got $rc"
echo "$output" | grep -q "WARN" || fail "test3: expected WARN for uncovered ATs"
pass "test3: uncovered AT -> exit 0 with WARN"

test4_dir="$TMPDIR_BASE/test4"
setup_fixture_repo "$test4_dir"
write_contract "$test4_dir" "AT-100"
write_plan "$test4_dir"
write_prd "$test4_dir" '{
  "items": [
    {"id":"S1-001","contract_refs":["1 Foundation"],"plan_refs":["1 Foundation"],"enforcing_contract_ats":["AT-100"]}
  ]
}'
write_contract "$test4_dir" "AT-100" "AT-200"
write_deferred "$test4_dir" "$(cat <<'DEFER'
AT-200:
  owner: "test"
  reason: "deferred for testing"
  target_phase: 2
DEFER
)"
git add -A && git commit -q -m "init"

cd "$test4_dir"
rc=0
output="$(bash "$SCRIPT" plans/prd.json 2>&1)" || rc=$?
[[ "$rc" == "0" ]] || fail "test4: expected exit 0, got $rc"
if echo "$output" | grep -q "AT-200.*not covered"; then
  fail "test4: AT-200 should be exempted by deferred list"
fi
pass "test4: deferred AT exempted -> exit 0"

test5_dir="$TMPDIR_BASE/test5"
setup_fixture_repo "$test5_dir"
write_contract "$test5_dir" "AT-500"
write_plan "$test5_dir"
write_prd "$test5_dir" '{
  "items": [
    {"id":"S1-001","contract_refs":["1 Foundation"],"plan_refs":["1 Foundation"],"enforcing_contract_ats":["AT-100"]}
  ]
}'
git add -A && git commit -q -m "init"

cd "$test5_dir"
rc=0
output="$(bash "$SCRIPT" plans/prd.json 2>&1)" || rc=$?
[[ "$rc" == "1" ]] || fail "test5: expected exit 1 (AT-100 dangling after renumber), got $rc"
echo "$output" | grep -q "AT-100" || fail "test5: expected AT-100 in error output"
pass "test5: AT renumbered, old ref dangling -> exit 1"

test6_dir="$TMPDIR_BASE/test6"
setup_fixture_repo "$test6_dir"
write_contract "$test6_dir" "AT-100"
write_plan "$test6_dir"
mkdir -p "$test6_dir/plans"
echo "{ invalid json" > "$test6_dir/plans/prd.json"
git add -A && git commit -q -m "init"

cd "$test6_dir"
rc=0
bash "$SCRIPT" plans/prd.json >/dev/null 2>&1 || rc=$?
[[ "$rc" != "0" ]] || fail "test6: expected non-zero exit (malformed JSON), got $rc"
pass "test6: malformed prd.json -> exit $rc (non-zero)"

echo ""
echo "PASS: all 6 contract AT parity test cases"
