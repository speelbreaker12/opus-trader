#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/workflow_quick_step.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$output" | grep -Fq "$pattern" || fail "$label missing expected pattern '$pattern'"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_verify="$tmp_dir/mock_verify.sh"
cat > "$mock_verify" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "$1" > "${VERIFY_CALL_ARGS:?missing VERIFY_CALL_ARGS}"
if [[ "${FORCE_VERIFY_FAIL:-0}" == "1" ]]; then
  echo "forced verify fail" >&2
  exit 9
fi
EOF
chmod +x "$mock_verify"

ok_output="$(
  cd "$ROOT" && \
  WORKFLOW_QUICK_VERIFY_ALLOW_OVERRIDE=1 \
  WORKFLOW_QUICK_VERIFY_SCRIPT="$mock_verify" \
  VERIFY_CALL_ARGS="$tmp_dir/verify.args" \
  "$SCRIPT" "WF-002" "post_findings_fixes"
)"
printf '%s\n' "$ok_output" | grep -Fq "OK: workflow quick step passed for WF-002 checkpoint=post_findings_fixes" || fail "missing success output"
grep -Fxq "quick" "$tmp_dir/verify.args" || fail "verify script was not called in quick mode"

expect_fail "missing args" "Usage:" "$SCRIPT"
expect_fail "invalid story id" "invalid STORY_ID" "$SCRIPT" "../bad" "pre_reviews"
expect_fail "story id with slash" "invalid STORY_ID" "$SCRIPT" "workflow/maintenance" "pre_reviews"
expect_fail "invalid checkpoint" "invalid checkpoint" "$SCRIPT" "WF-002" "bad_step"

set +e
fail_output="$(
  cd "$ROOT" && \
  FORCE_VERIFY_FAIL=1 \
  WORKFLOW_QUICK_VERIFY_ALLOW_OVERRIDE=1 \
  WORKFLOW_QUICK_VERIFY_SCRIPT="$mock_verify" \
  VERIFY_CALL_ARGS="$tmp_dir/verify_fail.args" \
  "$SCRIPT" "WF-002" "pre_reviews" 2>&1
)"
fail_rc=$?
set -e
[[ "$fail_rc" -ne 0 ]] || fail "verify failure should propagate"
printf '%s\n' "$fail_output" | grep -Fq "forced verify fail" || fail "missing propagated verify failure output"

echo "PASS: workflow_quick_step"
