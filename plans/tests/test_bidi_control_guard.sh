#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/bidi_control_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
mkdir -p "$fixture/src"

cat > "$fixture/src/clean.rs" <<'EOF'
fn clean_example() {
    println!("clean");
}
EOF

BIDI_CONTROL_GUARD_ROOT="$fixture" "$SCRIPT" >/dev/null

mock_bin="$tmp_dir/mock_bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/rg" <<'EOF'
#!/usr/bin/env bash
echo "PCRE2 is not available in this build" >&2
exit 2
EOF
chmod +x "$mock_bin/rg"

# Fallback path: rg exists but -P is unavailable -> perl scanner should still pass on clean input.
PATH="$mock_bin:$PATH" BIDI_CONTROL_GUARD_ROOT="$fixture" "$SCRIPT" >/dev/null

printf 'fn risky() { println!("x \342\200\256 y"); }\n' > "$fixture/src/with_bidi.rs"

set +e
out="$(
  PATH="$mock_bin:$PATH" BIDI_CONTROL_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1
)"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || fail "expected bidi guard to fail when bidi control char exists"
echo "$out" | grep -Fq "FAIL: bidirectional control characters detected" || fail "missing failure banner"
echo "$out" | grep -Fq "src/with_bidi.rs:1" || fail "missing offending file/line diagnostic"
echo "$out" | grep -Fq "falling back to perl scanner" || fail "missing rg->perl fallback warning"

echo "PASS: bidi control guard"
