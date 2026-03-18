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
arg_capture="$tmp_dir/base_args_capture.txt"

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

cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$@" > "${TEST_ARG_CAPTURE:?missing TEST_ARG_CAPTURE}"
echo "src/mock_base_review.rs:3"
exit 0
EOF
chmod +x "$mock_bin/codex"

base_story="S9-CODEX-BASE-ARGS"
base_out_root="$tmp_dir/out-base"
base_title="fixture codex base args"

PATH="$mock_bin:$PATH" \
TEST_ARG_CAPTURE="$arg_capture" \
bash "$SCRIPT" "$base_story" \
  --tool codex \
  --base origin/main \
  --timeout-seconds 0 \
  --out-root "$base_out_root" \
  --title "$base_title" >/dev/null

base_review_file="$base_out_root/$base_story/codex/codex.enriched.md"
[[ -f "$base_review_file" ]] || fail "missing base review artifact: $base_review_file"
[[ -f "$arg_capture" ]] || fail "missing base-mode arg capture: $arg_capture"

grep -Fxq -- "review" "$arg_capture" || fail "codex base review should invoke review subcommand"
grep -Fxq -- "--base" "$arg_capture" || fail "codex base review should pass --base"
grep -Fxq -- "origin/main" "$arg_capture" || fail "codex base review should pass base ref"
if grep -Fq -- "Rust fintech trading engine rules:" "$arg_capture"; then
  fail "codex base review must not pass prompt positional arg"
fi
grep -Fq -- "src/mock_base_review.rs:3" "$base_review_file" || fail "base-mode citation missing from review artifact"

echo "test_review_logged_prompt_literalization.sh: ok"
