#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/lint_risk_facade.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mod_file="$tmp_dir/mod.rs"
api_file="$tmp_dir/api.rs"
allowlist_file="$tmp_dir/risk_facade_symbols.txt"
scan_root="$tmp_dir/crates"

mkdir -p "$scan_root/soldier_core/src/risk" "$scan_root/soldier_core/src/consumer"

cat > "$mod_file" <<'EOF'
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

LINT_RISK_FACADE_MOD="$mod_file" \
LINT_RISK_FACADE_API="$api_file" \
LINT_RISK_FACADE_ALLOWLIST="$allowlist_file" \
LINT_RISK_FACADE_SCAN_ROOT="$scan_root" \
bash "$SCRIPT" >/dev/null

cat > "$mod_file" <<'EOF'
pub mod api;
pub use api::*;
EOF

set +e
public_mod_out="$(LINT_RISK_FACADE_MOD="$mod_file" LINT_RISK_FACADE_API="$api_file" LINT_RISK_FACADE_ALLOWLIST="$allowlist_file" bash "$SCRIPT" 2>&1)"
public_mod_rc=$?
set -e
[[ $public_mod_rc -ne 0 ]] || fail "public risk api module declaration should fail facade lint"
echo "$public_mod_out" | grep -Fq "must not expose 'pub mod api;'" || fail "missing public-module diagnostic"

cat > "$mod_file" <<'EOF'
mod api;
pub use api::*;
EOF

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta, Surprise};
pub use super::bar::Gamma;
EOF

set +e
extra_out="$(LINT_RISK_FACADE_MOD="$mod_file" LINT_RISK_FACADE_API="$api_file" LINT_RISK_FACADE_ALLOWLIST="$allowlist_file" LINT_RISK_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
extra_rc=$?
set -e
[[ $extra_rc -ne 0 ]] || fail "extra export should fail risk facade lint"
echo "$extra_out" | grep -Fq "non-allowlisted exports present" || fail "missing extra-export diagnostic"
echo "$extra_out" | grep -Fq "Surprise" || fail "extra symbol should be named in diagnostic"

cat > "$api_file" <<'EOF'
pub use super::foo::{Alpha, Beta};
pub use super::bar::Gamma;
EOF

cat > "$scan_root/soldier_core/src/consumer/deep_import.rs" <<'EOF'
use crate::risk::pending_exposure::PendingExposureBook;
EOF

set +e
deep_out="$(LINT_RISK_FACADE_MOD="$mod_file" LINT_RISK_FACADE_API="$api_file" LINT_RISK_FACADE_ALLOWLIST="$allowlist_file" LINT_RISK_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
deep_rc=$?
set -e
[[ $deep_rc -ne 0 ]] || fail "deep risk import should fail lint"
echo "$deep_out" | grep -Fq "deep risk imports are forbidden" || fail "missing deep-import diagnostic"
echo "$deep_out" | grep -Fq "consumer/deep_import.rs" || fail "deep-import location should be reported"

cat > "$scan_root/soldier_core/src/consumer/deep_import.rs" <<'EOF'
pub(crate) use crate::risk::pending_exposure::PendingExposureBook;
EOF

set +e
deep_restricted_out="$(LINT_RISK_FACADE_MOD="$mod_file" LINT_RISK_FACADE_API="$api_file" LINT_RISK_FACADE_ALLOWLIST="$allowlist_file" LINT_RISK_FACADE_SCAN_ROOT="$scan_root" bash "$SCRIPT" 2>&1)"
deep_restricted_rc=$?
set -e
[[ $deep_restricted_rc -ne 0 ]] || fail "restricted deep risk import should fail lint"
echo "$deep_restricted_out" | grep -Fq "deep risk imports are forbidden" || fail "missing restricted deep-import diagnostic"
echo "$deep_restricted_out" | grep -Fq "consumer/deep_import.rs" || fail "restricted deep-import location should be reported"

echo "PASS: lint_risk_facade fixtures"
