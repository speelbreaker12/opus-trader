#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MAP="$ROOT/plans/fail_closed_gate_map.json"
COVERAGE="$ROOT/plans/fail_closed_coverage.sh"
BASH_BIN="$(command -v bash)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$MAP" ]] || fail "missing fail-closed gate map: $MAP"
[[ -f "$COVERAGE" ]] || fail "missing fail-closed coverage script: $COVERAGE"
[[ -n "$BASH_BIN" ]] || fail "bash not found"

recorded_path="$(
  jq -r '.recorded_before_dispatch[0] // ""' "$MAP"
)"

[[ "$recorded_path" == "src/execution/recorded_before_dispatch_gate_tests.rs" ]] \
  || fail "recorded_before_dispatch path must target src execution unit tests; got: $recorded_path"

grep -Fq 'DEFAULT_TEST_DIR="$SOLDIER_CORE_DIR/tests"' "$COVERAGE" \
  || fail "coverage script missing default tests dir guard"
grep -Fq 'if [[ "$tf" == */* ]]; then' "$COVERAGE" \
  || fail "coverage script missing subpath resolution branch"
grep -Fq 'full_path="$SOLDIER_CORE_DIR/$tf"' "$COVERAGE" \
  || fail "coverage script missing soldier_core-relative path resolution"
grep -Fq 'full_path="$DEFAULT_TEST_DIR/$tf"' "$COVERAGE" \
  || fail "coverage script missing tests-dir filename fallback"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

link_required_basics() {
  local bin_dir="$1"
  mkdir -p "$bin_dir"
  ln -sf "$(command -v dirname)" "$bin_dir/dirname"
}

run_and_capture() {
  local output_file="$1"
  shift

  set +e
  "$@" >"$output_file" 2>&1
  local rc=$?
  set -e
  printf '%s\n' "$rc"
}

no_jq_bin="$tmp_dir/no_jq_bin"
link_required_basics "$no_jq_bin"
no_jq_output="$tmp_dir/no_jq.out"
no_jq_rc="$(run_and_capture "$no_jq_output" env PATH="$no_jq_bin" "$BASH_BIN" "$COVERAGE")"
[[ "$no_jq_rc" == "2" ]] || fail "missing jq must exit 2, got: $no_jq_rc"
grep -Fq 'ERROR: jq required' "$no_jq_output" \
  || fail "missing jq diagnostic not emitted"

missing_map_root="$tmp_dir/missing_map_root"
mkdir -p "$missing_map_root/plans"
cp "$COVERAGE" "$missing_map_root/plans/fail_closed_coverage.sh"
missing_map_bin="$tmp_dir/missing_map_bin"
link_required_basics "$missing_map_bin"
cat > "$missing_map_bin/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
chmod +x "$missing_map_bin/jq"
missing_map_output="$tmp_dir/missing_map.out"
missing_map_rc="$(run_and_capture "$missing_map_output" env PATH="$missing_map_bin" "$BASH_BIN" "$missing_map_root/plans/fail_closed_coverage.sh")"
[[ "$missing_map_rc" == "2" ]] || fail "missing gate map must exit 2, got: $missing_map_rc"
grep -Fq 'ERROR: missing gate map:' "$missing_map_output" \
  || fail "missing gate map diagnostic not emitted"

echo "PASS: fail-closed gate map path handling"
