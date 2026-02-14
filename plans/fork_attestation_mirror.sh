#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/fork_attestation_mirror.sh --pr <number> --story <STORY_ID> --mirror-branch <branch> --attestation-commit <sha> [--mirror-head <sha>] [--actor <name>] [--out <path>]

Writes tracked fork-remediation metadata and validates it.
Default output path:
  plans/review_attestations/fork_remediation/pr_<PR_NUMBER>.json
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

pr_number=""
story_id=""
mirror_branch=""
mirror_head_sha=""
attestation_commit_sha=""
actor=""
out_file=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      pr_number="${2:-}"
      shift 2
      ;;
    --story)
      story_id="${2:-}"
      shift 2
      ;;
    --mirror-branch)
      mirror_branch="${2:-}"
      shift 2
      ;;
    --mirror-head)
      mirror_head_sha="${2:-}"
      shift 2
      ;;
    --attestation-commit)
      attestation_commit_sha="${2:-}"
      shift 2
      ;;
    --actor)
      actor="${2:-}"
      shift 2
      ;;
    --out)
      out_file="${2:-}"
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

[[ -n "$pr_number" && -n "$story_id" && -n "$mirror_branch" && -n "$attestation_commit_sha" ]] || {
  usage >&2
  exit 2
}
[[ "$pr_number" =~ ^[1-9][0-9]*$ ]] || die "invalid PR number: $pr_number"
[[ "$story_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "invalid story id: $story_id"
[[ "$attestation_commit_sha" =~ ^[0-9a-f]{40}$ ]] || die "attestation commit must be 40-char lowercase sha"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ -z "$mirror_head_sha" ]]; then
  mirror_head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
fi
[[ "$mirror_head_sha" =~ ^[0-9a-f]{40}$ ]] || die "mirror head must be 40-char lowercase sha"

if [[ -z "$actor" ]]; then
  actor="${GITHUB_ACTOR:-}"
fi
if [[ -z "$actor" ]]; then
  actor="$(git config user.name 2>/dev/null || true)"
fi
if [[ -z "$actor" ]]; then
  actor="unknown"
fi

if [[ -z "$out_file" ]]; then
  out_file="plans/review_attestations/fork_remediation/pr_${pr_number}.json"
fi

mkdir -p "$(dirname "$out_file")"

tmp_file="$(mktemp)"
cleanup() {
  if [[ -n "${tmp_file:-}" && -f "$tmp_file" ]]; then
    rm -f "$tmp_file"
  fi
}
trap cleanup EXIT

now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

jq -n \
  --arg story_id "$story_id" \
  --arg mirror_branch "$mirror_branch" \
  --arg mirror_head_sha "$mirror_head_sha" \
  --arg attestation_commit_sha "$attestation_commit_sha" \
  --arg remediated_by "$actor" \
  --arg remediated_at_utc "$now_utc" \
  --argjson pr_number "$pr_number" \
  '{
    schema_version: 1,
    pr_number: $pr_number,
    story_id: $story_id,
    mirror_branch: $mirror_branch,
    mirror_head_sha: $mirror_head_sha,
    attestation_commit_sha: $attestation_commit_sha,
    remediated_by: $remediated_by,
    remediated_at_utc: $remediated_at_utc
  }' > "$tmp_file"

mv "$tmp_file" "$out_file"
tmp_file=""

verify_script="$ROOT/plans/fork_attestation_remediation_verify.sh"
[[ -x "$verify_script" ]] || die "missing remediation verifier: $verify_script"
"$verify_script" --pr "$pr_number" --file "$out_file" >/dev/null

echo "Wrote fork remediation metadata: $out_file"
