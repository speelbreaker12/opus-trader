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

# Codex should fail closed on timeout (no fallback path in current workflow).
cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
sleep 2
exit 0
EOF
chmod +x "$mock_bin/codex"

story="S9-TIMEOUT-FAILCLOSED-CODEX"
out_root="$tmp_dir/out"

set +e
PATH="$mock_bin:$PATH" \
bash "$SCRIPT" "$story" \
  --tool codex \
  --files "plans/review_logged.sh" \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout fail-closed codex" >/dev/null 2>&1
rc=$?
set -e

review_file="$out_root/$story/codex/codex.enriched.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"
[[ "$rc" -eq 7 ]] || fail "expected timeout hard-gate exit 7, got $rc"

grep -Fq -- "- Timeout Seconds: 1" "$review_file" || fail "timeout metadata missing"
grep -Fq -- "- Timed Out: true" "$review_file" || fail "timed_out marker missing"
grep -Fq -- "HARD_GATE: REVIEW_COMMAND_TIMEOUT (exit 7)" "$review_file" || fail "timeout hard-gate marker missing"

echo "test_review_logged_timeout_fallback.sh: ok"
