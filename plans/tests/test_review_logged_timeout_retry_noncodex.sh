#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
state_file="$tmp_dir/kimi_call_count.txt"

# Deterministic timeout-retry fixture:
# - Every invocation emits a citation immediately.
# - Then sleeps 2s.
#   * initial attempt (timeout=1s) is killed by timeout wrapper
#   * retry attempt (timeout=10s) completes successfully
#
# This avoids racey dependence on first-attempt side effects under load.
cat > "$mock_bin/kimi" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

state_file="${TEST_KIMI_STATE_FILE:?missing TEST_KIMI_STATE_FILE}"
count=0
if [[ -f "$state_file" ]]; then
  count="$(cat "$state_file" 2>/dev/null || echo 0)"
fi
count=$((count + 1))
echo "$count" > "$state_file"

echo "src/mock_timeout_retry.rs:7"
sleep 2
exit 0
EOF
chmod +x "$mock_bin/kimi"

story="S9-TIMEOUT-RETRY"
out_root="$tmp_dir/out"

PATH="$mock_bin:$PATH" \
TEST_KIMI_STATE_FILE="$state_file" \
REVIEW_LOG_TIMEOUT_RETRY_SECONDS=10 \
bash "$SCRIPT" "$story" \
  --tool kimi \
  --commit HEAD \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout retry" >/dev/null

review_file="$out_root/$story/kimi/kimi.enriched.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"

grep -Fq -- "- Timeout Triggered: true" "$review_file" || fail "timeout trigger metadata missing"
grep -Fq -- "- Timeout Retry Seconds: 10" "$review_file" || fail "timeout retry metadata missing"
grep -Fq -- "- Timeout Fallback Kind: timeout_retry" "$review_file" || fail "timeout retry fallback kind missing"
grep -Fq -- "- Timeout Attempts: 1" "$review_file" || fail "timeout attempts should be 1"
grep -Fq -- "src/mock_timeout_retry.rs:7" "$review_file" || fail "retry transcript citation missing"

# Gemini should resolve a default timeout in generic mode instead of tripping
# `set -u` on an uninitialized timeout_seconds variable.
cat > "$mock_bin/gemini" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "src/mock_gemini_default_timeout.rs:9"
exit 0
EOF
chmod +x "$mock_bin/gemini"

story_gemini="S9-GEMINI-DEFAULT-TIMEOUT"
out_root_gemini="$tmp_dir/out-gemini"

PATH="$mock_bin:$PATH" \
GEMINI_MODEL="gemini-3-pro-preview" \
bash "$SCRIPT" "$story_gemini" \
  --tool gemini \
  --commit HEAD \
  --out-root "$out_root_gemini" \
  --title "fixture gemini default timeout" >/dev/null

gemini_review_file="$out_root_gemini/$story_gemini/gemini/gemini.enriched.md"
[[ -f "$gemini_review_file" ]] || fail "missing review artifact: $gemini_review_file"

grep -Fq -- "- Timeout Seconds: 600" "$gemini_review_file" || fail "gemini default timeout metadata missing"
grep -Fq -- "- Command Exit Code: 0" "$gemini_review_file" || fail "gemini default timeout run should succeed"
grep -Fq -- "src/mock_gemini_default_timeout.rs:9" "$gemini_review_file" || fail "gemini transcript citation missing"

echo "test_review_logged_timeout_retry_noncodex.sh: ok"
