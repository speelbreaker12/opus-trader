#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/check_contract_at_wording_drift.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -f "$SCRIPT" ]] || fail "missing checker script: $SCRIPT"

TMPDIR_BASE="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_BASE"' EXIT

setup_fixture_repo() {
  local dir="$1"
  mkdir -p "$dir/specs" "$dir/plans"
  cd "$dir"
  git init -q
  git config user.email "test@test.com"
  git config user.name "Test"
}

write_plan() {
  local dir="$1"
  cat > "$dir/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

Minimal fixture plan.
EOF
}

write_contract() {
  local dir="$1"
  local at100_then="$2"
  local at200_then="$3"
  cat > "$dir/specs/CONTRACT.md" <<EOF
# Contract

AT-100
- Given: the gate runs
- Then: $at100_then

AT-200
- Given: the other gate runs
- Then: $at200_then
EOF
}

write_prd() {
  local dir="$1"
  local quote="$2"
  cat > "$dir/plans/prd.json" <<EOF
{
  "items": [
    {
      "id": "S1-001",
      "contract_refs": ["AT-100"],
      "plan_refs": ["Implementation Plan"],
      "contract_must_evidence": [
        {
          "quote": "$quote",
          "location": "specs/CONTRACT.md",
          "anchor": "AT-100"
        }
      ],
      "enforcing_contract_ats": ["AT-100"]
    }
  ]
}
EOF
}

# Test 1: unchanged contract wording should pass.
test1_dir="$TMPDIR_BASE/test1"
setup_fixture_repo "$test1_dir"
write_plan "$test1_dir"
write_contract "$test1_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test1_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"

cd "$test1_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref HEAD 2>&1)" || rc=$?
[[ "$rc" == "0" ]] || fail "test1: expected exit 0, got $rc"
grep -Fq 'PASS[contract_at_wording_drift]' <<< "$output" \
  || fail "test1: expected pass diagnostic"
pass "test1: unchanged contract wording passes"

# Test 2: changed AT wording with stale PRD quote should fail.
test2_dir="$TMPDIR_BASE/test2"
setup_fixture_repo "$test2_dir"
write_plan "$test2_dir"
write_contract "$test2_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test2_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"
write_contract "$test2_dir" "new AT-100 wording" "old AT-200 wording"
git add specs/CONTRACT.md && git commit -q -m "change at100 wording"

cd "$test2_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref HEAD~1 2>&1)" || rc=$?
[[ "$rc" == "1" ]] || fail "test2: expected exit 1, got $rc"
grep -Fq 'AT-100' <<< "$output" || fail "test2: expected AT-100 in failure output"
grep -Fq 'S1-001' <<< "$output" || fail "test2: expected story id in failure output"
pass "test2: stale AT quote fails closed"

# Test 3: changed AT wording with updated PRD quote should pass.
test3_dir="$TMPDIR_BASE/test3"
setup_fixture_repo "$test3_dir"
write_plan "$test3_dir"
write_contract "$test3_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test3_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"
write_contract "$test3_dir" "new AT-100 wording" "old AT-200 wording"
write_prd "$test3_dir" "new AT-100 wording"
git add -A && git commit -q -m "change at100 wording and prd quote"

cd "$test3_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref HEAD~1 2>&1)" || rc=$?
[[ "$rc" == "0" ]] || fail "test3: expected exit 0, got $rc"
grep -Fq 'PASS[contract_at_wording_drift]' <<< "$output" \
  || fail "test3: expected pass diagnostic"
pass "test3: updated AT quote passes"

# Test 4: unrelated AT wording change should not trip unrelated quotes.
test4_dir="$TMPDIR_BASE/test4"
setup_fixture_repo "$test4_dir"
write_plan "$test4_dir"
write_contract "$test4_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test4_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"
write_contract "$test4_dir" "old AT-100 wording" "new AT-200 wording"
git add specs/CONTRACT.md && git commit -q -m "change at200 wording"

cd "$test4_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref HEAD~1 2>&1)" || rc=$?
[[ "$rc" == "0" ]] || fail "test4: expected exit 0, got $rc"
grep -Fq 'PASS[contract_at_wording_drift]' <<< "$output" \
  || fail "test4: expected pass diagnostic"
pass "test4: unrelated AT changes are ignored"

# Test 5: deleting the referenced AT block must fail closed.
test5_dir="$TMPDIR_BASE/test5"
setup_fixture_repo "$test5_dir"
write_plan "$test5_dir"
write_contract "$test5_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test5_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"
cat > "$test5_dir/specs/CONTRACT.md" <<'EOF'
# Contract

AT-200
- Given: the other gate runs
- Then: new AT-200 wording
EOF
git add specs/CONTRACT.md && git commit -q -m "remove at100 block"

cd "$test5_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref HEAD~1 2>&1)" || rc=$?
[[ "$rc" == "1" ]] || fail "test5: expected exit 1, got $rc"
grep -Fq 'AT-100' <<< "$output" || fail "test5: expected removed AT anchor in failure output"
grep -Fq 'S1-001' <<< "$output" || fail "test5: expected story id in failure output"
pass "test5: removed AT block fails closed"

# Test 6: unresolved base ref is a setup error.
test6_dir="$TMPDIR_BASE/test6"
setup_fixture_repo "$test6_dir"
write_plan "$test6_dir"
write_contract "$test6_dir" "old AT-100 wording" "old AT-200 wording"
write_prd "$test6_dir" "old AT-100 wording"
git add -A && git commit -q -m "base"

cd "$test6_dir"
rc=0
output="$(bash "$SCRIPT" --base-ref missing/ref 2>&1)" || rc=$?
[[ "$rc" == "2" ]] || fail "test6: expected exit 2, got $rc"
grep -Fq "unable to resolve merge-base" <<< "$output" \
  || fail "test6: expected merge-base failure diagnostic"
pass "test6: unresolved base ref fails as setup error"

echo "PASS: contract AT wording drift"
