#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
pipeline_script="$repo_root/plans/prd_pipeline.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$pipeline_script" ]] || fail "prd_pipeline.sh not found at $pipeline_script"

tmp_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$tmp_dir"
}
trap cleanup EXIT

setup_fixture() {
  local fixture_root="$1"
  mkdir -p "$fixture_root/plans" "$fixture_root/.context"

  cp "$pipeline_script" "$fixture_root/plans/prd_pipeline.sh"
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
record_file="${GATE_RECORD_FILE:?missing GATE_RECORD_FILE}"
printf '%s\n' "$@" > "$record_file"
exit 0
EOF_GATE
  chmod +x "$fixture_root/plans/prd_gate.sh"
}

run_pipeline_fixture() {
  local fixture_root="$1"
  local gate_args="$2"

  (
    cd "$fixture_root"
    GATE_RECORD_FILE="$fixture_root/gate_args.txt" \
    PRD_GATE_ARGS="$gate_args" \
    PRD_AUDITOR_ENABLED=0 \
    ./plans/prd_pipeline.sh
  ) >/dev/null 2>&1
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

quoted_fixture="$tmp_dir/quoted"
setup_fixture "$quoted_fixture"
run_pipeline_fixture "$quoted_fixture" '--label "two words"'
assert_recorded_args "$quoted_fixture/gate_args.txt" "--label" "two words"

injection_fixture="$tmp_dir/injection"
setup_fixture "$injection_fixture"
malicious_target="$tmp_dir/pwned"
run_pipeline_fixture "$injection_fixture" '--label "$(touch '"$malicious_target"')"'
assert_recorded_args "$injection_fixture/gate_args.txt" "--label" "\$(touch $malicious_target)"
[[ ! -e "$malicious_target" ]] || fail "command substitution payload executed unexpectedly"

echo "test_prd_pipeline.sh: ok"
