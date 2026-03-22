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

# Known limitation:
# The lint scans *_with_events bodies after sanitization. Indirect helper calls
# outside those bodies are still a review concern and must stay documented here.

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

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root"$' \n'"$plain_root"$'  ' bash "$SCRIPT" >/dev/null
pass "newline-delimited multi-root scan trims accidental surrounding whitespace"

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

cat > "$space_root/tracing_warn_braces.rs" <<'EOF'
pub(crate) fn evaluate_warn_braces_with_events<E>(events: &mut E) {
    let _ = events;
    tracing::warn!{ "graybox seam should stay telemetry-pure" }
}
EOF

set +e
tracing_braces_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
tracing_braces_rc=$?
set -e
[[ $tracing_braces_rc -ne 0 ]] || fail "brace-style tracing macros should fail graybox lint"
echo "$tracing_braces_out" | grep -Fq "direct tracing macro" || fail "missing brace-style tracing diagnostic"
echo "$tracing_braces_out" | grep -Fq "evaluate_warn_braces_with_events" || fail "missing function name in brace-style tracing diagnostic"
pass "brace-style tracing macros fail lint"

rm -f "$space_root/tracing_warn_braces.rs"

cat > "$space_root/tracing_warn_brackets.rs" <<'EOF'
pub(crate) fn evaluate_warn_brackets_with_events<E>(events: &mut E) {
    let _ = events;
    tracing::warn![ "graybox seam should stay telemetry-pure" ]
}
EOF

set +e
tracing_brackets_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
tracing_brackets_rc=$?
set -e
[[ $tracing_brackets_rc -ne 0 ]] || fail "bracket-style tracing macros should fail graybox lint"
echo "$tracing_brackets_out" | grep -Fq "direct tracing macro" || fail "missing bracket-style tracing diagnostic"
echo "$tracing_brackets_out" | grep -Fq "evaluate_warn_brackets_with_events" || fail "missing function name in bracket-style tracing diagnostic"
pass "bracket-style tracing macros fail lint"

rm -f "$space_root/tracing_warn_brackets.rs"

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

cat > "$space_root/trait_decl.rs" <<'EOF'
trait Demo {
    fn probe_with_events<E>(&mut self, events: &mut E);
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" >/dev/null
pass "declaration-only *_with_events signatures stay allowed"

rm -f "$space_root/trait_decl.rs"

cat > "$space_root/local_record_method.rs" <<'EOF'
struct Metrics;

impl Metrics {
    fn record_wal_nonblocking_allowed(&mut self) {}
}

pub(crate) fn evaluate_local_metrics_with_events<E>(events: &mut E, metrics: &mut Metrics) {
    let _ = events;
    metrics.record_wal_nonblocking_allowed();
}
EOF

set +e
local_record_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
local_record_rc=$?
set -e
[[ $local_record_rc -ne 0 ]] || fail "inline metrics.record_* calls should fail graybox lint"
echo "$local_record_out" | grep -Fq "instance metric mutation" || fail "missing local metrics diagnostic"
echo "$local_record_out" | grep -Fq "evaluate_local_metrics_with_events" || fail "missing function name in local metrics diagnostic"
pass "inline metrics.record_* calls fail lint"

rm -f "$space_root/local_record_method.rs"

cat > "$space_root/wrapper_call.rs" <<'EOF'
struct Input;
struct Metrics;
struct Events;

pub(crate) fn check_post_only(_input: &Input, _metrics: &mut Metrics) {}
pub(crate) fn check_post_only_with_events(_input: &Input, _metrics: &mut Metrics, _events: &mut Events) {}

pub(crate) fn evaluate_preflight_with_events<E>(events: &mut E) {
    let _ = events;
    let input = Input;
    let mut metrics = Metrics;
    check_post_only(&input, &mut metrics);
}
EOF

set +e
wrapper_call_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
wrapper_call_rc=$?
set -e
[[ $wrapper_call_rc -ne 0 ]] || fail "wrapper calls that bypass *_with_events should fail graybox lint"
echo "$wrapper_call_out" | grep -Fq "wrapper call bypassing sink seam" || fail "missing wrapper-call diagnostic"
echo "$wrapper_call_out" | grep -Fq "evaluate_preflight_with_events" || fail "missing function name in wrapper-call diagnostic"
pass "wrapper calls bypassing *_with_events fail lint"

rm -f "$space_root/wrapper_call.rs"

cat > "$space_root/direct_bump.rs" <<'EOF'
pub(crate) fn evaluate_bump_with_events<E>(events: &mut E) {
    let _ = events;
    bump_post_only_reject();
}
EOF

set +e
bump_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
bump_rc=$?
set -e
[[ $bump_rc -ne 0 ]] || fail "direct bump_* calls should fail graybox lint"
echo "$bump_out" | grep -Fq "wrapper-only bump helper call" || fail "missing bump helper diagnostic"
echo "$bump_out" | grep -Fq "evaluate_bump_with_events" || fail "missing function name in bump helper diagnostic"
pass "direct bump_* calls fail lint"

rm -f "$space_root/direct_bump.rs"

cat > "$space_root/local_bump_method.rs" <<'EOF'
pub(crate) fn evaluate_local_bump_with_events<E>(events: &mut E) {
    let _ = events;
    metrics.bump_rejects();
}
EOF

LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" >/dev/null
pass "local bump_* method calls stay allowed"

rm -f "$space_root/local_bump_method.rs"

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

rm -f "$space_root/fetch_add.rs"

cat > "$space_root/trace_ids.rs" <<'EOF'
pub(crate) fn evaluate_trace_context_with_events<E>(events: &mut E) {
    let _ = events;
    with_intent_trace_ids("intent", "run", || {});
}
EOF

set +e
trace_ids_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
trace_ids_rc=$?
set -e
[[ $trace_ids_rc -ne 0 ]] || fail "with_intent_trace_ids should fail graybox lint"
echo "$trace_ids_out" | grep -Fq "trace-id dependency" || fail "missing trace-id diagnostic"
echo "$trace_ids_out" | grep -Fq "evaluate_trace_context_with_events" || fail "missing function name in trace-id diagnostic"
pass "with_intent_trace_ids fails lint"

rm -f "$space_root/trace_ids.rs"

cat > "$space_root/metrics_lock.rs" <<'EOF'
pub(crate) fn evaluate_metrics_lock_with_events<E>(events: &mut E) {
    let _ = events;
    let _guard = METRICS_TEST_LOCK.lock().unwrap();
}
EOF

set +e
metrics_lock_out="$(LINT_GRAYBOX_TELEMETRY_ROOTS="$space_root" bash "$SCRIPT" 2>&1)"
metrics_lock_rc=$?
set -e
[[ $metrics_lock_rc -ne 0 ]] || fail "METRICS_TEST_LOCK should fail graybox lint"
echo "$metrics_lock_out" | grep -Fq "shared metrics lock dependency" || fail "missing METRICS_TEST_LOCK diagnostic"
echo "$metrics_lock_out" | grep -Fq "evaluate_metrics_lock_with_events" || fail "missing function name in METRICS_TEST_LOCK diagnostic"
pass "METRICS_TEST_LOCK fails lint"
