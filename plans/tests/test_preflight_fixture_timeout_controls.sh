#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_PREFLIGHT="$ROOT/plans/preflight.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SOURCE_PREFLIGHT" ]] || fail "missing source preflight script: $SOURCE_PREFLIGHT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mkdir -p "$repo/plans/tests" "$repo/specs"

cp "$SOURCE_PREFLIGHT" "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

rewrite_fixture_arrays() {
  local file="$1"
  local tmp_file="$file.tmp"
  awk '
    BEGIN {in_smoke=0; in_full=0}
    /^SMOKE_REVIEW_FIXTURE_TESTS=\(/ {
      print
      print "  \"plans/tests/test_dummy_sleep.sh\""
      in_smoke=1
      next
    }
    in_smoke && /^\)/ {in_smoke=0; print; next}
    in_smoke {next}
    /^FULL_ONLY_REVIEW_FIXTURE_TESTS=\(/ {print; in_full=1; next}
    in_full && /^\)/ {in_full=0; print; next}
    in_full {next}
    {print}
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

rewrite_fixture_arrays "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

cat > "$repo/plans/tests/test_dummy_sleep.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DUMMY_EXIT_CODE:-}" ]]; then
  exit "$DUMMY_EXIT_CODE"
fi

sleep "${DUMMY_SLEEP_SECS:-0}"
exit 0
EOF
chmod +x "$repo/plans/tests/test_dummy_sleep.sh"

write_pass_script() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
  chmod +x "$path"
}

write_pass_script "$repo/plans/legacy_layout_guard.sh"
write_pass_script "$repo/plans/readme_ci_parity_check.sh"
write_pass_script "$repo/plans/slice_completion_review_guard.sh"
write_pass_script "$repo/plans/story_review_findings_guard.sh"
write_pass_script "$repo/plans/stoic_cli_invariant_check.sh"
write_pass_script "$repo/plans/toggle_policy_check.sh"
write_pass_script "$repo/plans/prd_schema_check.sh"

cat > "$repo/plans/prd.json" <<'EOF'
{}
EOF
cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract
EOF

(
  cd "$repo"
  git init -q
  git config user.name "fixture"
  git config user.email "fixture@example.com"
)

invalid_log="$tmp_dir/invalid_timeout.log"
set +e
(
  cd "$repo"
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=5s \
  ./plans/preflight.sh >"$invalid_log" 2>&1
)
invalid_rc=$?
set -e
[[ "$invalid_rc" -eq 2 ]] || fail "expected invalid timeout input to fail-closed with rc=2, got $invalid_rc"
grep -Fq "Invalid PREFLIGHT_FIXTURE_TEST_TIMEOUT='5s'" "$invalid_log" \
  || fail "missing invalid timeout diagnostics"

mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

limit="${1:-}"
shift || true
[[ -n "$limit" ]] || exit 2

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
rc="$?"
set -e

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

case "$rc" in
  143|137) exit 124 ;;
  *) exit "$rc" ;;
esac
EOF
chmod +x "$mock_bin/timeout"

timed_log="$tmp_dir/timed_fixture.log"
set +e
(
  cd "$repo"
  PATH="$mock_bin:$PATH" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=1 \
  DUMMY_SLEEP_SECS=2 \
  ./plans/preflight.sh >"$timed_log" 2>&1
)
timed_rc=$?
set -e
[[ "$timed_rc" -eq 1 ]] || fail "expected fixture timeout to fail with rc=1, got $timed_rc"
grep -Fq "Fixture test timed out: plans/tests/test_dummy_sleep.sh" "$timed_log" \
  || fail "missing fixture timeout classification"

no_timeout_log="$tmp_dir/no_timeout_wrapper.log"
set +e
(
  cd "$repo"
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=0 \
  DUMMY_EXIT_CODE=124 \
  ./plans/preflight.sh >"$no_timeout_log" 2>&1
)
no_timeout_rc=$?
set -e
[[ "$no_timeout_rc" -eq 1 ]] || fail "expected fixture failure rc=1 when timeout wrapper disabled, got $no_timeout_rc"
grep -Fq "Fixture test failed: plans/tests/test_dummy_sleep.sh (rc=124" "$no_timeout_log" \
  || fail "expected rc=124 to be classified as FAIL when timeout wrapper disabled"
if grep -Fq "Fixture test timed out: plans/tests/test_dummy_sleep.sh" "$no_timeout_log"; then
  fail "rc=124 should not be classified as timeout when timeout wrapper is disabled"
fi

wrapper_enabled_124_log="$tmp_dir/wrapper_enabled_124.log"
set +e
(
  cd "$repo"
  PATH="$mock_bin:$PATH" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=10 \
  DUMMY_EXIT_CODE=124 \
  ./plans/preflight.sh >"$wrapper_enabled_124_log" 2>&1
)
wrapper_enabled_124_rc=$?
set -e
[[ "$wrapper_enabled_124_rc" -eq 1 ]] || fail "expected fixture failure rc=1 for wrapper-enabled child rc=124, got $wrapper_enabled_124_rc"
grep -Fq "Fixture test failed: plans/tests/test_dummy_sleep.sh (rc=124" "$wrapper_enabled_124_log" \
  || fail "expected wrapper-enabled child rc=124 to be classified as FAIL"
if grep -Fq "Fixture test timed out: plans/tests/test_dummy_sleep.sh" "$wrapper_enabled_124_log"; then
  fail "wrapper-enabled child rc=124 should not be classified as timeout"
fi

echo "test_preflight_fixture_timeout_controls.sh: ok"
