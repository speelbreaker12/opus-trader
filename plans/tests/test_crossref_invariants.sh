#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VALIDATOR="$ROOT/plans/validate_crossref_invariants.py"
INVARIANTS="$ROOT/plans/crossref_execution_invariants.yaml"
SCHEMA="$ROOT/plans/schemas/crossref_execution_invariants.schema.json"
BURNIN="$ROOT/plans/crossref_burnin_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_rc() {
  local expected_rc="$1"
  shift

  set +e
  "$@" >"$tmp_dir/out.txt" 2>"$tmp_dir/err.txt"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$tmp_dir/out.txt" >&2 || true
    echo "stderr:" >&2
    cat "$tmp_dir/err.txt" >&2 || true
    fail "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -f "$VALIDATOR" ]] || fail "missing validator: $VALIDATOR"
[[ -f "$INVARIANTS" ]] || fail "missing invariants: $INVARIANTS"
[[ -f "$SCHEMA" ]] || fail "missing schema: $SCHEMA"
[[ -x "$BURNIN" ]] || fail "burn-in checker not executable: $BURNIN"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

expect_rc 0 python3 "$VALIDATOR" --invariants "$INVARIANTS" --schema "$SCHEMA"

# Semantic failure: required workflow step missing.
bad_inv="$tmp_dir/bad_invariants.yaml"
cp "$INVARIANTS" "$bad_inv"
sed -i.bak '/- pr_gate_wait/d' "$bad_inv"
rm -f "$bad_inv.bak"
expect_rc 3 python3 "$VALIDATOR" --invariants "$bad_inv" --schema "$SCHEMA"

# Schema/parse failure.
malformed_inv="$tmp_dir/malformed.yaml"
cat > "$malformed_inv" <<'EOF_MALFORMED'
not: [valid
EOF_MALFORMED
expect_rc 2 python3 "$VALIDATOR" --invariants "$malformed_inv" --schema "$SCHEMA"

# Burn-in eligibility checker pass/fail behavior.
burnin_out="$tmp_dir/burnin.json"
expect_rc 0 "$BURNIN" \
  --clean-merge-count 2 \
  --unexplained-drift-count 0 \
  --unknown-gap-count 0 \
  --out "$burnin_out"
[[ -f "$burnin_out" ]] || fail "missing burn-in output artifact"
grep -Fq '"eligible": true' "$burnin_out" || fail "expected eligible=true"

expect_rc 1 "$BURNIN" \
  --clean-merge-count 1 \
  --unexplained-drift-count 0 \
  --unknown-gap-count 0

echo "PASS: crossref invariants"
