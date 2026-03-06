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

fixture_file="$tmp_dir/literal_prompt_fixture.rs"
marker_file="$tmp_dir/prompt_eval_marker.txt"
prompt_capture="$tmp_dir/prompt_capture.txt"

cat > "$fixture_file" <<EOF
fn literal_prompt_fixture() {}
// This token must survive into the review prompt as plain text.
\$(echo prompt_eval > "$marker_file")
EOF

cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
cat > "${TEST_PROMPT_CAPTURE:?missing TEST_PROMPT_CAPTURE}"
echo "src/mock_prompt_literal.rs:1"
exit 0
EOF
chmod +x "$mock_bin/codex"

story="S9-PROMPT-LITERALIZATION"
out_root="$tmp_dir/out"

PATH="$mock_bin:$PATH" \
TEST_PROMPT_CAPTURE="$prompt_capture" \
bash "$SCRIPT" "$story" \
  --tool codex \
  --files "$fixture_file" \
  --prompt generic \
  --timeout-seconds 0 \
  --out-root "$out_root" \
  --title "fixture prompt literalization" >/dev/null

review_file="$out_root/$story/codex/codex.generic.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"
[[ -f "$prompt_capture" ]] || fail "missing prompt capture: $prompt_capture"
[[ ! -f "$marker_file" ]] || fail "prompt construction executed literal command substitution"

expected_literal="\$(echo prompt_eval > \"$marker_file\")"
grep -Fq -- "$expected_literal" "$prompt_capture" || fail "prompt capture did not preserve literal command substitution"
grep -Fq -- "src/mock_prompt_literal.rs:1" "$review_file" || fail "mock citation missing from review artifact"

echo "test_review_logged_prompt_literalization.sh: ok"
