#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/thinking_review_logged.sh <slice_id> [--head <sha>] [--branch <name>] [--stories <csv>] [--reviewer <name>] [--out-root <path>] [--force]

Writes a slice-close thinking review artifact to:
  artifacts/slice_reviews/<slice_id>/thinking_review.md

Default behavior writes a template with "Ready To Close Slice: NO".
USAGE
}

slice_id="${1:-}"
if [[ -z "$slice_id" || "$slice_id" == "-h" || "$slice_id" == "--help" ]]; then
  usage
  exit 2
fi
shift

head_sha=""
branch=""
stories="<story_ids>"
reviewer="<name>"
out_root="${SLICE_REVIEW_ARTIFACTS_ROOT:-artifacts/slice_reviews}"
force_write=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --branch)
      branch="${2:?missing branch}"
      shift 2
      ;;
    --stories)
      stories="${2:?missing stories}"
      shift 2
      ;;
    --reviewer)
      reviewer="${2:?missing reviewer}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    --force)
      force_write=1
      shift 1
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read HEAD" >&2; exit 2; }
fi

if [[ -z "$branch" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
fi

if [[ "$out_root" != /* ]]; then
  out_root="$repo_root/$out_root"
fi

out_dir="$out_root/$slice_id"
out_file="$out_dir/thinking_review.md"
mkdir -p "$out_dir"

if [[ -f "$out_file" && "$force_write" -ne 1 ]]; then
  echo "ERROR: artifact already exists (use --force to overwrite): $out_file" >&2
  exit 2
fi

ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

cat > "$out_file" <<EOF
# Thinking Review (Slice Close)

- Slice ID: $slice_id
- Integration HEAD: $head_sha
- Skill Path: ~/.agents/skills/thinking-review-expert/SKILL.md
- Reviewer: $reviewer
- Timestamp (UTC): $ts

## Scope
- Stories merged in this slice: $stories
- Branch reviewed: $branch

## Findings
- Blocking: <none | summary>
- Major: <none | summary>
- Medium: <none | summary>

## Final Disposition
- Ready To Close Slice: NO
- Follow-ups: <none | list>
EOF

echo "Saved thinking review artifact: $out_file"
