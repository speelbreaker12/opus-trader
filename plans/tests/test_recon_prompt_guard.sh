#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_prompt_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

mk_fixture() {
  local dst="$1"
  mkdir -p \
    "$dst/SKILLS" \
    "$dst/plans/step_prompts/recon" \
    "$dst/plans/prompts"
  cp "$ROOT/SKILLS/slice-execute.md" "$dst/SKILLS/slice-execute.md"
  cp "$ROOT/plans/step_prompts/recon/r1_audit.md" "$dst/plans/step_prompts/recon/r1_audit.md"
  cp "$ROOT/plans/step_prompts/recon/INDEX.md" "$dst/plans/step_prompts/recon/INDEX.md"
  cp "$ROOT/plans/prompts/reconcil.md" "$dst/plans/prompts/reconcil.md"
  cp "$ROOT/plans/prompts/slice_reconcile_r1_audit.md" "$dst/plans/prompts/slice_reconcile_r1_audit.md"
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Baseline must pass in-repo.
RECON_PROMPT_GUARD_ROOT="$ROOT" "$SCRIPT" >/dev/null

# Case 1: Canonical reference drift in recon index.
fixture_legacy="$tmp_dir/legacy"
mk_fixture "$fixture_legacy"
perl -0pi -e 's#reviews/reconciliations/PROTOCOL\.md#reviews/premortems/RUNBOOK_PREMORTEM_RECON.md#g' \
  "$fixture_legacy/plans/step_prompts/recon/INDEX.md"

set +e
legacy_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_legacy" "$SCRIPT" 2>&1)"
legacy_rc=$?
set -e
[[ "$legacy_rc" -ne 0 ]] || fail "expected canonical-reference drift case to fail"
if ! echo "$legacy_output" | grep -Eq "LEGACY_REFERENCE_DRIFT|CANONICAL_REFERENCE_MISSING"; then
  fail "missing canonical-reference drift diagnostic"
fi

# Case 2: R1 prompt mislabeled as write step.
fixture_mislabel="$tmp_dir/mislabel"
mk_fixture "$fixture_mislabel"
perl -0pi -e 's/R1 READ-ONLY AUDIT/R1 IMPLEMENTATION WRITE STEP/g' \
  "$fixture_mislabel/plans/step_prompts/recon/r1_audit.md"

set +e
mislabel_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_mislabel" "$SCRIPT" 2>&1)"
mislabel_rc=$?
set -e
[[ "$mislabel_rc" -ne 0 ]] || fail "expected read-only label regression case to fail"
echo "$mislabel_output" | grep -Fq "READ_ONLY_LABEL_MISSING" || fail "missing READ_ONLY_LABEL_MISSING diagnostic"

# Case 3: Surrogate fallback prohibition removed.
fixture_surrogate="$tmp_dir/surrogate"
mk_fixture "$fixture_surrogate"
perl -0pi -e 's/There is no surrogate or fallback path for R1\./Use surrogate fallback path for R1./g' \
  "$fixture_surrogate/plans/prompts/slice_reconcile_r1_audit.md"

set +e
surrogate_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_surrogate" "$SCRIPT" 2>&1)"
surrogate_rc=$?
set -e
[[ "$surrogate_rc" -ne 0 ]] || fail "expected surrogate regression case to fail"
echo "$surrogate_output" | grep -Fq "SURROGATE_POLICY_MISSING" || fail "missing SURROGATE_POLICY_MISSING diagnostic"

# Case 4: R1 prompt must hand off to implement, not self_review.
fixture_next_step="$tmp_dir/next_step"
mk_fixture "$fixture_next_step"
perl -0pi -e 's/READY FOR IMPLEMENT GATE/READY FOR SELF_REVIEW/g' \
  "$fixture_next_step/plans/prompts/slice_reconcile_r1_audit.md" \
  "$fixture_next_step/plans/step_prompts/recon/r1_audit.md"

set +e
next_step_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_next_step" "$SCRIPT" 2>&1)"
next_step_rc=$?
set -e
[[ "$next_step_rc" -ne 0 ]] || fail "expected next-step drift case to fail"
echo "$next_step_output" | grep -Fq "NEXT_STEP_DRIFT" || fail "missing NEXT_STEP_DRIFT diagnostic"

# Case 5: Trading lens must be explicitly bound to gate outcome.
fixture_lens="$tmp_dir/lens"
mk_fixture "$fixture_lens"
perl -0pi -e 's/Trading lens = `BLOCKING` requires `GATE: NO-GO`\./Trading lens and gate are independent./g' \
  "$fixture_lens/plans/prompts/slice_reconcile_r1_audit.md"

set +e
lens_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_lens" "$SCRIPT" 2>&1)"
lens_rc=$?
set -e
[[ "$lens_rc" -ne 0 ]] || fail "expected trading-lens gate-binding regression case to fail"
echo "$lens_output" | grep -Fq "TRADING_LENS_GATE_BINDING_MISSING" || fail "missing TRADING_LENS_GATE_BINDING_MISSING diagnostic"

# Case 6: slice-execute must reference premortem §5 for wrong-impl gate.
fixture_slice="$tmp_dir/slice"
mk_fixture "$fixture_slice"
perl -0pi -e 's/premortem §5 \(wrong impl gate\)/premortem §4 (wrong impl gate)/g' \
  "$fixture_slice/SKILLS/slice-execute.md"

set +e
slice_output="$(RECON_PROMPT_GUARD_ROOT="$fixture_slice" "$SCRIPT" 2>&1)"
slice_rc=$?
set -e
[[ "$slice_rc" -ne 0 ]] || fail "expected slice-execute wrong-section regression case to fail"
echo "$slice_output" | grep -Fq "WRONG_IMPL_SECTION_DRIFT" || fail "missing WRONG_IMPL_SECTION_DRIFT diagnostic"

# Case 7: missing/broken rg must fail closed.
fixture_missing_rg="$tmp_dir/missing_rg"
mk_fixture "$fixture_missing_rg"
mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/rg" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$mock_bin/rg"

set +e
missing_rg_output="$(
  PATH="$mock_bin:/usr/bin:/bin" RECON_PROMPT_GUARD_ROOT="$fixture_missing_rg" "$SCRIPT" 2>&1
)"
missing_rg_rc=$?
set -e
[[ "$missing_rg_rc" -ne 0 ]] || fail "expected missing rg case to fail closed"
echo "$missing_rg_output" | grep -Eq "FAIL: .*rg|MISSING_TOOL|SCANNER_ERROR" || fail "missing rg failure diagnostic"

echo "PASS: recon prompt guard test"
