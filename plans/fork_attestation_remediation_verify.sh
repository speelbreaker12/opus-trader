#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: plans/fork_attestation_remediation_verify.sh --pr <number> [--file <path>]

Validates tracked fork-remediation metadata:
  plans/review_attestations/fork_remediation/pr_<PR_NUMBER>.json
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

pr_number=""
metadata_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      pr_number="${2:-}"
      shift 2
      ;;
    --file)
      metadata_file="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

[[ -n "$pr_number" ]] || { usage >&2; exit 2; }
[[ "$pr_number" =~ ^[0-9]+$ ]] || die "invalid PR number: $pr_number"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "$metadata_file" ]]; then
  metadata_file="plans/review_attestations/fork_remediation/pr_${pr_number}.json"
fi

[[ -f "$metadata_file" ]] || die "FORK_REMEDIATION_METADATA_MISSING ($metadata_file)"
jq -e . "$metadata_file" >/dev/null 2>&1 || die "FORK_REMEDIATION_SCHEMA_INVALID (invalid JSON: $metadata_file)"

read -r schema_version file_pr story_id mirror_branch mirror_head_sha attestation_commit_sha remediated_by remediated_at_utc <<EOF
$(jq -r '
  [
    (.schema_version // ""),
    (.pr_number // ""),
    (.story_id // ""),
    (.mirror_branch // ""),
    (.mirror_head_sha // ""),
    (.attestation_commit_sha // ""),
    (.remediated_by // ""),
    (.remediated_at_utc // "")
  ] | @tsv
' "$metadata_file")
EOF

[[ "$schema_version" == "1" ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (schema_version must be 1)"
[[ "$file_pr" =~ ^[0-9]+$ ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (pr_number must be integer)"
[[ "$file_pr" == "$pr_number" ]] || die "FORK_REMEDIATION_PR_MISMATCH (expected=$pr_number actual=$file_pr)"
[[ -n "$story_id" ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (story_id missing)"
[[ -n "$mirror_branch" ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (mirror_branch missing)"
[[ "$mirror_head_sha" =~ ^[0-9a-f]{40}$ ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (mirror_head_sha must be 40-char lowercase sha)"
[[ "$attestation_commit_sha" =~ ^[0-9a-f]{40}$ ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (attestation_commit_sha must be 40-char lowercase sha)"
[[ -n "$remediated_by" ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (remediated_by missing)"
[[ "$remediated_at_utc" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]] || die "FORK_REMEDIATION_SCHEMA_INVALID (remediated_at_utc must be RFC3339 UTC Z)"

echo "PASS: fork attestation remediation metadata ($metadata_file)"
