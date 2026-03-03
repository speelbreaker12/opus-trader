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

# Kimi should fail closed on timeout with no retry path.
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

sleep 2
exit 0
EOF
chmod +x "$mock_bin/kimi"

# Provide a deterministic timeout wrapper so this fixture does not depend on
# host timeout/gtimeout behavior under parallel preflight load.
cat > "$mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

limit="${1:-}"
shift || true
[[ -n "$limit" ]] || exit 125

"$@" &
cmd_pid="$!"
(
  sleep "$limit"
  kill -TERM "$cmd_pid" 2>/dev/null || true
  sleep 0.1
  kill -KILL "$cmd_pid" 2>/dev/null || true
) &
watchdog_pid="$!"

set +e
wait "$cmd_pid"
rc=$?
set -e

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

case "$rc" in
  143|137) exit 124 ;;
  *) exit "$rc" ;;
esac
EOF
chmod +x "$mock_bin/timeout"
ln -sf timeout "$mock_bin/gtimeout"

story="S9-TIMEOUT-FAILCLOSED-KIMI"
out_root="$tmp_dir/out"

set +e
PATH="$mock_bin:$PATH" \
TEST_KIMI_STATE_FILE="$state_file" \
bash "$SCRIPT" "$story" \
  --tool kimi \
  --commit HEAD \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout fail-closed kimi" >/dev/null 2>&1
rc=$?
set -e

review_file="$out_root/$story/kimi/kimi.enriched.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"
[[ "$rc" -eq 7 ]] || fail "expected timeout hard-gate exit 7, got $rc"

grep -Fq -- "- Timeout Seconds: 1" "$review_file" || fail "timeout metadata missing"
grep -Fq -- "- Timed Out: true" "$review_file" || fail "timed_out marker missing"
grep -Fq -- "HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)" "$review_file" || fail "timeout hard-gate marker missing"

[[ "$(cat "$state_file")" == "1" ]] || fail "expected kimi to be invoked once"

echo "test_review_logged_timeout_retry_noncodex.sh: ok"
