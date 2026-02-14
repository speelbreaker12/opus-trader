#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/pre_pr_review_gate.sh <STORY_ID> [--head <sha>] [--branch <name>] [--artifacts-root <path>] [--slice-id <id>] [--slice-artifacts-root <path>]

Purpose:
  Pre-PR review evidence gate aligned to split policy:
    - Enforce full story review evidence via ./plans/story_review_gate.sh.
    - Enforce one-story-per-branch with slash-free Story IDs (`[A-Za-z0-9][A-Za-z0-9._-]*`) and branch format:
        story/<STORY_ID>
        story/<STORY_ID>/<slug>
        story/<PRD_STORY_ID>-<slug>
    - Optionally require thinking-review evidence for a slice close when --slice-id is provided.

Required story review evidence:
  - Enforced by ./plans/story_review_gate.sh for STORY_ID + HEAD.

Optional thinking-review evidence:
  - When --slice-id is set, this script delegates to:
      ./plans/slice_review_gate.sh <slice_id> --head <sha>
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

validate_identifier() {
  local value="$1"
  local label="$2"
  if ! [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "invalid $label value: $value"
  fi
}

extract_story_from_branch() {
  local branch="$1"
  if [[ "$branch" =~ ^story/([A-Za-z0-9][A-Za-z0-9._-]*)(/[A-Za-z0-9._-]+)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$branch" =~ ^story/([A-Za-z0-9][A-Za-z0-9._-]*)-[A-Za-z0-9._]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

escape_regex() {
  printf '%s\n' "$1" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g'
}

branch_matches_story() {
  local branch="$1"
  local story_id="$2"
  local escaped_story
  escaped_story="$(escape_regex "$story_id")"

  if [[ "$branch" =~ ^story/${escaped_story}(/([A-Za-z0-9._-]+))?$ ]]; then
    return 0
  fi
  if [[ "$branch" =~ ^story/${escaped_story}-[A-Za-z0-9._]+$ ]]; then
    return 0
  fi
  return 1
}

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

head_sha=""
branch_name=""
artifacts_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
slice_id=""
slice_artifacts_root="${SLICE_REVIEW_ARTIFACTS_ROOT:-artifacts/slice_reviews}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --branch)
      branch_name="${2:?missing branch}"
      shift 2
      ;;
    --artifacts-root)
      artifacts_root="${2:?missing path}"
      shift 2
      ;;
    --slice-id)
      slice_id="${2:?missing id}"
      shift 2
      ;;
    --slice-artifacts-root)
      slice_artifacts_root="${2:?missing path}"
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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$repo_root"

validate_identifier "$story" "STORY_ID"
if [[ -n "$slice_id" ]]; then
  validate_identifier "$slice_id" "slice-id"
fi

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || die "failed to read HEAD"
fi

if [[ -z "$branch_name" ]]; then
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -n "$branch_name" && "$branch_name" != "HEAD" ]] || die "unable to validate story binding from branch (pass --branch for detached HEAD)"

branch_story="$(extract_story_from_branch "$branch_name" || true)"
[[ -n "$branch_story" ]] || die "branch must be story-scoped: expected story/<STORY_ID>[/<slug>] (slash-free STORY_ID) or story/<PRD_STORY_ID>-<slug>, got '$branch_name'"
if ! branch_matches_story "$branch_name" "$story"; then
  die "story id mismatch: STORY_ID=$story does not match branch story id=$branch_story (branch=$branch_name)"
fi

if [[ "$artifacts_root" != /* ]]; then
  artifacts_root="$repo_root/$artifacts_root"
fi

if [[ "$slice_artifacts_root" != /* ]]; then
  slice_artifacts_root="$repo_root/$slice_artifacts_root"
fi

story_gate="$repo_root/plans/story_review_gate.sh"
[[ -x "$story_gate" ]] || die "missing or non-executable story review gate: $story_gate"
"$story_gate" "$story" --head "$head_sha" --artifacts-root "$artifacts_root"

if [[ -n "$slice_id" ]]; then
  slice_gate="$repo_root/plans/slice_review_gate.sh"
  [[ -x "$slice_gate" ]] || die "missing or non-executable slice review gate: $slice_gate"
  "$slice_gate" "$slice_id" --head "$head_sha" --artifacts-root "$slice_artifacts_root"
fi

echo "OK: pre-PR review gate passed for $story @ $head_sha"
echo "  branch: $branch_name"
if [[ -n "$slice_id" ]]; then
  echo "  slice_id: $slice_id"
fi
