#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/fork_attestation_remediation_verify.sh"

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

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

pr=17
valid_file="$tmp_dir/pr_${pr}.json"
cat > "$valid_file" <<'EOF'
{
  "schema_version": 1,
  "pr_number": 17,
  "story_id": "WF-004",
  "mirror_branch": "mirror/pr-17",
  "mirror_head_sha": "0123456789abcdef0123456789abcdef01234567",
  "attestation_commit_sha": "89abcdef0123456789abcdef0123456789abcdef",
  "remediated_by": "maintainer",
  "remediated_at_utc": "2026-02-13T14:00:00Z"
}
EOF

ok_output="$("$SCRIPT" --pr "$pr" --file "$valid_file")"
printf '%s\n' "$ok_output" | grep -Fq "PASS: fork attestation remediation metadata" || fail "missing pass output"

missing_file="$tmp_dir/missing.json"
expect_fail "missing metadata file" "FORK_REMEDIATION_METADATA_MISSING" "$SCRIPT" --pr "$pr" --file "$missing_file"

mismatch_file="$tmp_dir/mismatch.json"
cp "$valid_file" "$mismatch_file"
sed -i.bak 's/"pr_number": 17/"pr_number": 18/' "$mismatch_file"
rm -f "$mismatch_file.bak"
expect_fail "pr mismatch" "FORK_REMEDIATION_PR_MISMATCH" "$SCRIPT" --pr "$pr" --file "$mismatch_file"

bad_sha_file="$tmp_dir/bad_sha.json"
cp "$valid_file" "$bad_sha_file"
sed -i.bak 's/0123456789abcdef0123456789abcdef01234567/notasha/' "$bad_sha_file"
rm -f "$bad_sha_file.bak"
expect_fail "bad mirror sha" "FORK_REMEDIATION_SCHEMA_INVALID (mirror_head_sha" "$SCRIPT" --pr "$pr" --file "$bad_sha_file"

echo "PASS: fork_attestation_remediation_verify"
