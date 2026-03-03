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

# Broken timeout shims should be ignored by timeout_bin().
cat > "$mock_bin/timeout" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$mock_bin/timeout"

cat > "$mock_bin/gtimeout" <<'EOF'
#!/usr/bin/env bash
exit 127
EOF
chmod +x "$mock_bin/gtimeout"

cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
echo "src/mock_no_timeout_bin.rs:10"
exit 0
EOF
chmod +x "$mock_bin/codex"

story="S9-NO-TIMEOUT-BIN"
out_root="$tmp_dir/out"

PATH="$mock_bin:$PATH" \
bash "$SCRIPT" "$story" \
  --tool codex \
  --commit HEAD \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout binary unavailable" >/dev/null

review_file="$out_root/$story/codex/codex.enriched.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"

grep -Fq -- "- Command Exit Code: 0" "$review_file" || fail "review should succeed without timeout binaries"
grep -Fq -- "- Timeout Triggered: false" "$review_file" || fail "timeout should not be marked as triggered"
grep -Fq -- "- Timeout Fallback Kind: none" "$review_file" || fail "fallback kind should remain none"
grep -Fq -- "src/mock_no_timeout_bin.rs:10" "$review_file" || fail "mock citation missing"

# Empty transcripts must fail-closed for findings summary counting.
cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
exit 0
EOF
chmod +x "$mock_bin/codex"

story_empty="S9-EMPTY-TRANSCRIPT"
out_root_empty="$tmp_dir/out-empty"

set +e
PATH="$mock_bin:$PATH" \
bash "$SCRIPT" "$story_empty" \
  --tool codex \
  --commit HEAD \
  --timeout-seconds 1 \
  --out-root "$out_root_empty" \
  --title "fixture empty transcript fail-closed" >/dev/null
empty_rc=$?
set -e
[[ "$empty_rc" -ne 0 ]] || fail "empty transcript should fail citation gate in C1 mode"

empty_review_file="$out_root_empty/$story_empty/codex/codex.enriched.md"
[[ -f "$empty_review_file" ]] || fail "missing empty transcript artifact: $empty_review_file"
grep -Fq -- "FINDINGS_SUMMARY: P0=999 P1=999 P2=999" "$empty_review_file" \
  || fail "empty transcript findings summary must be fail-closed (999)"

echo "test_review_logged_timeout_binary_unavailable.sh: ok"
