#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LINT="$ROOT/plans/artifact_lint.sh"
VERIFY="$ROOT/plans/verify_fork.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$output" | grep -Fq "$pattern" || fail "$label missing expected pattern '$pattern'"
}

write_gate_markers() {
  local out_dir="$1"
  local gate="$2"
  local rc="${3:-0}"

  : > "$out_dir/$gate.log"
  printf '%s\n' "$rc" > "$out_dir/$gate.rc"
  printf '0.1\n' > "$out_dir/$gate.time"
}

[[ -x "$LINT" ]] || fail "missing executable artifact lint script: $LINT"
[[ -f "$VERIFY" ]] || fail "missing verify script: $VERIFY"

# Ensure verify full path invokes strict artifact lint wiring.
grep -Fq 'artifact_lint_cmd=(./plans/artifact_lint.sh --mode "$MODE")' "$VERIFY" \
  || fail "verify_fork missing artifact_lint mode wiring"
grep -Fq 'artifact_lint_cmd+=(--verify-artifacts-dir "$VERIFY_ARTIFACTS_DIR")' "$VERIFY" \
  || fail "verify_fork missing strict verify-artifacts-dir wiring"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

expect_fail "full mode requires verify dir" \
  "full mode requires --verify-artifacts-dir" \
  "$LINT" --mode full

expect_fail "missing verify dir fails" \
  "verify artifacts dir not found" \
  "$LINT" --mode full --verify-artifacts-dir "$tmp_dir/missing"

missing_markers_dir="$tmp_dir/missing_markers"
mkdir -p "$missing_markers_dir"
write_gate_markers "$missing_markers_dir" "preflight" "0"
expect_fail "full mode missing required gate marker fails" \
  "verify artifacts dir missing marker: verify_gate_contract.log" \
  "$LINT" --mode full --verify-artifacts-dir "$missing_markers_dir"

failed_gate_dir="$tmp_dir/failed_gate"
mkdir -p "$failed_gate_dir"
write_gate_markers "$failed_gate_dir" "preflight" "0"
write_gate_markers "$failed_gate_dir" "verify_gate_contract" "0"
: > "$failed_gate_dir/FAILED_GATE"
expect_fail "failed gate marker blocks strict mode" \
  "verify artifacts dir contains FAILED_GATE" \
  "$LINT" --mode full --verify-artifacts-dir "$failed_gate_dir"

nonzero_rc_dir="$tmp_dir/nonzero_rc"
mkdir -p "$nonzero_rc_dir"
write_gate_markers "$nonzero_rc_dir" "preflight" "1"
write_gate_markers "$nonzero_rc_dir" "verify_gate_contract" "0"
expect_fail "non-zero required gate rc blocks strict mode" \
  "verify artifacts dir marker preflight.rc is non-zero: 1" \
  "$LINT" --mode full --verify-artifacts-dir "$nonzero_rc_dir"

valid_dir="$tmp_dir/valid"
mkdir -p "$valid_dir"
write_gate_markers "$valid_dir" "preflight" "0"
write_gate_markers "$valid_dir" "verify_gate_contract" "0"
ok_output="$("$LINT" --mode full --verify-artifacts-dir "$valid_dir")"
printf '%s\n' "$ok_output" | grep -Fq "strict_markers_checked=6" \
  || fail "strict success output missing strict_markers_checked=6"

echo "PASS: artifact_lint strict full-mode coverage"
