#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/slice_completion_enforce.sh [--branch <name>] [--head <sha>] [--slice-id <id>] [--prd-file <path>] [--artifacts-root <path>]

Purpose:
  Enforce slice-close thinking-review gate in verify full when running on a
  slice integration branch and the slice is fully passed in PRD.

Behavior:
  - If branch is not run/sliceN-clean: skip (exit 0)
  - If slice has no PRD stories: skip (exit 0)
  - If any slice story has passes!=true: skip (exit 0)
  - Else: require plans/slice_review_gate.sh to pass for that slice/head
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

branch_name=""
head_sha=""
slice_id=""
prd_file="${PRD_FILE:-plans/prd.json}"
artifacts_root="${SLICE_REVIEW_ARTIFACTS_ROOT:-artifacts/slice_reviews}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      branch_name="${2:?missing branch}"
      shift 2
      ;;
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --slice-id)
      slice_id="${2:?missing id}"
      shift 2
      ;;
    --prd-file)
      prd_file="${2:?missing path}"
      shift 2
      ;;
    --artifacts-root)
      artifacts_root="${2:?missing path}"
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

command -v jq >/dev/null 2>&1 || die "jq required"

if [[ -z "$branch_name" ]]; then
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -n "$branch_name" ]] || die "failed to determine branch"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
fi
[[ -n "$head_sha" ]] || die "failed to determine HEAD"

if [[ "$branch_name" =~ ^run/slice([0-9]+)-clean$ ]]; then
  slice_num="${BASH_REMATCH[1]}"
else
  echo "SKIP: slice completion enforcement not applicable on branch '$branch_name'"
  exit 0
fi

if [[ "$prd_file" != /* ]]; then
  prd_file="$repo_root/$prd_file"
fi
[[ -f "$prd_file" ]] || die "missing PRD file: $prd_file"

slice_story_count="$(jq -r --argjson s "$slice_num" '[.items[] | select(.slice == $s)] | length' "$prd_file" 2>/dev/null || true)"
[[ "$slice_story_count" =~ ^[0-9]+$ ]] || die "invalid PRD query result for slice story count"
if [[ "$slice_story_count" == "0" ]]; then
  echo "SKIP: no PRD stories found for slice=$slice_num"
  exit 0
fi

pending_count="$(jq -r --argjson s "$slice_num" '[.items[] | select(.slice == $s and (.passes != true))] | length' "$prd_file" 2>/dev/null || true)"
[[ "$pending_count" =~ ^[0-9]+$ ]] || die "invalid PRD query result for pending story count"
if [[ "$pending_count" != "0" ]]; then
  echo "SKIP: slice=$slice_num has $pending_count stories with passes!=true"
  exit 0
fi

if [[ -z "$slice_id" ]]; then
  slice_id="slice${slice_num}"
fi

gate="./plans/slice_review_gate.sh"
[[ -x "$gate" ]] || die "missing or non-executable slice review gate: $gate"

"$gate" "$slice_id" --head "$head_sha" --artifacts-root "$artifacts_root"

echo "PASS: slice completion enforcement passed for branch=$branch_name slice_id=$slice_id head=$head_sha"
