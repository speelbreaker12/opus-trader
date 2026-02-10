#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/kimi_review_logged.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Mock kimi CLI for deterministic test behavior.
mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/kimi" <<'EOF'
#!/usr/bin/env bash
echo "MOCK_KIMI_REVIEW_OK $*"
exit 0
EOF
chmod +x "$mock_bin/kimi"

story="S1-TEST"
out_root="$tmp_dir/out"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

PATH="$mock_bin:$PATH" "$SCRIPT" "$story" --commit HEAD --out-root "$out_root" --title "fixture kimi review" >/dev/null

review_file="$(find "$out_root/$story/kimi" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$review_file" && -f "$review_file" ]] || fail "review artifact missing in $out_root/$story/kimi"

grep -Fxq -- "- Story: $story" "$review_file" || fail "missing story metadata"
grep -Fxq -- "- HEAD: $head_sha" "$review_file" || fail "missing HEAD metadata"
grep -Fxq -- "- Model: k2.5" "$review_file" || fail "missing default model metadata"
grep -Fq -- "MOCK_KIMI_REVIEW_OK" "$review_file" || fail "missing mock CLI output in artifact"

# Fallback path: no `kimi review` subcommand support.
fallback_bin="$tmp_dir/fallback_bin"
mkdir -p "$fallback_bin"
cat > "$fallback_bin/kimi" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "review" ]]; then
  echo "No such command 'review'." >&2
  exit 2
fi
echo "MOCK_KIMI_PRINT_OK $*"
exit 0
EOF
chmod +x "$fallback_bin/kimi"

fallback_story="S1-FALLBACK"
PATH="$fallback_bin:$PATH" "$SCRIPT" "$fallback_story" --commit HEAD --out-root "$out_root" --title "fixture kimi fallback" >/dev/null
fallback_file="$(find "$out_root/$fallback_story/kimi" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$fallback_file" && -f "$fallback_file" ]] || fail "fallback review artifact missing"
grep -Fxq -- "- Command mode: print-prompt" "$fallback_file" || fail "fallback mode metadata missing"
grep -Fq -- "MOCK_KIMI_PRINT_OK" "$fallback_file" || fail "fallback CLI output missing"

# Missing story id must fail.
expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: kimi review logger fixtures"
