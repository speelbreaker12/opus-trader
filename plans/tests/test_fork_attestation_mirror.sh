#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/fork_attestation_mirror.sh"
VERIFY_SCRIPT="$ROOT/plans/fork_attestation_remediation_verify.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local out=""
  set +e
  out="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$out" | grep -Fq "$pattern" || fail "$label missing expected pattern '$pattern'"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
[[ -x "$VERIFY_SCRIPT" ]] || fail "missing executable verifier: $VERIFY_SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pr=29
story_id="WF-004"
mirror_branch="mirror/pr-29"
attestation_sha="89abcdef0123456789abcdef0123456789abcdef"
mirror_head_sha="$(git -C "$ROOT" rev-parse HEAD)"
out_file="$tmp_dir/pr_${pr}.json"

write_output="$(
  cd "$ROOT" && \
  "$SCRIPT" \
    --pr "$pr" \
    --story "$story_id" \
    --mirror-branch "$mirror_branch" \
    --mirror-head "$mirror_head_sha" \
    --attestation-commit "$attestation_sha" \
    --actor "owner" \
    --out "$out_file"
)"
printf '%s\n' "$write_output" | grep -Fq "Wrote fork remediation metadata" || fail "missing write output"
[[ -f "$out_file" ]] || fail "metadata file was not written"

jq -e --arg story "$story_id" '.story_id == $story' "$out_file" >/dev/null || fail "story_id mismatch"
jq -e --arg branch "$mirror_branch" '.mirror_branch == $branch' "$out_file" >/dev/null || fail "mirror_branch mismatch"
jq -e --arg sha "$mirror_head_sha" '.mirror_head_sha == $sha' "$out_file" >/dev/null || fail "mirror_head_sha mismatch"
jq -e --arg sha "$attestation_sha" '.attestation_commit_sha == $sha' "$out_file" >/dev/null || fail "attestation sha mismatch"
jq -e '.schema_version == 1' "$out_file" >/dev/null || fail "schema version mismatch"
jq -e '.remediated_at_utc | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T")' "$out_file" >/dev/null || fail "remediated_at_utc format mismatch"

"$VERIFY_SCRIPT" --pr "$pr" --file "$out_file" >/dev/null

expect_fail "bad attestation sha" "attestation commit must be 40-char lowercase sha" "$SCRIPT" --pr "$pr" --story "$story_id" --mirror-branch "$mirror_branch" --attestation-commit "badsha"

echo "PASS: fork_attestation_mirror"
