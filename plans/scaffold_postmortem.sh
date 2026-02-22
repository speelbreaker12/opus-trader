#!/usr/bin/env bash
set -euo pipefail

# Scaffold a new story postmortem entry.
# Usage: ./plans/scaffold_postmortem.sh <STORY-ID>
# Creates: artifacts/story/<STORY-ID>/postmortem.md

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/plans/postmortem_template.md"
OUT_DIR="$ROOT/artifacts/story"

usage() {
  echo "Usage: $0 <STORY-ID>" >&2
  echo "Creates: artifacts/story/<STORY-ID>/postmortem.md" >&2
  echo "Example: $0 S7-001" >&2
  exit 1
}

if [[ $# -eq 0 ]]; then
  usage
fi

story_id="$1"

# Validate story ID format (e.g., S7-001, PX-1)
if [[ ! "$story_id" =~ ^[A-Z]+[0-9]*-[0-9]+$ ]]; then
  echo "ERROR: invalid story ID format: $story_id (expected e.g., S7-001, PX-1)" >&2
  usage
fi

target_dir="$OUT_DIR/$story_id"
target="$target_dir/postmortem.md"

if [[ -f "$target" ]]; then
  echo "ERROR: already exists: $target" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template missing: $TEMPLATE" >&2
  exit 1
fi

mkdir -p "$target_dir"

# Copy template and substitute story ID + HEAD
head_sha="$(git rev-parse HEAD 2>/dev/null || echo '<HEAD>')"
sed -e "s/\${STORY_ID}/${story_id}/g" \
    -e "s/\${HEAD}/${head_sha}/g" \
    "$TEMPLATE" > "$target"

echo "$target"
