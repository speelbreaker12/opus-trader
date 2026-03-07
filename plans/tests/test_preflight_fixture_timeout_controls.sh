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
PINNED_FIXTURE_MODE="smoke"

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
    /^FULL_ONLY_REVIEW_FIXTURE_TESTS=\(/ {
      print
      print "  \"plans/tests/test_dummy_sleep.sh\""
      in_full=1
      next
    }
    in_full && /^\)/ {in_full=0; print; next}
    in_full {next}
    {print}
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

rewrite_fixture_arrays_repeated_dummy() {
  local file="$1"
  local repeat_count="$2"
  local tmp_file="$file.tmp"
  local line=""
  local in_smoke=0
  local in_full=0

  while IFS= read -r line; do
    if [[ "$line" == 'SMOKE_REVIEW_FIXTURE_TESTS=(' ]]; then
      printf '%s\n' "$line" >> "$tmp_file"
      i=0
      while [[ "$i" -lt "$repeat_count" ]]; do
        printf '  "%s"\n' "plans/tests/test_dummy_sleep.sh" >> "$tmp_file"
        i=$((i + 1))
      done
      in_smoke=1
      continue
    fi
    if [[ "$line" == 'FULL_ONLY_REVIEW_FIXTURE_TESTS=(' ]]; then
      printf '%s\n' "$line" >> "$tmp_file"
      i=0
      while [[ "$i" -lt "$repeat_count" ]]; do
        printf '  "%s"\n' "plans/tests/test_dummy_sleep.sh" >> "$tmp_file"
        i=$((i + 1))
      done
      in_full=1
      continue
    fi
    if [[ "$in_smoke" -eq 1 ]]; then
      if [[ "$line" == ')' ]]; then
        in_smoke=0
        printf '%s\n' "$line" >> "$tmp_file"
      fi
      continue
    fi
    if [[ "$in_full" -eq 1 ]]; then
      if [[ "$line" == ')' ]]; then
        in_full=0
        printf '%s\n' "$line" >> "$tmp_file"
      fi
      continue
    fi
    printf '%s\n' "$line" >> "$tmp_file"
  done < "$file"
  mv "$tmp_file" "$file"
}

rewrite_supports_wait_n_to_false() {
  local file="$1"
  local tmp_file="$file.tmp"
  awk '
    BEGIN {in_fn=0}
    /^supports_wait_n\(\) \{/ {
      print "supports_wait_n() {"
      print "  return 1"
      print "}"
      in_fn=1
      next
    }
    in_fn && /^}$/ {in_fn=0; next}
    in_fn {next}
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
write_pass_script "$repo/plans/premortem_path_guard.sh"
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

invalid_wait_mode_log="$tmp_dir/invalid_wait_mode.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_WAIT_N_MODE=broken \
  ./plans/preflight.sh >"$invalid_wait_mode_log" 2>&1
)
invalid_wait_mode_rc=$?
set -e
[[ "$invalid_wait_mode_rc" -eq 2 ]] || fail "expected invalid wait mode to fail-closed with rc=2, got $invalid_wait_mode_rc"
grep -Fq "Invalid PREFLIGHT_WAIT_N_MODE='broken'" "$invalid_wait_mode_log" \
  || fail "missing invalid wait-mode diagnostics"

force_wait_n_script="$repo/plans/preflight_force_wait_n_unsupported.sh"
cp "$repo/plans/preflight.sh" "$force_wait_n_script"
rewrite_supports_wait_n_to_false "$force_wait_n_script"
chmod +x "$force_wait_n_script"

force_on_unsupported_log="$tmp_dir/force_on_unsupported.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_WAIT_N_MODE=force_on \
  "$force_wait_n_script" >"$force_on_unsupported_log" 2>&1
)
force_on_unsupported_rc=$?
set -e
[[ "$force_on_unsupported_rc" -eq 2 ]] \
  || fail "expected force_on without wait -n support to fail-closed with rc=2, got $force_on_unsupported_rc"
grep -Fq "PREFLIGHT_WAIT_N_MODE=force_on requires wait -n support" "$force_on_unsupported_log" \
  || fail "missing force_on unsupported diagnostics"

mock_fast_hash_git_bin="$tmp_dir/mock_fast_hash_git_bin"
mkdir -p "$mock_fast_hash_git_bin"
cat > "$mock_fast_hash_git_bin/git" <<EOF
#!/usr/bin/env bash
set -euo pipefail
real_git="$(
  command -v git
)"
if [[ "\${1:-}" == "diff" && "\${2:-}" == "--quiet" ]]; then
  exit 0
fi
if [[ "\${1:-}" == "ls-files" ]]; then
  if [[ "\${2:-}" == "--others" ]]; then
    exit 0
  fi
  if [[ "\${2:-}" == "--" ]]; then
    # Degenerate fast-path list: helper must reject this and fallback.
    printf '   \\n'
    exit 0
  fi
fi
exec "\$real_git" "\$@"
EOF
chmod +x "$mock_fast_hash_git_bin/git"

mkdir -p "$repo/.cache"
printf '%s\n' 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855' \
  > "$repo/.cache/preflight_fixtures_smoke.hash"

degenerate_fast_hash_log="$tmp_dir/degenerate_fast_hash.log"
set +e
(
  cd "$repo"
  PATH="$mock_fast_hash_git_bin:$PATH" \
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=0 \
  DUMMY_EXIT_CODE=1 \
  ./plans/preflight.sh >"$degenerate_fast_hash_log" 2>&1
)
degenerate_fast_hash_rc=$?
set -e
[[ "$degenerate_fast_hash_rc" -eq 1 ]] \
  || fail "expected degenerate fast hash input to fallback and run fixture (rc=1), got $degenerate_fast_hash_rc"
if grep -Fq "Fixture tests (cached, 1 tests)" "$degenerate_fast_hash_log"; then
  fail "degenerate fast hash must not produce a cached fixture skip"
fi
grep -Fq "Fixture test failed: plans/tests/test_dummy_sleep.sh (rc=1" "$degenerate_fast_hash_log" \
  || fail "expected failing fixture to run after fast-hash rejection"

invalid_log="$tmp_dir/invalid_timeout.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=5s \
  ./plans/preflight.sh >"$invalid_log" 2>&1
)
invalid_rc=$?
set -e
[[ "$invalid_rc" -eq 2 ]] || fail "expected invalid timeout input to fail-closed with rc=2, got $invalid_rc"
grep -Fq "Invalid PREFLIGHT_FIXTURE_TEST_TIMEOUT='5s'" "$invalid_log" \
  || fail "missing invalid timeout diagnostics"

(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  ./plans/preflight.sh >/dev/null 2>&1
)

cached_invalid_log="$tmp_dir/cached_invalid_timeout.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=bad \
  ./plans/preflight.sh >"$cached_invalid_log" 2>&1
)
cached_invalid_rc=$?
set -e
[[ "$cached_invalid_rc" -eq 2 ]] || fail "expected invalid timeout to fail-closed with cached fixtures, got $cached_invalid_rc"
grep -Fq "Invalid PREFLIGHT_FIXTURE_TEST_TIMEOUT='bad'" "$cached_invalid_log" \
  || fail "missing cached invalid-timeout diagnostics"

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
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
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
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
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
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
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

timeout_invocation_log="$tmp_dir/mock_timeout_invocations.log"
cat > "$mock_bin/timeout" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "\$1" >> "$timeout_invocation_log"
shift
"\$@"
EOF
chmod +x "$mock_bin/timeout"

full_default_timeout_logged="$tmp_dir/full_default_timeout_logged.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE=full \
  PATH="$mock_bin:$PATH" \
  PREFLIGHT_NO_CACHE=1 \
  DUMMY_SLEEP_SECS=0 \
  ./plans/preflight.sh >"$full_default_timeout_logged" 2>&1
)
full_default_timeout_logged_rc=$?
set -e
[[ "$full_default_timeout_logged_rc" -eq 0 ]] \
  || fail "expected full fixture mode with logging timeout wrapper to pass, got rc=$full_default_timeout_logged_rc"
grep -Fxq "300" "$timeout_invocation_log" \
  || fail "expected full fixture mode to default fixture timeout to 300 seconds"

parallel_default_script="$repo/plans/preflight_parallel_default_jobs.sh"
cp "$repo/plans/preflight.sh" "$parallel_default_script"
rewrite_fixture_arrays_repeated_dummy "$parallel_default_script" 5
chmod +x "$parallel_default_script"

cat > "$repo/plans/tests/test_dummy_sleep.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${DUMMY_EXIT_CODE:-}" ]]; then
  exit "$DUMMY_EXIT_CODE"
fi

state_dir="${CONCURRENCY_STATE_DIR:-}"
if [[ -n "$state_dir" ]]; then
  mkdir -p "$state_dir"
  lock_dir="$state_dir/lockdir"
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.01
  done

  current=0
  if [[ -f "$state_dir/current" ]]; then
    current="$(cat "$state_dir/current")"
  fi
  current=$((current + 1))
  printf '%s\n' "$current" > "$state_dir/current"

  max_seen=0
  if [[ -f "$state_dir/max" ]]; then
    max_seen="$(cat "$state_dir/max")"
  fi
  if [[ "$current" -gt "$max_seen" ]]; then
    printf '%s\n' "$current" > "$state_dir/max"
  fi
  rmdir "$lock_dir"
fi

sleep "${DUMMY_SLEEP_SECS:-0}"

if [[ -n "$state_dir" ]]; then
  while ! mkdir "$lock_dir" 2>/dev/null; do
    sleep 0.01
  done
  current="$(cat "$state_dir/current")"
  current=$((current - 1))
  printf '%s\n' "$current" > "$state_dir/current"
  rmdir "$lock_dir"
fi

exit 0
EOF
chmod +x "$repo/plans/tests/test_dummy_sleep.sh"

mock_parallel_bin="$tmp_dir/mock_parallel_bin"
mkdir -p "$mock_parallel_bin"
cat > "$mock_parallel_bin/sysctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-n" && "${2:-}" == "hw.ncpu" ]]; then
  printf '2\n'
  exit 0
fi

echo "unexpected sysctl args: $*" >&2
exit 1
EOF
chmod +x "$mock_parallel_bin/sysctl"

parallel_default_log="$tmp_dir/parallel_default_jobs.log"
parallel_state_dir="$tmp_dir/parallel_state"
rm -rf "$parallel_state_dir"
mkdir -p "$parallel_state_dir"

set +e
(
  cd "$repo"
  PATH="$mock_parallel_bin:$PATH" \
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=0 \
  DUMMY_SLEEP_SECS=1 \
  CONCURRENCY_STATE_DIR="$parallel_state_dir" \
  "$parallel_default_script" >"$parallel_default_log" 2>&1
)
parallel_default_rc=$?
set -e
[[ "$parallel_default_rc" -eq 0 ]] \
  || fail "expected default parallel-jobs fixture run to pass, got rc=$parallel_default_rc"
parallel_max="$(cat "$parallel_state_dir/max" 2>/dev/null || echo 0)"
[[ "$parallel_max" -eq 2 ]] \
  || fail "expected default preflight fixture concurrency to match detected CPU count (2), saw $parallel_max"

echo "test_preflight_fixture_timeout_controls.sh: ok"
