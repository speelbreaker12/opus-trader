#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_doc_budget.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mk_fixture() {
  local dir="$1"
  local protocol_lines="$2"
  local reference_lines="$3"
  local handoff_lines="$4"

  mkdir -p \
    "$dir/reviews/reconciliations" \
    "$dir/plans"

  seq 1 "$protocol_lines" | sed 's/^/protocol line /' > "$dir/reviews/reconciliations/PROTOCOL.md"
  seq 1 "$reference_lines" | sed 's/^/reference line /' > "$dir/reviews/reconciliations/REFERENCE.md"
  seq 1 "$handoff_lines" | sed 's/^/handoff line /' > "$dir/reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md"
  : > "$dir/plans/progress.txt"
}

# Case 1: baseline pass under default budget.
fixture_pass="$tmp_dir/pass"
mk_fixture "$fixture_pass" 200 200 200
pass_out="$(RECON_DOC_BUDGET_ROOT="$fixture_pass" "$SCRIPT" 2>&1)"
echo "$pass_out" | grep -Fq "DOC_LINES reviews/reconciliations/PROTOCOL.md 200" || fail "missing per-file count output"
echo "$pass_out" | grep -Fq "TOTAL_LINES 600" || fail "missing total line output"
echo "$pass_out" | grep -Fq "PASS: recon doc budget (600/1200)" || fail "missing pass summary"

# Case 2: fail when over budget.
fixture_over="$tmp_dir/over"
mk_fixture "$fixture_over" 500 450 300
set +e
over_out="$(RECON_DOC_BUDGET_ROOT="$fixture_over" "$SCRIPT" 2>&1)"
over_rc=$?
set -e
[[ "$over_rc" -ne 0 ]] || fail "expected over-budget fixture to fail"
echo "$over_out" | grep -Fq "BUDGET_EXCEEDED" || fail "missing over-budget diagnostic"
echo "$over_out" | grep -Fq "TOTAL_LINES 1250" || fail "missing over-budget total line count"

# Case 3: missing required source fails closed.
fixture_missing="$tmp_dir/missing"
mk_fixture "$fixture_missing" 200 200 200
rm -f "$fixture_missing/reviews/reconciliations/REFERENCE.md"
set +e
missing_out="$(RECON_DOC_BUDGET_ROOT="$fixture_missing" "$SCRIPT" 2>&1)"
missing_rc=$?
set -e
[[ "$missing_rc" -ne 0 ]] || fail "expected missing-doc fixture to fail"
echo "$missing_out" | grep -Fq "MISSING_DOC" || fail "missing missing-doc diagnostic"

# Case 4: invalid thresholds fail closed.
for invalid in "" "abc" "-1"; do
  set +e
  invalid_out="$(RECON_DOC_BUDGET_ROOT="$fixture_pass" RECON_DOC_BUDGET_MAX_LINES="$invalid" "$SCRIPT" 2>&1)"
  invalid_rc=$?
  set -e
  [[ "$invalid_rc" -ne 0 ]] || fail "expected invalid threshold '$invalid' to fail"
  echo "$invalid_out" | grep -Fq "INVALID_THRESHOLD" || fail "missing invalid-threshold diagnostic for '$invalid'"
done

# Case 5: local override requires approval records.
set +e
override_blocked_out="$(RECON_DOC_BUDGET_ROOT="$fixture_over" RECON_DOC_BUDGET_MAX_LINES=1300 "$SCRIPT" 2>&1)"
override_blocked_rc=$?
set -e
[[ "$override_blocked_rc" -ne 0 ]] || fail "expected unapproved local override to fail"
echo "$override_blocked_out" | grep -Fq "OVERRIDE_APPROVAL_MISSING" || fail "missing override-approval diagnostic"

# Case 6: local override passes when approval metadata is present.
cat >> "$fixture_over/plans/progress.txt" <<'EOF'
RECON_DOC_BUDGET_OVERRIDE_APPROVED_BY: owner
RECON_DOC_BUDGET_OVERRIDE_REASON: temporary reconciliation protocol expansion
RECON_DOC_BUDGET_OVERRIDE_EXPIRES: 2026-04-01
EOF
override_ok_out="$(RECON_DOC_BUDGET_ROOT="$fixture_over" RECON_DOC_BUDGET_MAX_LINES=1300 "$SCRIPT" 2>&1)"
echo "$override_ok_out" | grep -Fq "INFO: local override approved by 'owner'" || fail "missing local override approval output"
echo "$override_ok_out" | grep -Fq "PASS: recon doc budget (1250/1300)" || fail "missing local override pass summary"

# Case 7: CI override attempts are ignored (budget remains hard-enforced).
fixture_ci="$tmp_dir/ci"
mk_fixture "$fixture_ci" 500 450 300
set +e
ci_out="$(RECON_DOC_BUDGET_ROOT="$fixture_ci" CI=1 RECON_DOC_BUDGET_MAX_LINES=1300 "$SCRIPT" 2>&1)"
ci_rc=$?
set -e
[[ "$ci_rc" -ne 0 ]] || fail "expected CI override attempt to fail when default budget exceeded"
echo "$ci_out" | grep -Fq "WARN: CI override ignored" || fail "missing CI override warning"
echo "$ci_out" | grep -Fq "BUDGET_EXCEEDED" || fail "missing CI hard-enforcement diagnostic"

echo "PASS: recon doc budget test"
