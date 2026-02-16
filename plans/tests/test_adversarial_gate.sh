#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/lib/adversarial_gate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$GATE" ]] || fail "adversarial gate not executable: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ─── Test 1: gate runs and produces valid report ─────────────────────────
echo "test 1: gate produces valid adversarial_report.json"

export VERIFY_ARTIFACTS_DIR="$tmp_dir/run1"
mkdir -p "$VERIFY_ARTIFACTS_DIR"

set +e
bash "$GATE" >"$tmp_dir/run1_stdout.log" 2>"$tmp_dir/run1_stderr.log"
rc=$?
set -e

[[ "$rc" -eq 0 ]] || fail "gate exited $rc (expected 0); stderr: $(cat "$tmp_dir/run1_stderr.log")"

report="$VERIFY_ARTIFACTS_DIR/adversarial_report.json"
[[ -f "$report" ]] || fail "adversarial_report.json not created"
jq empty "$report" || fail "adversarial_report.json is not valid JSON"

# Verify report structure
for field in invariants_in_spec invariants_testable invariants_deferred invariants_targeted \
             missing_ids unexpected_ids attack_vectors_tried attacks_blocked attacks_succeeded; do
  jq -e "has(\"$field\")" "$report" >/dev/null || fail "report missing field: $field"
done

# Verify no missing IDs (all testable GIs are covered)
missing_count=$(jq '.missing_ids | length' "$report")
[[ "$missing_count" -eq 0 ]] || fail "expected 0 missing IDs, got $missing_count"

# Verify attacks_succeeded is 0
attacks_succeeded=$(jq '.attacks_succeeded' "$report")
[[ "$attacks_succeeded" -eq 0 ]] || fail "expected 0 attacks_succeeded, got $attacks_succeeded"

# Verify attack_vectors > 0
attack_vectors=$(jq '.attack_vectors_tried' "$report")
[[ "$attack_vectors" -gt 0 ]] || fail "expected attack_vectors > 0, got $attack_vectors"

echo "  ok"

# ─── Test 2: .rc file is written ─────────────────────────────────────────
echo "test 2: .rc file written on success"

rc_file="$VERIFY_ARTIFACTS_DIR/adversarial_invariant_tests.rc"
[[ -f "$rc_file" ]] || fail ".rc file not created"
rc_val="$(cat "$rc_file")"
[[ "$rc_val" == "0" ]] || fail "expected .rc=0, got $rc_val"

echo "  ok"

# ─── Test 3: sunset config is loadable ───────────────────────────────────
echo "test 3: gate_sunsets.sh is valid"

sunset_config="$ROOT/plans/config/gate_sunsets.sh"
[[ -f "$sunset_config" ]] || fail "gate_sunsets.sh not found"

# Source it and verify the date is parseable
(
  source "$sunset_config"
  [[ -n "$ADVERSARIAL_SUNSET_DATE" ]] || exit 1
  # Verify it looks like a date
  echo "$ADVERSARIAL_SUNSET_DATE" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$' || exit 1
)
[[ $? -eq 0 ]] || fail "gate_sunsets.sh invalid or ADVERSARIAL_SUNSET_DATE not parseable"

echo "  ok"

echo "PASS: adversarial gate tests"
