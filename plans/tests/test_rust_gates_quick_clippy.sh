#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUST_GATES="$ROOT/plans/lib/rust_gates.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains_line() {
  local needle="$1"
  if ! grep -Fq -- "$needle" "$RUST_GATES"; then
    fail "missing expected rust gates token: $needle"
  fi
}

assert_absent_line() {
  local needle="$1"
  if grep -Fq -- "$needle" "$RUST_GATES"; then
    fail "stale rust gates token still present: $needle"
  fi
}

[[ -f "$RUST_GATES" ]] || fail "missing rust gates script: $RUST_GATES"

assert_contains_line 'log "2b) Rust clippy (full)"'
assert_contains_line 'run_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --all-targets --all-features -- -D warnings'
assert_contains_line 'log "2b) Rust clippy (quick)"'
assert_contains_line 'run_logged_or_exit "rust_clippy" "$RUST_CLIPPY_TIMEOUT" cargo clippy --workspace --lib -- -D warnings'

assert_absent_line 'warn "Skipping clippy in quick mode"'

echo "PASS: rust gates quick clippy wiring"
