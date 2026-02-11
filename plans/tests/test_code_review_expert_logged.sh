#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/code_review_expert_logged.sh"

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
  if ! printf '%s\n' "$output" | grep -Fq -- "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story="S1-TEST"
out_root="$tmp_dir/out"
head_sha="$(git -C "$ROOT" rev-parse HEAD)"

out="$("$SCRIPT" "$story" --head "$head_sha" --out-root "$out_root")"
review_file="$(printf '%s\n' "$out" | sed -n 's/^Saved code-review-expert artifact: //p' | tail -n 1)"

[[ -n "$review_file" && -f "$review_file" ]] || fail "review artifact missing in $out_root/$story/code_review_expert"

grep -Fxq -- "- Story: $story" "$review_file" || fail "missing story metadata"
grep -Fxq -- "- HEAD: $head_sha" "$review_file" || fail "missing HEAD metadata"
grep -Fq -- "Skill Path: ~/.agents/skills/code-review-expert/SKILL.md" "$review_file" || fail "missing skill-path metadata"
grep -Fxq -- "- Review Status: DRAFT" "$review_file" || fail "default review status should be DRAFT"

input_file="$tmp_dir/input.md"
cat > "$input_file" <<'INPUT'
- Blocking: none
- Major: add regression test for gate
INPUT

out2="$("$SCRIPT" "$story" --head "$head_sha" --status COMPLETE --out-root "$out_root" --from-file "$input_file")"
latest_file="$(printf '%s\n' "$out2" | sed -n 's/^Saved code-review-expert artifact: //p' | tail -n 1)"
[[ -n "$latest_file" && -f "$latest_file" ]] || fail "missing second review artifact"
grep -Fq -- "add regression test for gate" "$latest_file" || fail "missing imported findings content"
grep -Fxq -- "- Review Status: COMPLETE" "$latest_file" || fail "missing COMPLETE status metadata"

out3="$(printf '%s\n' "- Blocking: stdin check" | "$SCRIPT" "$story" --head "$head_sha" --out-root "$out_root" --from-stdin)"
stdin_file="$(printf '%s\n' "$out3" | sed -n 's/^Saved code-review-expert artifact: //p' | tail -n 1)"
[[ -n "$stdin_file" && -f "$stdin_file" ]] || fail "missing stdin review artifact"
grep -Fq -- "stdin check" "$stdin_file" || fail "missing stdin findings content"

expect_fail "mixed content sources" "choose only one content source" \
  "$SCRIPT" "$story" --head "$head_sha" --out-root "$out_root" --from-file "$input_file" --from-stdin

expect_fail "invalid status" "--status must be DRAFT or COMPLETE" \
  "$SCRIPT" "$story" --head "$head_sha" --status BROKEN --out-root "$out_root"

expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: code-review-expert logger fixtures"
