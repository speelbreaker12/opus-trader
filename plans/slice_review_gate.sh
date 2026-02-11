#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/slice_review_gate.sh <slice_id> [--head <sha>] [--artifacts-root <path>]

Purpose:
  Fail-closed gate for slice-close thinking-review evidence.

Requires:
  - artifacts/slice_reviews/<slice_id>/thinking_review.md
  - exact lines:
      - Slice ID: <slice_id>
      - Integration HEAD: <sha>
      - Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md
      - Ready To Close Slice: YES
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

require_fixed_line() {
  local file="$1"
  local expected="$2"
  local message="$3"
  grep -Fxq -- "$expected" "$file" || die "$message ($file)"
}

slice_id="${1:-}"
[[ -n "$slice_id" ]] || { usage >&2; exit 2; }
shift

head_sha=""
artifacts_root="${SLICE_REVIEW_ARTIFACTS_ROOT:-artifacts/slice_reviews}"

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

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || die "failed to read HEAD"
fi

if [[ "$artifacts_root" != /* ]]; then
  artifacts_root="$repo_root/$artifacts_root"
fi

review_file="$artifacts_root/$slice_id/thinking_review.md"
[[ -f "$review_file" ]] || die "missing slice thinking-review artifact: $review_file"

require_fixed_line "$review_file" "- Slice ID: $slice_id" "slice review has wrong slice id"
require_fixed_line "$review_file" "- Integration HEAD: $head_sha" "slice review does not match HEAD=$head_sha"
require_fixed_line "$review_file" "- Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md" "slice review missing canonical skill path"
require_fixed_line "$review_file" "- Ready To Close Slice: YES" "slice review must assert ready-to-close YES"

grep -Fq -- "## Final Disposition" "$review_file" || die "slice review missing '## Final Disposition' section ($review_file)"

echo "OK: slice review gate passed for $slice_id @ $head_sha"
echo "  thinking_review: $review_file"
