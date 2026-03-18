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
mkdir -p "$repo/plans/tests" "$repo/scripts" "$repo/specs"
PINNED_FIXTURE_MODE="smoke"

cp "$SOURCE_PREFLIGHT" "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

rewrite_fixture_arrays() {
  local file="$1"
  local tmp_file="$file.tmp"
  awk '
    BEGIN {in_smoke=0; in_full=0; in_full_serial=0}
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
    /^FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS=\(/ {
      print
      print "  \"plans/tests/test_dummy_sleep.sh\""
      in_full_serial=1
      next
    }
    in_full_serial && /^\)/ {in_full_serial=0; print; next}
    in_full_serial {next}
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
  local in_full_serial=0

  : > "$tmp_file"
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
    if [[ "$line" == 'FULL_ONLY_SERIAL_REVIEW_FIXTURE_TESTS=(' ]]; then
      printf '%s\n' "$line" >> "$tmp_file"
      i=0
      while [[ "$i" -lt "$repeat_count" ]]; do
        printf '  "%s"\n' "plans/tests/test_dummy_sleep.sh" >> "$tmp_file"
        i=$((i + 1))
      done
      in_full_serial=1
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
    if [[ "$in_full_serial" -eq 1 ]]; then
      if [[ "$line" == ')' ]]; then
        in_full_serial=0
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

extract_fn() {
  local file="$1"
  local fn_name="$2"
  awk -v fn="$fn_name" '
    $0 ~ "^" fn "\\(\\)[[:space:]]*\\{" { in_fn=1 }
    in_fn {
      print
      if ($0 == "}") { in_fn=0 }
    }
  ' "$file"
}

rewrite_fixture_arrays "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

cat > "$repo/scripts/check_skills_index.py" <<'EOF'
#!/usr/bin/env python3
raise SystemExit(0)
EOF
chmod +x "$repo/scripts/check_skills_index.py"

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
rewrite_fixture_arrays_repeated_dummy "$parallel_default_script" 12
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

cat > "$mock_parallel_bin/sysctl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" == "-n" && "${2:-}" == "hw.ncpu" ]]; then
  printf '64\n'
  exit 0
fi

echo "unexpected sysctl args: $*" >&2
exit 1
EOF
chmod +x "$mock_parallel_bin/sysctl"

parallel_cap_log="$tmp_dir/parallel_cap_jobs.log"
parallel_cap_state_dir="$tmp_dir/parallel_cap_state"
rm -rf "$parallel_cap_state_dir"
mkdir -p "$parallel_cap_state_dir"

set +e
(
  cd "$repo"
  PATH="$mock_parallel_bin:$PATH" \
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=0 \
  DUMMY_SLEEP_SECS=3 \
  CONCURRENCY_STATE_DIR="$parallel_cap_state_dir" \
  "$parallel_default_script" >"$parallel_cap_log" 2>&1
)
parallel_cap_rc=$?
set -e
[[ "$parallel_cap_rc" -eq 0 ]] \
  || fail "expected capped parallel-jobs fixture run to pass, got rc=$parallel_cap_rc"
parallel_cap_max="$(cat "$parallel_cap_state_dir/max" 2>/dev/null || echo 0)"
[[ "$parallel_cap_max" -ge 2 ]] \
  || fail "expected capped parallel-jobs fixture run to remain parallel, saw max concurrency $parallel_cap_max"
[[ "$parallel_cap_max" -le 8 ]] \
  || fail "expected default preflight fixture concurrency to stay within the 8-worker cap, saw $parallel_cap_max"

parallel_empty_batch_script="$repo/plans/preflight_parallel_empty_batch.sh"
cp "$repo/plans/preflight.sh" "$parallel_empty_batch_script"
rewrite_fixture_arrays_repeated_dummy "$parallel_empty_batch_script" 2
chmod +x "$parallel_empty_batch_script"

parallel_empty_batch_log="$tmp_dir/parallel_empty_batch.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=0 \
  PREFLIGHT_PARALLEL_JOBS=2 \
  DUMMY_SLEEP_SECS=0 \
  "$parallel_empty_batch_script" >"$parallel_empty_batch_log" 2>&1
)
parallel_empty_batch_rc=$?
set -e
[[ "$parallel_empty_batch_rc" -eq 0 ]] \
  || fail "expected empty-batch prune fixture run to pass, got rc=$parallel_empty_batch_rc"
if grep -Fq "alive[@]: unbound variable" "$parallel_empty_batch_log"; then
  fail "empty-batch prune must not trip bash nounset on an empty alive[] array"
fi

parallel_fail_collect_script="$repo/plans/preflight_parallel_fail_collect.sh"
cp "$repo/plans/preflight.sh" "$parallel_fail_collect_script"
rewrite_fixture_arrays_repeated_dummy "$parallel_fail_collect_script" 2
chmod +x "$parallel_fail_collect_script"

parallel_fail_collect_log="$tmp_dir/parallel_fail_collect.log"
set +e
(
  cd "$repo"
  PREFLIGHT_FIXTURE_MODE="$PINNED_FIXTURE_MODE" \
  PREFLIGHT_NO_CACHE=1 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=0 \
  PREFLIGHT_PARALLEL_JOBS=2 \
  DUMMY_EXIT_CODE=1 \
  "$parallel_fail_collect_script" >"$parallel_fail_collect_log" 2>&1
)
parallel_fail_collect_rc=$?
set -e
[[ "$parallel_fail_collect_rc" -eq 1 ]] \
  || fail "expected failing batch to surface through result-file collection with rc=1, got $parallel_fail_collect_rc"
grep -Fq "Fixture test failed: plans/tests/test_dummy_sleep.sh (rc=1" "$parallel_fail_collect_log" \
  || fail "expected failing batch to reach fixture result collection after waiting on children"
if grep -Fq "alive[@]: unbound variable" "$parallel_fail_collect_log"; then
  fail "failing batch must not trip bash nounset on an empty alive[] array"
fi

preflight_helper_fns="$tmp_dir/preflight_helper_fns.sh"
{
  extract_fn "$SOURCE_PREFLIGHT" "prune_fixture_pids_once"
  extract_fn "$SOURCE_PREFLIGHT" "shift_fixture_pid_queue"
  extract_fn "$SOURCE_PREFLIGHT" "wait_for_fixture_slot"
} > "$preflight_helper_fns"

# Regression proof: on the no-wait-n fallback path, a completed child must
# free a slot without blocking on the oldest still-running PID.
# Current failure mode on bash 3.2 waits on fixture_pids[0] and leaves the slot
# idle until that oldest PID exits.
fixture_pids=()
PREFLIGHT_WAIT_N_USE=0
PREFLIGHT_PARALLEL_JOBS=2
source "$preflight_helper_fns"

sleep 5 &
slow_pid=$!
sleep 0.2 &
fast_pid=$!
fixture_pids=("$slow_pid" "$fast_pid")

slot_wait_started="$(python3 - <<'PY'
import time
print(time.monotonic())
PY
)"
wait_for_fixture_slot
slot_wait_elapsed="$(python3 - "$slot_wait_started" <<'PY'
import time
import sys

start = float(sys.argv[1])
print(f"{time.monotonic() - start:.3f}")
PY
)"

if python3 - "$slot_wait_elapsed" <<'PY'
import sys
elapsed = float(sys.argv[1])
sys.exit(0 if elapsed < 1.5 else 1)
PY
then
  :
else
  fail "expected no-wait-n fallback to free a slot from a completed child without blocking on oldest PID (elapsed=${slot_wait_elapsed}s)"
fi
[[ "${#fixture_pids[@]}" -eq 1 ]] \
  || fail "expected no-wait-n fallback to prune finished children down to one active PID, saw ${#fixture_pids[@]}"
[[ "${fixture_pids[0]}" == "$slow_pid" ]] \
  || fail "expected slow PID to remain active after pruning finished later child"

wait "$fast_pid" 2>/dev/null || true
kill "$slow_pid" 2>/dev/null || true
wait "$slow_pid" 2>/dev/null || true

echo "test_preflight_fixture_timeout_controls.sh: ok"
