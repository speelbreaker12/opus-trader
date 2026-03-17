#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/lint_soldier_infra_facade.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

lib_file="$tmp_dir/lib.rs"
api_file="$tmp_dir/api.rs"
allowlist_file="$tmp_dir/soldier_infra_facade_symbols.txt"
scan_root="$tmp_dir"

mkdir -p "$tmp_dir/crates/soldier_infra/src" "$tmp_dir/consumer"

cat > "$lib_file" <<'EOF'
mod api;
pub use api::*;
EOF

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta};
pub use super::bar::Gamma;
EOF

cat > "$allowlist_file" <<'EOF'
Alpha
Beta
Gamma
EOF

LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" \
LINT_SOLDIER_INFRA_FACADE_API="$api_file" \
LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" \
LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" \
bash "$SCRIPT" >/dev/null

cat > "$lib_file" <<'EOF'
pub mod api;
pub use api::*;
EOF

set +e
public_mod_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" bash "$SCRIPT" 2>&1)"
public_mod_rc=$?
set -e
[[ $public_mod_rc -ne 0 ]] || fail "public soldier_infra api module declaration should fail facade lint"
echo "$public_mod_out" | grep -Fq "must not expose 'pub mod api;'" || fail "missing public-module diagnostic"

cat > "$lib_file" <<'EOF'
mod api;
pub use api::*;
EOF

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta, Surprise};
pub use super::bar::Gamma;
EOF

set +e
extra_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
extra_rc=$?
set -e
[[ $extra_rc -ne 0 ]] || fail "extra export should fail soldier_infra facade lint"
echo "$extra_out" | grep -Fq "non-allowlisted exports present" || fail "missing extra-export diagnostic"
echo "$extra_out" | grep -Fq "Surprise" || fail "extra symbol should be named in diagnostic"

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta};
pub use super::bar::Gamma;
EOF

# Nested brace groups must be rejected
cat > "$api_file" <<'EOF'
pub use super::foo::{nested::{Alpha, Beta}, Gamma};
EOF

set +e
nested_brace_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
nested_brace_rc=$?
set -e
[[ $nested_brace_rc -ne 0 ]] || fail "nested brace group should fail soldier_infra facade lint"
echo "$nested_brace_out" | grep -Fq "nested brace groups are not allowed" || fail "missing nested-brace diagnostic"

# Nested-module pub use must be rejected
cat > "$api_file" <<'EOF'
pub use super::foo::Alpha;
mod hidden {
    pub use super::super::foo::Beta;
}
pub use super::bar::Gamma;
EOF

set +e
nested_mod_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
nested_mod_rc=$?
set -e
[[ $nested_mod_rc -ne 0 ]] || fail "nested-module pub use should fail soldier_infra facade lint"
echo "$nested_mod_out" | grep -Fq "non-top-level pub use" || fail "missing nested-module diagnostic"

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta};
pub use super::bar::Gamma;
EOF

cat > "$tmp_dir/consumer/deep_import.rs" <<'EOF'
use soldier_infra::store::WalLedger;
EOF

set +e
deep_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
deep_rc=$?
set -e
[[ $deep_rc -ne 0 ]] || fail "deep soldier_infra import should fail lint"
echo "$deep_out" | grep -Fq "deep soldier_infra imports are forbidden" || fail "missing deep-import diagnostic"
echo "$deep_out" | grep -Fq "consumer/deep_import.rs" || fail "deep-import location should be reported"

cat > "$tmp_dir/consumer/deep_import.rs" <<'EOF'
pub(crate) use soldier_infra::store::WalLedger;
EOF

set +e
deep_restricted_out="$(LINT_SOLDIER_INFRA_FACADE_LIB="$lib_file" LINT_SOLDIER_INFRA_FACADE_API="$api_file" LINT_SOLDIER_INFRA_FACADE_ALLOWLIST="$allowlist_file" LINT_SOLDIER_INFRA_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
deep_restricted_rc=$?
set -e
[[ $deep_restricted_rc -ne 0 ]] || fail "restricted deep soldier_infra import should fail lint"
echo "$deep_restricted_out" | grep -Fq "deep soldier_infra imports are forbidden" || fail "missing restricted deep-import diagnostic"
echo "$deep_restricted_out" | grep -Fq "consumer/deep_import.rs" || fail "restricted deep-import location should be reported"

echo "PASS: lint_soldier_infra_facade fixtures"
