#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/lint_execution_facade.sh"

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

mod_file="$tmp_dir/mod.rs"
api_file="$tmp_dir/api.rs"
allowlist_file="$tmp_dir/execution_facade_symbols.txt"
scan_root="$tmp_dir/crates"

mkdir -p "$scan_root/soldier_core/src/execution"
mkdir -p "$scan_root/soldier_core/src/consumer"

cat > "$scan_root/soldier_core/src/consumer/facade_only.rs" <<'EOF'
use crate::execution::Side;
EOF

cat > "$mod_file" <<'EOF'
mod api;
pub use api::*;
EOF

cat > "$api_file" <<'EOF'
pub use super::foo::{
    Alpha,
    Beta,
};
pub use super::bar::Gamma;
EOF

cat > "$allowlist_file" <<'EOF'
Alpha
Beta
Gamma
EOF

# 1) Exact set should pass.
LINT_EXECUTION_FACADE_MOD="$mod_file" \
LINT_EXECUTION_FACADE_API="$api_file" \
LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
bash "$SCRIPT" >/dev/null
pass "exact facade export set passes"

# 1a) Public api module declaration must fail (semver leak guard).
cat > "$mod_file" <<'EOF'
pub mod api;
pub use api::*;
EOF

set +e
public_mod_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  bash "$SCRIPT" 2>&1
)"
public_mod_rc=$?
set -e
[[ $public_mod_rc -ne 0 ]] || fail "public api module declaration should fail facade lint"
echo "$public_mod_out" | grep -Fq "must not expose 'pub mod api;'" || fail "missing public-module diagnostic"
pass "public api module declaration fails facade lint"

# Restore private module fixture for subsequent checks.
cat > "$mod_file" <<'EOF'
mod api;
pub use api::*;
EOF

# 1b) Nested grouped re-exports should also pass.
cat > "$api_file" <<'EOF'
pub use super::foo::{nested::{Alpha, Beta}, Gamma};
EOF

LINT_EXECUTION_FACADE_MOD="$mod_file" \
LINT_EXECUTION_FACADE_API="$api_file" \
LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
bash "$SCRIPT" >/dev/null
pass "nested grouped facade export set passes"

# 1c) Nested-module pub use should fail (facade only allows top-level re-exports).
cat > "$api_file" <<'EOF'
pub use super::foo::Alpha;
mod hidden {
    pub use super::foo::Beta;
}
pub use super::bar::Gamma;
EOF

set +e
nested_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  bash "$SCRIPT" 2>&1
)"
nested_rc=$?
set -e
[[ $nested_rc -ne 0 ]] || fail "nested-module pub use should fail exact-set lint"
echo "$nested_out" | grep -Fq "non-top-level pub use" || fail "missing nested-module diagnostic"
pass "nested-module pub use fails exact-set lint"

# 2) Extra export in api.rs not present in allowlist must fail.
cat > "$api_file" <<'EOF'
pub use super::foo::{
    Alpha,
    Beta,
    Surprise,
};
pub use super::bar::Gamma;
EOF

set +e
extra_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  bash "$SCRIPT" 2>&1
)"
extra_rc=$?
set -e
[[ $extra_rc -ne 0 ]] || fail "extra export should fail exact-set lint"
echo "$extra_out" | grep -Fq "non-allowlisted exports present" || fail "missing extra-export diagnostic"
echo "$extra_out" | grep -Fq "Surprise" || fail "extra symbol should be named in diagnostic"
pass "extra export fails exact-set lint"

# 3) Missing allowlisted export from api.rs must fail.
cat > "$api_file" <<'EOF'
pub use super::foo::Alpha;
pub use super::bar::Gamma;
EOF

set +e
missing_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  bash "$SCRIPT" 2>&1
)"
missing_rc=$?
set -e
[[ $missing_rc -ne 0 ]] || fail "missing export should fail exact-set lint"
echo "$missing_out" | grep -Fq "allowlisted exports missing" || fail "missing missing-export diagnostic"
echo "$missing_out" | grep -Fq "Beta" || fail "missing symbol should be named in diagnostic"
pass "missing export fails exact-set lint"

# 4) Deep execution import outside execution internals must fail.
cat > "$api_file" <<'EOF'
pub use super::foo::{
    Alpha,
    Beta,
};
pub use super::bar::Gamma;
EOF

cat > "$scan_root/soldier_core/src/consumer/deep_import.rs" <<'EOF'
use crate::execution::gate::LiquidityGateInput;
EOF

set +e
deep_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  bash "$SCRIPT" 2>&1
)"
deep_rc=$?
set -e
[[ $deep_rc -ne 0 ]] || fail "deep execution import should fail lint"
echo "$deep_out" | grep -Fq "deep execution imports are forbidden" || fail "missing deep-import diagnostic"
echo "$deep_out" | grep -Fq "consumer/deep_import.rs" || fail "deep-import location should be reported"
pass "deep execution import fails lint"

echo "PASS: lint_execution_facade exact-set fixtures"
