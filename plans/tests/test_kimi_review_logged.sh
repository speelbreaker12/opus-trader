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

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

extract_transcript() {
  local file="$1"
  local out="$2"
  awk '
    /^<<<REVIEW_TRANSCRIPT_BEGIN>>>$/ {capture=1; next}
    /^<<<REVIEW_TRANSCRIPT_END>>>$/ {capture=0; exit}
    capture {print}
  ' "$file" > "$out"
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
grep -Fxq -- "- Repo HEAD: $head_sha" "$review_file" || fail "missing repo HEAD metadata"
grep -Fxq -- "- Model: k2.5" "$review_file" || fail "missing default model metadata"
grep -Fxq -- "- Artifact Provenance: logger-v1" "$review_file" || fail "missing provenance metadata"
grep -Fxq -- "- Generator Script: plans/kimi_review_logged.sh" "$review_file" || fail "missing generator metadata"
grep -Fxq -- "- Command Exit Code: 0" "$review_file" || fail "missing command exit metadata"
grep -Eq '^- Transcript SHA256: [0-9a-f]{64}$' "$review_file" || fail "missing transcript hash metadata"
grep -Fxq -- "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "$review_file" || fail "missing transcript begin marker"
grep -Fxq -- "<<<REVIEW_TRANSCRIPT_END>>>" "$review_file" || fail "missing transcript end marker"
grep -Fq -- "MOCK_KIMI_REVIEW_OK" "$review_file" || fail "missing mock CLI output in artifact"

expected_hash="$(sed -n 's/^- Transcript SHA256: //p' "$review_file" | head -n 1)"
transcript_file="$tmp_dir/kimi_transcript.txt"
extract_transcript "$review_file" "$transcript_file"
actual_hash="$(sha256_file "$transcript_file")"
[[ "$actual_hash" == "$expected_hash" ]] || fail "transcript hash mismatch (expected=$expected_hash actual=$actual_hash)"

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

# Commit metadata must reflect resolved commit SHA (not always repo HEAD).
prior_commit="$(git -C "$ROOT" rev-parse HEAD~1)"
commit_story="S1-COMMIT-REF"
PATH="$mock_bin:$PATH" "$SCRIPT" "$commit_story" --commit HEAD~1 --out-root "$out_root" --title "fixture kimi commit ref" >/dev/null
commit_file="$(find "$out_root/$commit_story/kimi" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$commit_file" && -f "$commit_file" ]] || fail "commit-ref review artifact missing"
grep -Fxq -- "- Repo HEAD: $head_sha" "$commit_file" || fail "commit-ref metadata missing repo HEAD"
grep -Fxq -- "- HEAD: $prior_commit" "$commit_file" || fail "commit-ref metadata missing resolved commit SHA"
grep -Fxq -- "- Reviewed commit SHA: $prior_commit" "$commit_file" || fail "commit-ref metadata missing reviewed SHA"

# Default out-root should honor STORY_ARTIFACTS_ROOT when set.
story_root="$tmp_dir/story_root"
default_story="S1-STORY-ROOT"
PATH="$mock_bin:$PATH" STORY_ARTIFACTS_ROOT="$story_root" "$SCRIPT" "$default_story" --commit HEAD --title "fixture kimi story root" >/dev/null
default_file="$(find "$story_root/$default_story/kimi" -maxdepth 1 -type f -name '*_review.md' | head -n 1 || true)"
[[ -n "$default_file" && -f "$default_file" ]] || fail "default out-root did not honor STORY_ARTIFACTS_ROOT"

# Missing story id must fail.
expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: kimi review logger fixtures"
