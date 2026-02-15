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

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

extract_findings() {
  local file="$1"
  local out="$2"
  awk '
    /^<<<FINDINGS_BEGIN>>>$/ {capture=1; next}
    /^<<<FINDINGS_END>>>$/ {capture=0; exit}
    capture {print}
  ' "$file" > "$out"
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
grep -Fxq -- "- Artifact Provenance: logger-v1" "$review_file" || fail "missing provenance metadata"
grep -Fxq -- "- Generator Script: plans/code_review_expert_logged.sh" "$review_file" || fail "missing generator metadata"
grep -Fxq -- "- Content Source: template" "$review_file" || fail "missing template content source metadata"
grep -Eq '^- Findings SHA256: [0-9a-f]{64}$' "$review_file" || fail "missing findings hash metadata"
grep -Fxq -- "<<<FINDINGS_BEGIN>>>" "$review_file" || fail "missing findings begin marker"
grep -Fxq -- "<<<FINDINGS_END>>>" "$review_file" || fail "missing findings end marker"

expected_findings_hash="$(sed -n 's/^- Findings SHA256: //p' "$review_file" | head -n 1)"
findings_file="$tmp_dir/findings_template.txt"
extract_findings "$review_file" "$findings_file"
actual_findings_hash="$(sha256_file "$findings_file")"
[[ "$actual_findings_hash" == "$expected_findings_hash" ]] || fail "template findings hash mismatch"

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
grep -Fxq -- "- Content Source: from-file" "$latest_file" || fail "missing from-file content source metadata"

out3="$(printf '%s\n' "- Blocking: stdin check" | "$SCRIPT" "$story" --head "$head_sha" --out-root "$out_root" --from-stdin)"
stdin_file="$(printf '%s\n' "$out3" | sed -n 's/^Saved code-review-expert artifact: //p' | tail -n 1)"
[[ -n "$stdin_file" && -f "$stdin_file" ]] || fail "missing stdin review artifact"
grep -Fq -- "stdin check" "$stdin_file" || fail "missing stdin findings content"
grep -Fxq -- "- Content Source: from-stdin" "$stdin_file" || fail "missing from-stdin content source metadata"

expect_fail "mixed content sources" "choose only one content source" \
  "$SCRIPT" "$story" --head "$head_sha" --out-root "$out_root" --from-file "$input_file" --from-stdin

expect_fail "invalid status" "--status must be DRAFT or COMPLETE" \
  "$SCRIPT" "$story" --head "$head_sha" --status BROKEN --out-root "$out_root"

expect_fail "missing story id" "Usage:" "$SCRIPT"

echo "PASS: code-review-expert logger fixtures"
