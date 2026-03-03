#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"

cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "src/mock_no_timeout_bin.rs:10"
exit 0
EOF
chmod +x "$mock_bin/codex"

story="S9-NO-TIMEOUT-BIN"
out_root="$tmp_dir/out"

set +e
output="$(
PATH="$mock_bin:/usr/bin:/bin" \
bash "$SCRIPT" "$story" \
  --tool codex \
  --files "plans/review_logged.sh" \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout binary unavailable" 2>&1
)"
rc=$?
set -e

review_file="$out_root/$story/codex/codex.enriched.md"
[[ "$rc" -eq 2 ]] || fail "expected missing-timeout-binary exit 2, got $rc"
echo "$output" | grep -Fq -- "ERROR: timeout requested but neither 'timeout' nor 'gtimeout' is available in PATH" \
  || fail "missing timeout-binary-unavailable error"

[[ ! -f "$review_file" ]] || fail "review artifact should not be created when timeout binaries are unavailable"

echo "test_review_logged_timeout_binary_unavailable.sh: ok"
