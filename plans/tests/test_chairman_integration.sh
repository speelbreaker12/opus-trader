#!/usr/bin/env bash
set -euo pipefail

# Smoke test: parallel_review.sh --chairman integration path
#
# Creates a mock chairman_synthesis.sh and mock review_logged.sh,
# runs parallel_review.sh --chairman, and asserts:
#   1. The chairman script was invoked
#   2. The chairman script received the expected arguments (run_dir, --tool, --style)
#   3. Chairman failure propagates to parallel_review.sh exit code

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/parallel_review.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ── Mock review_logged.sh ────────────────────────────────────────────
mock_review="$tmp_dir/review_logged.sh"
cat > "$mock_review" <<'MOCK'
#!/usr/bin/env bash
# Mock review_logged.sh — creates minimal reviewer artifacts
STORY="$1"; shift
TOOL=""
PROMPT="enriched"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)   TOOL="$2"; shift 2 ;;
    --prompt) PROMPT="$2"; shift 2 ;;
    *)        shift ;;
  esac
done

artifacts_root="${STORY_ARTIFACTS_ROOT:-.}/artifacts/story"
[[ -n "${STORY_ARTIFACTS_ROOT:-}" ]] && artifacts_root="$STORY_ARTIFACTS_ROOT"
out_dir="$artifacts_root/$STORY/$TOOL"
mkdir -p "$out_dir"
cat > "$out_dir/${TOOL}.${PROMPT}.md" <<EOF
---
provenance:
  tool: $TOOL
---
### P1 Mock finding from $TOOL
**Citation:** \`src/foo.rs:42\`
**Issue:** test issue
**Fix:** test fix
EOF
exit 0
MOCK
chmod +x "$mock_review"

# ── Mock chairman_synthesis.sh (success) ─────────────────────────────
mock_chairman="$tmp_dir/chairman_synthesis_ok.sh"
cat > "$mock_chairman" <<'MOCK'
#!/usr/bin/env bash
# Record invocation arguments for assertion
echo "$@" > "$(dirname "$0")/chairman_invocation.log"
exit 0
MOCK
chmod +x "$mock_chairman"

# ── Mock chairman_synthesis.sh (failure) ─────────────────────────────
mock_chairman_fail="$tmp_dir/chairman_synthesis_fail.sh"
cat > "$mock_chairman_fail" <<'MOCK'
#!/usr/bin/env bash
echo "$@" > "$(dirname "$0")/chairman_fail_invocation.log"
exit 1
MOCK
chmod +x "$mock_chairman_fail"

# ── Setup artifacts root ─────────────────────────────────────────────
artifacts_root="$tmp_dir/artifacts"
mkdir -p "$artifacts_root"

# ═══════════════════════════════════════════════════════════════════════
# Test 1: Chairman script is called with expected arguments on success
# ═══════════════════════════════════════════════════════════════════════

# Override CHAIRMAN_SCRIPT via sed on a copy of parallel_review.sh
test_script="$tmp_dir/parallel_review_test.sh"
sed "s|CHAIRMAN_SCRIPT=.*|CHAIRMAN_SCRIPT=\"$mock_chairman\"|" "$SCRIPT" > "$test_script"
chmod +x "$test_script"

set +e
STORY_ARTIFACTS_ROOT="$artifacts_root" \
  "$test_script" TEST-001 \
    --base main \
    --tools codex,sonnet \
    --prompt enriched \
    --chairman opus \
    --review-script "$mock_review" \
    > "$tmp_dir/test1_stdout.log" 2>&1
test1_rc=$?
set -e

if [[ $test1_rc -ne 0 ]]; then
  cat "$tmp_dir/test1_stdout.log"
  fail "test1: parallel_review.sh exited $test1_rc (expected 0)"
fi

# Assert chairman was invoked
invocation_log="$tmp_dir/chairman_invocation.log"
if [[ ! -f "$invocation_log" ]]; then
  fail "test1: chairman script was not invoked"
fi

invocation="$(cat "$invocation_log")"

# Assert run_dir argument
if [[ "$invocation" != *"TEST-001"* ]]; then
  fail "test1: chairman invocation missing story run dir (got: $invocation)"
fi

# Assert --tool argument
if [[ "$invocation" != *"--tool opus"* ]]; then
  fail "test1: chairman invocation missing '--tool opus' (got: $invocation)"
fi

# Assert --style argument matches prompt style
if [[ "$invocation" != *"--style enriched"* ]]; then
  fail "test1: chairman invocation missing '--style enriched' (got: $invocation)"
fi

pass "test1: chairman invoked with correct arguments"

# ═══════════════════════════════════════════════════════════════════════
# Test 2: Chairman failure propagates to non-zero exit code
# ═══════════════════════════════════════════════════════════════════════

# Fresh artifacts dir for test2
artifacts_root2="$tmp_dir/artifacts2"
mkdir -p "$artifacts_root2"

test_script2="$tmp_dir/parallel_review_test2.sh"
sed "s|CHAIRMAN_SCRIPT=.*|CHAIRMAN_SCRIPT=\"$mock_chairman_fail\"|" "$SCRIPT" > "$test_script2"
chmod +x "$test_script2"

set +e
STORY_ARTIFACTS_ROOT="$artifacts_root2" \
  "$test_script2" TEST-002 \
    --base main \
    --tools codex,sonnet \
    --prompt enriched \
    --chairman opus \
    --review-script "$mock_review" \
    > "$tmp_dir/test2_stdout.log" 2>&1
test2_rc=$?
set -e

if [[ $test2_rc -eq 0 ]]; then
  fail "test2: parallel_review.sh exited 0 despite chairman failure (expected non-zero)"
fi

pass "test2: chairman failure propagated to exit code $test2_rc"

# ═══════════════════════════════════════════════════════════════════════
# Test 3: Chairman is skipped when reviews fail
# ═══════════════════════════════════════════════════════════════════════

# Create a failing mock review
mock_review_fail="$tmp_dir/review_fail.sh"
cat > "$mock_review_fail" <<'MOCK'
#!/usr/bin/env bash
exit 1
MOCK
chmod +x "$mock_review_fail"

artifacts_root3="$tmp_dir/artifacts3"
mkdir -p "$artifacts_root3"

# Reset the chairman log
rm -f "$tmp_dir/chairman_invocation.log"

test_script3="$tmp_dir/parallel_review_test3.sh"
sed "s|CHAIRMAN_SCRIPT=.*|CHAIRMAN_SCRIPT=\"$mock_chairman\"|" "$SCRIPT" > "$test_script3"
chmod +x "$test_script3"

set +e
STORY_ARTIFACTS_ROOT="$artifacts_root3" \
  "$test_script3" TEST-003 \
    --base main \
    --tools codex,sonnet \
    --chairman opus \
    --review-script "$mock_review_fail" \
    > "$tmp_dir/test3_stdout.log" 2>&1
test3_rc=$?
set -e

if [[ -f "$tmp_dir/chairman_invocation.log" ]]; then
  fail "test3: chairman was invoked despite review failures (should be skipped)"
fi

pass "test3: chairman correctly skipped when reviews fail"

echo
echo "All chairman integration tests passed."
