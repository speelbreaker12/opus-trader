#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/story_postmortem_logged.sh <STORY_ID> [--head <sha>] [--out-root <path>]

Scaffolds a TOC-style postmortem from plans/postmortem_template.md.
Writes: artifacts/story/<ID>/postmortem.md

Use plans/postmortem_gate.sh to validate the filled artifact.
USAGE
}

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

head_sha=""
out_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read HEAD" >&2; exit 2; }
fi

if [[ "$out_root" != /* ]]; then
  out_root="$repo_root/$out_root"
fi

dir="$out_root/$story"
mkdir -p "$dir"

file="$dir/postmortem.md"

if [[ -f "$file" ]]; then
  echo "Already exists: $file" >&2
  echo "$file"
  exit 0
fi

template="$repo_root/plans/postmortem_template.md"
if [[ ! -f "$template" ]]; then
  echo "ERROR: template missing: $template" >&2
  exit 1
fi

sed -e "s/\${STORY_ID}/${story}/g" \
    -e "s/\${HEAD}/${head_sha}/g" \
    "$template" > "$file"

echo "Scaffolded postmortem: $file"
echo "Validate with: ./plans/postmortem_gate.sh $story --head $head_sha"
