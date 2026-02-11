#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/pre_pr_review_gate.sh <STORY_ID> [--head <sha>] [--artifacts-root <path>] [--slice-id <id>] [--slice-artifacts-root <path>]

Purpose:
  Pre-PR review evidence gate aligned to split policy:
    - Always require code-review-expert evidence for STORY_ID + HEAD.
    - Optionally require thinking-review evidence for a slice close when --slice-id is provided.

Required code-review-expert evidence:
  - artifacts/story/<STORY_ID>/code_review_expert/*_review.md
  - exact lines:
      - Story: <STORY_ID>
      - HEAD: <sha>
      - Skill Path: ~/.agents/skills/code-review-expert/SKILL.md
      - Review Status: COMPLETE
  - unresolved placeholder token "<none | summary>" must not be present.

Optional thinking-review evidence:
  - When --slice-id is set, this script delegates to:
      ./plans/slice_review_gate.sh <slice_id> --head <sha>
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

head_sha=""
artifacts_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
slice_id=""
slice_artifacts_root="${SLICE_REVIEW_ARTIFACTS_ROOT:-artifacts/slice_reviews}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
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

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || die "failed to read HEAD"
fi

if [[ "$artifacts_root" != /* ]]; then
  artifacts_root="$repo_root/$artifacts_root"
fi

if [[ "$slice_artifacts_root" != /* ]]; then
  slice_artifacts_root="$repo_root/$slice_artifacts_root"
fi

review_dir="$artifacts_root/$story/code_review_expert"
review_file=""
if [[ -d "$review_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $head_sha" "$f"; then
      review_file="$f"
      break
    fi
  done < <(find "$review_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
fi
[[ -n "$review_file" ]] || die "missing code-review-expert review artifact for HEAD=$head_sha in: $review_dir"

grep -Fxq -- "- Review Status: COMPLETE" "$review_file" || die "code-review-expert review must be COMPLETE ($review_file)"
grep -Fxq -- "- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md" "$review_file" || die "code-review-expert review missing canonical skill path ($review_file)"
if grep -Fq -- "<none | summary>" "$review_file"; then
  die "code-review-expert review contains unresolved placeholder '<none | summary>' ($review_file)"
fi

if [[ -n "$slice_id" ]]; then
  slice_gate="$repo_root/plans/slice_review_gate.sh"
  [[ -x "$slice_gate" ]] || die "missing or non-executable slice review gate: $slice_gate"
  "$slice_gate" "$slice_id" --head "$head_sha" --artifacts-root "$slice_artifacts_root"
fi

echo "OK: pre-PR review gate passed for $story @ $head_sha"
echo "  code_review_expert_review: $review_file"
if [[ -n "$slice_id" ]]; then
  echo "  slice_id: $slice_id"
fi
