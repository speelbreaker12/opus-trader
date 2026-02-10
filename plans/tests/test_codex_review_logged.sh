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
review_count=0
latest_review=""
while IFS= read -r f; do
  [[ -n "$f" ]] || continue
  review_count=$((review_count + 1))
  latest_review="$f"
done < <(find "$out_root/$story/codex" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort)
[[ "$review_count" -ge 2 ]] || fail "expected at least two codex review artifacts; found $review_count"
[[ -n "$latest_review" && -f "$latest_review" ]] || fail "missing second review artifact"
[[ "$latest_review" != "$review_file" ]] || fail "latest review artifact should differ from first artifact"
grep -Fq -- "--model o3" "$latest_review" || fail "extra args were not recorded"

# Default out-root should honor STORY_ARTIFACTS_ROOT when set.
story_root="$tmp_dir/story_root"
default_story="S1-STORY-ROOT"
PATH="$mock_bin:$PATH" STORY_ARTIFACTS_ROOT="$story_root" "$SCRIPT" "$default_story" --commit HEAD --title "fixture codex story root" >/dev/null
default_file="$(find "$story_root/$default_story/codex" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$default_file" && -f "$default_file" ]] || fail "default out-root did not honor STORY_ARTIFACTS_ROOT"

# Missing story id must fail.
expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: codex review logger fixtures"
