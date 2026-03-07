#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pipeline_script="$repo_root/plans/prd_pipeline.sh"
hash_utils="$repo_root/plans/lib/hash_utils.sh"
PIPELINE_LAST_RC=0

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$pipeline_script" ]] || fail "prd_pipeline.sh not found at $pipeline_script"
[[ -f "$hash_utils" ]] || fail "hash_utils.sh not found at $hash_utils"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup_fixture() {
  local fixture_root="$1"
  mkdir -p "$fixture_root/plans" "$fixture_root/plans/lib" "$fixture_root/.context" "$fixture_root/bin"

  cp "$pipeline_script" "$fixture_root/plans/prd_pipeline.sh"
  cp "$hash_utils" "$fixture_root/plans/lib/hash_utils.sh"
  chmod +x "$fixture_root/plans/prd_pipeline.sh"

  cat > "$fixture_root/plans/prd.json" <<'JSON'
{
  "items": []
}
JSON

  cat > "$fixture_root/plans/prd_schema_check.sh" <<'EOF_SCHEMA'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF_SCHEMA
  chmod +x "$fixture_root/plans/prd_schema_check.sh"

  cat > "$fixture_root/plans/prd_gate.sh" <<'EOF_GATE'
#!/usr/bin/env bash
set -euo pipefail
record_file="${GATE_RECORD_FILE:-}"
count_file="${PIPELINE_GATE_COUNT_FILE:-.context/gate_calls}"
count=0
if [[ -f "$count_file" ]]; then
  count="$(cat "$count_file")"
fi
count=$((count + 1))
printf '%s' "$count" > "$count_file"
if [[ -n "$record_file" ]]; then
  printf '%s\n' "$@" > "$record_file"
fi
behavior_key="PIPELINE_GATE_BEHAVIOR_${count}"
behavior="${!behavior_key:-${PIPELINE_GATE_BEHAVIOR:-pass}}"
case "$behavior" in
  pass)
    exit 0
    ;;
  fail)
    exit 1
    ;;
  sleep:*)
    sleep "${behavior#sleep:}"
    exit 0
    ;;
  *)
    echo "unknown gate behavior: $behavior" >&2
    exit 2
    ;;
esac
EOF_GATE
  chmod +x "$fixture_root/plans/prd_gate.sh"

  cat > "$fixture_root/plans/prd_autofix.sh" <<'EOF_AUTOFIX'
#!/usr/bin/env bash
set -euo pipefail
behavior="${PIPELINE_AUTOFIX_BEHAVIOR:-pass}"
case "$behavior" in
  pass)
    exit 0
    ;;
  fail)
    exit 1
    ;;
  sleep:*)
    sleep "${behavior#sleep:}"
    exit 0
    ;;
  *)
    echo "unknown autofix behavior: $behavior" >&2
    exit 2
    ;;
esac
EOF_AUTOFIX
  chmod +x "$fixture_root/plans/prd_autofix.sh"

  cat > "$fixture_root/plans/prd_cutter.sh" <<'EOF_CUTTER'
#!/usr/bin/env bash
set -euo pipefail
behavior="${PIPELINE_CUTTER_BEHAVIOR:-pass}"
case "$behavior" in
  pass)
    printf '%s\n' "# cutter change" >> "${PRD_FILE:-plans/prd.json}"
    exit 0
    ;;
  fail)
    exit 1
    ;;
  sleep:*)
    sleep "${behavior#sleep:}"
    exit 0
    ;;
  *)
    echo "unknown cutter behavior: $behavior" >&2
    exit 2
    ;;
esac
EOF_CUTTER
  chmod +x "$fixture_root/plans/prd_cutter.sh"

  cat > "$fixture_root/plans/run_prd_auditor.sh" <<'EOF_AUDITOR'
#!/usr/bin/env bash
set -euo pipefail
behavior="${PIPELINE_AUDITOR_BEHAVIOR:-pass}"
case "$behavior" in
  pass)
    exit 0
    ;;
  fail)
    exit 1
    ;;
  sleep:*)
    sleep "${behavior#sleep:}"
    exit 0
    ;;
  *)
    echo "unknown auditor behavior: $behavior" >&2
    exit 2
    ;;
esac
EOF_AUDITOR
  chmod +x "$fixture_root/plans/run_prd_auditor.sh"

  cat > "$fixture_root/plans/prd_patcher.sh" <<'EOF_PATCHER'
#!/usr/bin/env bash
set -euo pipefail
behavior="${PIPELINE_PATCHER_BEHAVIOR:-pass}"
case "$behavior" in
  pass)
    exit 0
    ;;
  fail)
    exit 1
    ;;
  sleep:*)
    sleep "${behavior#sleep:}"
    exit 0
    ;;
  *)
    echo "unknown patcher behavior: $behavior" >&2
    exit 2
    ;;
esac
EOF_PATCHER
  chmod +x "$fixture_root/plans/prd_patcher.sh"

  cat > "$fixture_root/bin/timeout" <<'EOF_TIMEOUT'
#!/usr/bin/env python3
import subprocess
import sys

if len(sys.argv) < 3:
    sys.exit(125)

timeout_seconds = float(sys.argv[1])
command = sys.argv[2:]

try:
    completed = subprocess.run(command, check=False, timeout=timeout_seconds)
    sys.exit(completed.returncode)
except subprocess.TimeoutExpired:
    sys.exit(124)
except OSError:
    sys.exit(127)
EOF_TIMEOUT
  chmod +x "$fixture_root/bin/timeout"
  cp "$fixture_root/bin/timeout" "$fixture_root/bin/gtimeout"
}

run_pipeline_fixture() {
  local fixture_root="$1"
  shift

  set +e
  (
    cd "$fixture_root"
    env "PATH=$fixture_root/bin:$PATH" "$@" ./plans/prd_pipeline.sh
  ) >"$fixture_root/pipeline.stdout" 2>"$fixture_root/pipeline.stderr"
  PIPELINE_LAST_RC=$?
  set -e
}

assert_recorded_args() {
  local record_file="$1"
  local expected_first="$2"
  local expected_second="$3"

  [[ -f "$record_file" ]] || fail "missing gate record file: $record_file"

  local first_arg
  local second_arg
  local extra_arg
  first_arg="$(sed -n '1p' "$record_file")"
  second_arg="$(sed -n '2p' "$record_file")"
  extra_arg="$(sed -n '3p' "$record_file")"

  [[ "$first_arg" == "$expected_first" ]] || fail "expected first arg '$expected_first', got '$first_arg'"
  [[ "$second_arg" == "$expected_second" ]] || fail "expected second arg '$expected_second', got '$second_arg'"
  [[ -z "$extra_arg" ]] || fail "expected exactly 2 args, found extra '$extra_arg'"
}

assert_blocked_reason() {
  local blocked_file="$1"
  local expected_reason="$2"
  local reason=""

  [[ -f "$blocked_file" ]] || fail "missing blocked json: $blocked_file"
  reason="$(jq -r '.reason // empty' "$blocked_file")"
  [[ "$reason" == "$expected_reason" ]] || fail "expected blocked reason '$expected_reason', got '$reason'"
}

quoted_fixture="$tmp_dir/quoted"
setup_fixture "$quoted_fixture"
run_pipeline_fixture "$quoted_fixture" \
  "GATE_RECORD_FILE=$quoted_fixture/gate_args.txt" \
  'PRD_GATE_ARGS=--label "two words"' \
  "PRD_AUDITOR_ENABLED=0"
[[ "$PIPELINE_LAST_RC" -eq 0 ]] || fail "quoted fixture expected rc=0, got $PIPELINE_LAST_RC"
assert_recorded_args "$quoted_fixture/gate_args.txt" "--label" "two words"

injection_fixture="$tmp_dir/injection"
setup_fixture "$injection_fixture"
malicious_target="$tmp_dir/pwned"
run_pipeline_fixture "$injection_fixture" \
  "GATE_RECORD_FILE=$injection_fixture/gate_args.txt" \
  'PRD_GATE_ARGS=--label "$(touch "'"$malicious_target"'")"' \
  "PRD_AUDITOR_ENABLED=0"
[[ "$PIPELINE_LAST_RC" -eq 0 ]] || fail "injection fixture expected rc=0, got $PIPELINE_LAST_RC"
assert_recorded_args "$injection_fixture/gate_args.txt" "--label" "\$(touch $malicious_target)"
[[ ! -e "$malicious_target" ]] || fail "command substitution payload executed unexpectedly"

gate_timeout_fixture="$tmp_dir/gate-timeout"
setup_fixture "$gate_timeout_fixture"
run_pipeline_fixture "$gate_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "MAX_REPAIR_PASSES=2" \
  "PIPELINE_GATE_BEHAVIOR_1=sleep:2" \
  "PRD_AUDITOR_ENABLED=0"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "gate timeout fixture expected non-zero rc"
assert_blocked_reason "$gate_timeout_fixture/.context/prd_pipeline_blocked.json" "GATE_TIMEOUT"
if grep -Fq '==> PRD_AUTOFIX' "$gate_timeout_fixture/pipeline.stderr"; then
  fail "gate timeout fixture should stop before PRD_AUTOFIX"
fi

autofix_timeout_fixture="$tmp_dir/autofix-timeout"
setup_fixture "$autofix_timeout_fixture"
run_pipeline_fixture "$autofix_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "PIPELINE_GATE_BEHAVIOR_1=fail" \
  "PIPELINE_AUTOFIX_BEHAVIOR=sleep:2" \
  "PRD_AUTOFIX_CMD=./plans/prd_autofix.sh" \
  "PRD_AUDITOR_ENABLED=0"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "autofix timeout fixture expected non-zero rc"
assert_blocked_reason "$autofix_timeout_fixture/.context/prd_pipeline_blocked.json" "AUTOFIX_TIMEOUT"

cutter_timeout_fixture="$tmp_dir/cutter-timeout"
setup_fixture "$cutter_timeout_fixture"
rm -f "$cutter_timeout_fixture/plans/prd_autofix.sh"
run_pipeline_fixture "$cutter_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "PIPELINE_GATE_BEHAVIOR_1=fail" \
  "PRD_CUTTER_CMD=./plans/prd_cutter.sh" \
  "PIPELINE_CUTTER_BEHAVIOR=sleep:2" \
  "PRD_AUDITOR_ENABLED=0"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "cutter timeout fixture expected non-zero rc"
assert_blocked_reason "$cutter_timeout_fixture/.context/prd_pipeline_blocked.json" "CUTTER_TIMEOUT"

auditor_timeout_fixture="$tmp_dir/auditor-timeout"
setup_fixture "$auditor_timeout_fixture"
run_pipeline_fixture "$auditor_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "PIPELINE_GATE_BEHAVIOR_1=pass" \
  "PIPELINE_AUDITOR_BEHAVIOR=sleep:2"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "auditor timeout fixture expected non-zero rc"
assert_blocked_reason "$auditor_timeout_fixture/.context/prd_pipeline_blocked.json" "AUDIT_TIMEOUT"

patcher_timeout_fixture="$tmp_dir/patcher-timeout"
setup_fixture "$patcher_timeout_fixture"
run_pipeline_fixture "$patcher_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "PIPELINE_GATE_BEHAVIOR_1=pass" \
  "PIPELINE_AUDITOR_BEHAVIOR=pass" \
  "PRD_PATCHER_CMD=./plans/prd_patcher.sh" \
  "PIPELINE_PATCHER_BEHAVIOR=sleep:2"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "patcher timeout fixture expected non-zero rc"
assert_blocked_reason "$patcher_timeout_fixture/.context/prd_pipeline_blocked.json" "PATCHER_TIMEOUT"

final_gate_timeout_fixture="$tmp_dir/final-gate-timeout"
setup_fixture "$final_gate_timeout_fixture"
run_pipeline_fixture "$final_gate_timeout_fixture" \
  "PIPELINE_CMD_TIMEOUT=1" \
  "PIPELINE_GATE_BEHAVIOR_1=pass" \
  "PIPELINE_GATE_BEHAVIOR_2=sleep:2" \
  "PIPELINE_AUDITOR_BEHAVIOR=pass"
[[ "$PIPELINE_LAST_RC" -ne 0 ]] || fail "final gate timeout fixture expected non-zero rc"
assert_blocked_reason "$final_gate_timeout_fixture/.context/prd_pipeline_blocked.json" "FINAL_GATE_TIMEOUT"

echo "test_prd_pipeline.sh: ok"
