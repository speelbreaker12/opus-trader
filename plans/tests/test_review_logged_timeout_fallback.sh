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
tools_bin="$tmp_dir/tools"
mkdir -p "$mock_bin"
mkdir -p "$tools_bin"

link_tool() {
  local name="$1"
  local resolved
  resolved="$(command -v "$name" 2>/dev/null || true)"
  [[ -n "$resolved" ]] || fail "required tool not found on host: $name"
  ln -s "$resolved" "$tools_bin/$name"
}

required_tools=(
  awk
  bash
  cat
  cp
  cut
  date
  dirname
  git
  grep
  head
  jq
  ln
  mkdir
  mktemp
  pwd
  rm
  sed
  sleep
  sort
  tee
  tr
  true
  wc
)
for tool_name in "${required_tools[@]}"; do
  link_tool "$tool_name"
done
if command -v shasum >/dev/null 2>&1; then
  link_tool "shasum"
elif command -v sha256sum >/dev/null 2>&1; then
  link_tool "sha256sum"
else
  fail "required hash tool missing: shasum or sha256sum"
fi

# First attempt (codex review) times out; fallback (codex exec) succeeds.
cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

mode="${1:-}"
if [[ "$mode" == "review" ]]; then
  sleep 2
  exit 0
fi
if [[ "$mode" == "exec" ]]; then
  # Do not drain full stdin prompt here; large prompts + tight timeout windows
  # can make this fixture flaky under parallel preflight load.
  read -r _ || true
  echo "src/mock_timeout_fallback.rs:42"
  exit 0
fi

echo "unexpected codex mode: $*" >&2
exit 2
EOF
chmod +x "$mock_bin/codex"

cat > "$mock_bin/gtimeout" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

limit="${1:-}"
shift || true
[[ -n "$limit" ]] || exit 2

"$@" &
cmd_pid="$!"
(
  sleep "$limit"
  kill -TERM "$cmd_pid" 2>/dev/null || true
  sleep 0.1
  kill -KILL "$cmd_pid" 2>/dev/null || true
) &
watchdog_pid="$!"

set +e
wait "$cmd_pid"
rc="$?"
set -e

kill "$watchdog_pid" 2>/dev/null || true
wait "$watchdog_pid" 2>/dev/null || true

case "$rc" in
  143|137) exit 124 ;;
  *) exit "$rc" ;;
esac
EOF
chmod +x "$mock_bin/gtimeout"

story="S9-TIMEOUT-FALLBACK"
out_root="$tmp_dir/out"
test_path="$mock_bin:$tools_bin"

PATH="$test_path" command -v timeout >/dev/null 2>&1 && fail "timeout must be absent from fixture PATH"
PATH="$test_path" command -v gtimeout >/dev/null 2>&1 || fail "gtimeout shim must be present in fixture PATH"

PATH="$test_path" \
CODEX_MODEL="GPT-5.3-Codex" \
/bin/bash "$SCRIPT" "$story" \
  --tool codex \
  --commit HEAD \
  --timeout-seconds 1 \
  --out-root "$out_root" \
  --title "fixture timeout fallback" >/dev/null

review_file="$out_root/$story/codex/codex.enriched.md"
[[ -f "$review_file" ]] || fail "missing review artifact: $review_file"

grep -Fq -- "- Timeout Triggered: true" "$review_file" || fail "timeout trigger metadata missing"
grep -Fq -- "- Timeout Fallback Kind: codex_exec_after_timeout" "$review_file" || fail "fallback kind metadata missing"
grep -Fq -- "- Initial Command: codex review" "$review_file" || fail "initial command metadata missing"
grep -Fq -- "- Command: codex exec --model gpt-5-codex" "$review_file" || fail "fallback command/model not recorded"
grep -Fq -- "- Model: gpt-5-codex" "$review_file" || fail "model normalization not applied"
grep -Fq -- "src/mock_timeout_fallback.rs:42" "$review_file" || fail "fallback transcript citation missing"

echo "test_review_logged_timeout_fallback.sh: ok"
