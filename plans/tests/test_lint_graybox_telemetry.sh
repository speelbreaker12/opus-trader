#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/lint_graybox_telemetry.sh"

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

space_root="$tmp_dir/gray box root"
plain_root="$tmp_dir/plain_root"
legacy_root="$tmp_dir/legacy_root"
mkdir -p "$space_root" "$plain_root" "$legacy_root"

cat > "$space_root/clean.rs" <<'EOF'
pub(crate) fn evaluate_clean_with_events<E>(events: &mut E) {
    let _ = events;
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" >/dev/null
pass "clean graybox seam passes lint for roots with spaces"

cat > "$plain_root/also_clean.rs" <<'EOF'
pub(crate) fn evaluate_another_clean_with_events<E>(events: &mut E) {
    let _ = events;
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root"$'\n'"$plain_root" bash "$SCRIPT" >/dev/null
pass "newline-delimited multi-root scan preserves spaces"

cat > "$legacy_root/legacy_clean.rs" <<'EOF'
pub(crate) fn evaluate_legacy_clean_with_events<E>(events: &mut E) {
    let _ = events;
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$plain_root $legacy_root" bash "$SCRIPT" >/dev/null
pass "legacy whitespace-delimited roots remain supported"

cat > "$space_root/record_gate_sequence.rs" <<'EOF'
pub(crate) fn evaluate_gate_sequence_with_events<E>(events: &mut E) {
    let _ = events;
    record_gate_sequence_result(GateSequenceResult::Allowed);
}
EOF

set +e
record_gate_sequence_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
record_gate_sequence_rc=$?
set -e
[[ $record_gate_sequence_rc -ne 0 ]] || fail "record_gate_sequence_result should fail graybox lint"
echo "$record_gate_sequence_out" | grep -Fq "wrapper-only record helper call" || fail "missing record helper diagnostic"
echo "$record_gate_sequence_out" | grep -Fq "evaluate_gate_sequence_with_events" || fail "missing function name in record helper diagnostic"
pass "record_gate_sequence_result fails lint"

rm -f "$space_root/record_gate_sequence.rs"

cat > "$space_root/record_slippage_sample.rs" <<'EOF'
pub(crate) fn evaluate_slippage_with_events<E>(events: &mut E) {
    let _ = events;
    record_expected_slippage_sample(1.25);
}
EOF

set +e
record_slippage_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
record_slippage_rc=$?
set -e
[[ $record_slippage_rc -ne 0 ]] || fail "record_expected_slippage_sample should fail graybox lint"
echo "$record_slippage_out" | grep -Fq "wrapper-only record helper call" || fail "missing slippage helper diagnostic"
echo "$record_slippage_out" | grep -Fq "evaluate_slippage_with_events" || fail "missing function name in slippage helper diagnostic"
pass "record_expected_slippage_sample fails lint"

rm -f "$space_root/record_slippage_sample.rs"

cat > "$space_root/tracing_warn.rs" <<'EOF'
pub(crate) fn evaluate_warn_with_events<E>(events: &mut E) {
    let _ = events;
    tracing::warn!("graybox seam should stay telemetry-pure");
}
EOF

set +e
tracing_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
tracing_rc=$?
set -e
[[ $tracing_rc -ne 0 ]] || fail "direct tracing macros should fail graybox lint"
echo "$tracing_out" | grep -Fq "direct tracing macro" || fail "missing tracing macro diagnostic"
echo "$tracing_out" | grep -Fq "evaluate_warn_with_events" || fail "missing function name in tracing diagnostic"
pass "direct tracing macros fail lint"

rm -f "$space_root/tracing_warn.rs"

cat > "$space_root/lifetime_helper.rs" <<'EOF'
pub(crate) fn evaluate_lifetime_with_events<'a, E>(events: &'a mut E) {
    let _ = events;
    record_gate_sequence_result(GateSequenceResult::Allowed);
}
EOF

set +e
lifetime_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
lifetime_rc=$?
set -e
[[ $lifetime_rc -ne 0 ]] || fail "lifetime-bearing seam should still fail graybox lint"
echo "$lifetime_out" | grep -Fq "wrapper-only record helper call" || fail "missing lifetime helper diagnostic"
echo "$lifetime_out" | grep -Fq "evaluate_lifetime_with_events" || fail "missing function name in lifetime diagnostic"
pass "lifetimes do not mask wrapper helper calls"

rm -f "$space_root/lifetime_helper.rs"

cat > "$space_root/local_record_method.rs" <<'EOF'
pub(crate) fn evaluate_local_metrics_with_events<E>(events: &mut E) {
    let _ = events;
    metrics.record_wal_nonblocking_allowed();
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" >/dev/null
pass "local record_* method calls stay allowed"

rm -f "$space_root/local_record_method.rs"

cat > "$space_root/metric_line.rs" <<'EOF'
pub(crate) fn evaluate_metric_line_with_events<E>(events: &mut E) {
    let _ = events;
    crate::execution::emit_execution_metric_line("metric_name", "");
}
EOF

set +e
metric_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
metric_rc=$?
set -e
[[ $metric_rc -ne 0 ]] || fail "metric-line emission should fail graybox lint"
echo "$metric_out" | grep -Fq "metric-line emission" || fail "missing metric-line diagnostic"
echo "$metric_out" | grep -Fq "evaluate_metric_line_with_events" || fail "missing function name in diagnostic"
pass "metric-line emission fails lint"

rm -f "$space_root/metric_line.rs"
cat > "$space_root/fetch_add.rs" <<'EOF'
pub(crate) fn evaluate_counter_with_events<E>(events: &mut E) {
    let _ = events;
    SOME_COUNTER.fetch_add(1, Ordering::Relaxed);
}
EOF

set +e
counter_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
counter_rc=$?
set -e
[[ $counter_rc -ne 0 ]] || fail "fetch_add should fail graybox lint"
echo "$counter_out" | grep -Fq "global counter mutation" || fail "missing fetch_add diagnostic"
echo "$counter_out" | grep -Fq "evaluate_counter_with_events" || fail "missing function name in fetch_add diagnostic"
pass "fetch_add fails lint"
