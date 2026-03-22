#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/lint_facade_public_modules.sh"

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

core_root="$tmp_dir/crates/soldier_core/src"
infra_root="$tmp_dir/crates/soldier_infra/src"
core_lib="$core_root/lib.rs"
infra_lib="$infra_root/lib.rs"

mkdir -p "$core_root/execution" "$core_root/idempotency" "$core_root/risk" "$infra_root/store"

cat > "$core_lib" <<'EOF'
pub mod execution;
pub mod idempotency;
pub mod recovery;
pub mod risk;
pub mod status_codes;
pub mod venue;
EOF

cat > "$infra_lib" <<'EOF'
mod api;
pub use api::*;
EOF

set +e
pass_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
pass_rc=$?
set -e
[[ $pass_rc -eq 0 ]] || fail "expected top-level facade pub mods to pass, got: $pass_out"
pass "allowed top-level soldier_core pub mods pass"

cat > "$core_root/idempotency/mod.rs" <<'EOF'
pub mod hash;
EOF

set +e
core_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
core_leak_rc=$?
set -e
[[ $core_leak_rc -ne 0 ]] || fail "unexpected public soldier_core child module should fail"
echo "$core_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_core leak diagnostic"
echo "$core_leak_out" | grep -Fq "crates/soldier_core/src/idempotency/mod.rs:1:pub mod hash;" || fail "soldier_core leak location should be reported"
pass "unexpected soldier_core child pub mod fails"

rm -f "$core_root/idempotency/mod.rs"

cat > "$core_root/idempotency/mod.rs" <<'EOF'
pub mod hash {}
EOF

set +e
core_inline_block_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
core_inline_block_rc=$?
set -e
[[ $core_inline_block_rc -ne 0 ]] || fail "inline public soldier_core child module should fail"
echo "$core_inline_block_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_core inline-block diagnostic"
echo "$core_inline_block_out" | grep -Fq "crates/soldier_core/src/idempotency/mod.rs:1:pub mod hash {" || fail "soldier_core inline-block location should be reported"
pass "inline soldier_core child pub mod fails"

rm -f "$core_root/idempotency/mod.rs"

cat > "$core_root/idempotency/mod.rs" <<'EOF'
#[cfg(test)] pub mod hash;
EOF

set +e
core_attr_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
core_attr_leak_rc=$?
set -e
[[ $core_attr_leak_rc -ne 0 ]] || fail "attribute-prefixed public soldier_core child module should fail"
echo "$core_attr_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_core attribute leak diagnostic"
echo "$core_attr_leak_out" | grep -Fq "crates/soldier_core/src/idempotency/mod.rs:1:#[cfg(test)] pub mod hash;" || fail "soldier_core attribute leak location should be reported"
pass "attribute-prefixed soldier_core child pub mod fails"

rm -f "$core_root/idempotency/mod.rs"

cat > "$core_root/idempotency/mod.rs" <<'EOF'
#[cfg(test)]
pub mod hash;
EOF

set +e
core_multiline_attr_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
core_multiline_attr_leak_rc=$?
set -e
[[ $core_multiline_attr_leak_rc -ne 0 ]] || fail "multiline attribute-prefixed public soldier_core child module should fail"
echo "$core_multiline_attr_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing multiline soldier_core attribute leak diagnostic"
echo "$core_multiline_attr_leak_out" | grep -Fq "crates/soldier_core/src/idempotency/mod.rs:1:#[cfg(test)] pub mod hash;" || fail "multiline soldier_core attribute leak location should be reported"
pass "multiline attribute-prefixed soldier_core child pub mod fails"

rm -f "$core_root/idempotency/mod.rs"

cat > "$infra_root/store/mod.rs" <<'EOF'
pub mod ledger;
EOF

set +e
infra_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
infra_leak_rc=$?
set -e
[[ $infra_leak_rc -ne 0 ]] || fail "unexpected public soldier_infra child module should fail"
echo "$infra_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_infra leak diagnostic"
echo "$infra_leak_out" | grep -Fq "crates/soldier_infra/src/store/mod.rs:1:pub mod ledger;" || fail "soldier_infra leak location should be reported"
pass "unexpected soldier_infra child pub mod fails"

rm -f "$infra_root/store/mod.rs"

cat > "$infra_root/store/mod.rs" <<'EOF'
pub mod ledger {}
EOF

set +e
infra_inline_block_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
infra_inline_block_rc=$?
set -e
[[ $infra_inline_block_rc -ne 0 ]] || fail "inline public soldier_infra child module should fail"
echo "$infra_inline_block_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_infra inline-block diagnostic"
echo "$infra_inline_block_out" | grep -Fq "crates/soldier_infra/src/store/mod.rs:1:pub mod ledger {" || fail "soldier_infra inline-block location should be reported"
pass "inline soldier_infra child pub mod fails"

rm -f "$infra_root/store/mod.rs"

cat > "$infra_root/store/mod.rs" <<'EOF'
#[cfg(test)] pub mod ledger;
EOF

set +e
infra_attr_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
infra_attr_leak_rc=$?
set -e
[[ $infra_attr_leak_rc -ne 0 ]] || fail "attribute-prefixed public soldier_infra child module should fail"
echo "$infra_attr_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing soldier_infra attribute leak diagnostic"
echo "$infra_attr_leak_out" | grep -Fq "crates/soldier_infra/src/store/mod.rs:1:#[cfg(test)] pub mod ledger;" || fail "soldier_infra attribute leak location should be reported"
pass "attribute-prefixed soldier_infra child pub mod fails"

rm -f "$infra_root/store/mod.rs"

cat > "$infra_root/store/mod.rs" <<'EOF'
#[cfg(test)]
pub mod ledger;
EOF

set +e
infra_multiline_attr_leak_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
infra_multiline_attr_leak_rc=$?
set -e
[[ $infra_multiline_attr_leak_rc -ne 0 ]] || fail "multiline attribute-prefixed public soldier_infra child module should fail"
echo "$infra_multiline_attr_leak_out" | grep -Fq "Unexpected public submodules found" || fail "missing multiline soldier_infra attribute leak diagnostic"
echo "$infra_multiline_attr_leak_out" | grep -Fq "crates/soldier_infra/src/store/mod.rs:1:#[cfg(test)] pub mod ledger;" || fail "multiline soldier_infra attribute leak location should be reported"
pass "multiline attribute-prefixed soldier_infra child pub mod fails"

rm -f "$infra_root/store/mod.rs"

cat > "$core_lib" <<'EOF'
pub mod execution;
pub mod risk;
EOF

set +e
missing_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
missing_rc=$?
set -e
[[ $missing_rc -ne 0 ]] || fail "missing allowed top-level facade pub mods should fail"
echo "$missing_out" | grep -Fq "Missing required public facade modules" || fail "missing required-modules diagnostic"
echo "$missing_out" | grep -Fq "crates/soldier_core/src/lib.rs: pub mod idempotency;" || fail "missing module should be named"
pass "missing required top-level soldier_core pub mods fail"

rm -f "$infra_lib"

set +e
missing_infra_out="$(
  LINT_FACADE_PUBLIC_MODULES_ROOT="$tmp_dir" \
  bash "$SCRIPT" 2>&1
)"
missing_infra_rc=$?
set -e
[[ $missing_infra_rc -ne 0 ]] || fail "missing soldier_infra lib should fail closed"
echo "$missing_infra_out" | grep -Fq "missing soldier_infra lib file" || fail "missing soldier_infra diagnostic should be reported"
pass "missing soldier_infra lib fails closed"
