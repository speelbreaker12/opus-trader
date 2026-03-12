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

printf 'fn alm() { println!("x \330\234 y"); }\n' > "$fixture/src/with_alm.rs"

set +e
alm_out="$(
  PATH="$mock_bin:$PATH" BIDI_CONTROL_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1
)"
alm_rc=$?
set -e

[[ "$alm_rc" -ne 0 ]] || fail "expected bidi guard to fail when U+061C exists"
echo "$alm_out" | grep -Fq "src/with_alm.rs:1" || fail "missing U+061C offending file/line diagnostic"

rm -f "$fixture/src/with_bidi.rs" "$fixture/src/with_alm.rs"

real_grep="$(command -v grep)"
cat > "$mock_bin/grep" <<EOF
#!/usr/bin/env bash
set -euo pipefail
if [[ "\${1:-}" == "-Iq" && "\${2:-}" == "." ]]; then
  exit 0
fi
exec "$real_grep" "\$@"
EOF
chmod +x "$mock_bin/grep"

python3 - <<'PY' "$fixture/src/late_nul_binary.bin"
from pathlib import Path
import sys

Path(sys.argv[1]).write_bytes(
    b"A" * 12000 + "\u202e".encode("utf-8") + b"B" * 32 + b"\0tail\n"
)
PY

set +e
binary_out="$(
  PATH="$mock_bin:$PATH" BIDI_CONTROL_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1
)"
binary_rc=$?
set -e

[[ "$binary_rc" -eq 0 ]] || fail "binary files with late NUL bytes must be skipped before bidi scanning"
echo "$binary_out" | grep -Fq "bidi_control_guard: PASS" || fail "binary late-NUL fixture should not trip the bidi guard"

echo "PASS: bidi control guard"
