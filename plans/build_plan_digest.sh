#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

SOURCE_FILE="${PLAN_SOURCE_FILE:-}"
if [[ -z "$SOURCE_FILE" ]]; then
  if [[ -f "specs/IMPLEMENTATION_PLAN.md" ]]; then
    SOURCE_FILE="specs/IMPLEMENTATION_PLAN.md"
  else
    SOURCE_FILE="IMPLEMENTATION_PLAN.md"
  fi
fi
if [[ ! -f "$SOURCE_FILE" ]]; then
  echo "[plan_digest] ERROR: plan file missing: $SOURCE_FILE" >&2
  exit 2
fi

OUTPUT_FILE="${PLAN_DIGEST_FILE:-.context/plan_digest.json}"
# DIGEST_MODE: 'slim' for metadata only (fast), 'full' for complete text (default)
DIGEST_MODE="${DIGEST_MODE:-slim}"

SOURCE_FILE="$SOURCE_FILE" OUTPUT_FILE="$OUTPUT_FILE" DIGEST_MODE="$DIGEST_MODE" ./plans/build_markdown_digest.sh "$SOURCE_FILE" "$OUTPUT_FILE"
