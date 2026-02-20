#!/usr/bin/env bash
set -euo pipefail

# Scaffold a new story postmortem entry.
# Usage: ./plans/scaffold_postmortem.sh <STORY-ID>
# Creates: reviews/postmortems/<STORY-ID>_postmortem.md

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$ROOT/reviews/postmortems/STORY_POSTMORTEM_TEMPLATE.md"
OUT_DIR="$ROOT/reviews/postmortems"

usage() {
  echo "Usage: $0 <STORY-ID>" >&2
  echo "Creates: reviews/postmortems/<STORY-ID>_postmortem.md" >&2
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

target="$OUT_DIR/${story_id}_postmortem.md"

if [[ -f "$target" ]]; then
  echo "ERROR: already exists: $target" >&2
  exit 1
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "ERROR: template missing: $TEMPLATE" >&2
  exit 1
fi

# Copy template and replace placeholder with actual story ID
sed "s/<STORY-ID>/${story_id}/g" "$TEMPLATE" > "$target"
echo "$target"
