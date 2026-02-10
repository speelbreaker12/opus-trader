#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/codex_review_logged.sh"

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

# Mock codex CLI for deterministic test behavior.
mock_bin="$tmp_dir/bin"
mkdir -p "$mock_bin"
cat > "$mock_bin/codex" <<'EOF'
#!/usr/bin/env bash
echo "MOCK_CODEX_REVIEW_OK $*"
exit 0
EOF
chmod +x "$mock_bin/codex"

story="S1-TEST"
out_root="$tmp_dir/out"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

# Regression check: no extra args must still work under bash 3.2.
PATH="$mock_bin:$PATH" "$SCRIPT" "$story" --commit HEAD --out-root "$out_root" --title "fixture codex review" >/dev/null

review_file="$(find "$out_root/$story/codex" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$review_file" && -f "$review_file" ]] || fail "review artifact missing in $out_root/$story/codex"

grep -Fxq -- "- Story: $story" "$review_file" || fail "missing story metadata"
grep -Fxq -- "- HEAD: $head_sha" "$review_file" || fail "missing HEAD metadata"
grep -Fq -- "MOCK_CODEX_REVIEW_OK" "$review_file" || fail "missing mock CLI output in artifact"

# Extra args path should still execute and be recorded.
PATH="$mock_bin:$PATH" "$SCRIPT" "$story" --commit HEAD --out-root "$out_root" --title "fixture codex review extra" -- --model o3 >/dev/null
latest_review="$(find "$out_root/$story/codex" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r | head -n 1 || true)"
[[ -n "$latest_review" && -f "$latest_review" ]] || fail "missing second review artifact"
grep -Fq -- "--model o3" "$latest_review" || fail "extra args were not recorded"

# Missing story id must fail.
expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: codex review logger fixtures"
