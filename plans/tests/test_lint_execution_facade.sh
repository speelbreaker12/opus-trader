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
engine_file="$tmp_dir/engine.rs"
routing_file="$tmp_dir/routing.rs"

mkdir -p "$scan_root/soldier_core/src/execution"
mkdir -p "$scan_root/soldier_core/src/consumer"

cat > "$engine_file" <<'EOF'
use super::routing::route_open;
EOF

cat > "$routing_file" <<'EOF'
use super::open_runtime::build_open_order_intent_runtime;
use super::pipeline::evaluate_intent_pipeline;
EOF

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
LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
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
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
  bash "$SCRIPT" 2>&1
)"
deep_rc=$?
set -e
[[ $deep_rc -ne 0 ]] || fail "deep execution import should fail lint"
echo "$deep_out" | grep -Fq "deep execution imports are forbidden" || fail "missing deep-import diagnostic"
echo "$deep_out" | grep -Fq "consumer/deep_import.rs" || fail "deep-import location should be reported"
pass "deep execution import fails lint"

# Cleanup deep-import artifact before engine import test to avoid cross-test interference.
rm -f "$scan_root/soldier_core/src/consumer/deep_import.rs"

# 5) engine.rs must not import open_runtime/pipeline, including grouped multiline imports.
cat > "$engine_file" <<'EOF'
use super::{
    open_runtime::{OpenRuntimeInput, build_open_order_intent_runtime},
    pipeline::{IntentPipelineInput, evaluate_intent_pipeline},
};
EOF

set +e
engine_import_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
  bash "$SCRIPT" 2>&1
)"
engine_import_rc=$?
set -e
[[ $engine_import_rc -ne 0 ]] || fail "engine import of open_runtime/pipeline should fail lint"
echo "$engine_import_out" | grep -Fq "engine.rs must not import open_runtime or pipeline" || fail "missing engine import diagnostic"
pass "engine grouped multiline imports fail lint"

# Restore engine fixture for routing-only checks.
cat > "$engine_file" <<'EOF'
use super::routing::{route_open, route_pipeline};
EOF

# 6) routing.rs may own open_runtime/pipeline imports.
cat > "$routing_file" <<'EOF'
use super::{
    open_runtime::{OpenRuntimeInput, build_open_order_intent_runtime},
    pipeline::{IntentPipelineInput, evaluate_intent_pipeline},
};
EOF

LINT_EXECUTION_FACADE_MOD="$mod_file" \
LINT_EXECUTION_FACADE_API="$api_file" \
LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
bash "$SCRIPT" >/dev/null
pass "routing imports of open_runtime and pipeline pass lint"

# 7) non-test execution files other than routing.rs must not import open_runtime/pipeline.
cat > "$scan_root/soldier_core/src/execution/not_routing.rs" <<'EOF'
use super::pipeline::evaluate_intent_pipeline;
EOF

set +e
non_routing_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
  bash "$SCRIPT" 2>&1
)"
non_routing_rc=$?
set -e
[[ $non_routing_rc -ne 0 ]] || fail "non-routing execution import should fail lint"
echo "$non_routing_out" | grep -Fq "only routing.rs may import open_runtime or pipeline" || fail "missing non-routing diagnostic"
echo "$non_routing_out" | grep -Fq "not_routing.rs" || fail "non-routing location should be reported"
pass "non-routing execution imports fail lint"

rm -f "$scan_root/soldier_core/src/execution/not_routing.rs"

# 8) base_gates.rs must not be exempt from the routing-only boundary.
cat > "$scan_root/soldier_core/src/execution/base_gates.rs" <<'EOF'
use super::pipeline::QuantizePipelineInput;
EOF

set +e
base_gates_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
  bash "$SCRIPT" 2>&1
)"
base_gates_rc=$?
set -e
[[ $base_gates_rc -ne 0 ]] || fail "base_gates.rs pipeline import should fail lint"
echo "$base_gates_out" | grep -Fq "only routing.rs may import open_runtime or pipeline" || fail "missing base_gates diagnostic"
echo "$base_gates_out" | grep -Fq "base_gates.rs" || fail "base_gates location should be reported"
pass "base_gates pipeline import fails lint"

rm -f "$scan_root/soldier_core/src/execution/base_gates.rs"

# 9) intent_assembly.rs must not be exempt from the routing-only boundary.
cat > "$scan_root/soldier_core/src/execution/intent_assembly.rs" <<'EOF'
use super::pipeline::evaluate_intent_pipeline;
EOF

set +e
intent_assembly_out="$(
  LINT_EXECUTION_FACADE_MOD="$mod_file" \
  LINT_EXECUTION_FACADE_API="$api_file" \
  LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
  LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
  LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
  LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
  bash "$SCRIPT" 2>&1
)"
intent_assembly_rc=$?
set -e
[[ $intent_assembly_rc -ne 0 ]] || fail "intent_assembly.rs pipeline import should fail lint"
echo "$intent_assembly_out" | grep -Fq "only routing.rs may import open_runtime or pipeline" || fail "missing intent_assembly diagnostic"
echo "$intent_assembly_out" | grep -Fq "intent_assembly.rs" || fail "intent_assembly location should be reported"
pass "intent_assembly pipeline import fails lint"

rm -f "$scan_root/soldier_core/src/execution/intent_assembly.rs"

# 10) test-only execution files remain exempt.
cat > "$scan_root/soldier_core/src/execution/routing_boundary_tests.rs" <<'EOF'
use crate::execution::pipeline::evaluate_intent_pipeline;
EOF

LINT_EXECUTION_FACADE_MOD="$mod_file" \
LINT_EXECUTION_FACADE_API="$api_file" \
LINT_EXECUTION_FACADE_ALLOWLIST="$allowlist_file" \
LINT_EXECUTION_FACADE_SCAN_ROOT="$scan_root" \
LINT_EXECUTION_FACADE_ENGINE="$engine_file" \
LINT_EXECUTION_FACADE_ROUTING="$routing_file" \
bash "$SCRIPT" >/dev/null
pass "test-only execution imports remain exempt"

echo "PASS: lint_execution_facade exact-set fixtures"
