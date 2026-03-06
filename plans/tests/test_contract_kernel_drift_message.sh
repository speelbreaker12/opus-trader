#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
mkdir -p \
  "$fixture/docs/architecture" \
  "$fixture/specs" \
  "$fixture/scripts"

cp "$ROOT/scripts/build_contract_kernel.py" "$fixture/scripts/"
cp "$ROOT/scripts/check_contract_kernel.py" "$fixture/scripts/"
cp "$ROOT/scripts/contract_kernel_lib.py" "$fixture/scripts/"

cat > "$fixture/docs/architecture/contract_anchors.md" <<'EOF'
## Anchor-001: Example Anchor (Contract §1.0)
EOF

cat > "$fixture/docs/architecture/validation_rules.md" <<'EOF'
## VR-001: Example Rule
**Contract ref:** CONTRACT.md §1.0
**Rule:** Example rule.
**Gate ID:** VR-001a
EOF

cat > "$fixture/specs/CONTRACT.md" <<'EOF'
# **Version: 1.0**

## §1.0 Example
Kernel drift example.
EOF

cat > "$fixture/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# Implementation Plan

Minimal fixture plan.
EOF

(cd "$fixture" && python3 scripts/build_contract_kernel.py --out "$fixture/docs/contract_kernel.json")

cat > "$fixture/specs/CONTRACT.md" <<'EOF'
# **Version: 1.0**

## §1.0 Example
Kernel drift example.

Stale contract change.
EOF

stdout_log="$tmp_dir/stdout.log"
stderr_log="$tmp_dir/stderr.log"

if (cd "$fixture" && python3 scripts/check_contract_kernel.py --kernel "$fixture/docs/contract_kernel.json" \
    >"$stdout_log" 2>"$stderr_log"); then
  fail "expected stale contract kernel check to fail"
fi

grep -Fq 'sources.contract_sha256 mismatch' "$stderr_log" \
  || fail "expected contract sha mismatch message"
grep -Fq 'python3 scripts/build_contract_kernel.py --out docs/contract_kernel.json' "$stderr_log" \
  || fail "expected rebuild remediation command"

echo "PASS: contract kernel drift remediation message"
