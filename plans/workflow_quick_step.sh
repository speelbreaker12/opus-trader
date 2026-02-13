#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: plans/workflow_quick_step.sh <STORY_ID> <checkpoint>

Runs ./plans/verify.sh quick for a sequence-bound story checkpoint.

Allowed checkpoints:
  - pre_reviews
  - post_review_fixes
  - post_second_codex
  - post_findings_fixes
  - post_sync
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

story_id="${1:-}"
checkpoint="${2:-}"

if [[ -z "$story_id" || -z "$checkpoint" ]]; then
  usage >&2
  exit 2
fi

if ! [[ "$story_id" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*(/[A-Za-z0-9][A-Za-z0-9._-]*)*$ ]]; then
  die "invalid STORY_ID: $story_id"
fi

case "$checkpoint" in
  pre_reviews|post_review_fixes|post_second_codex|post_findings_fixes|post_sync) ;;
  *) die "invalid checkpoint: $checkpoint" ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

verify_script="${WORKFLOW_QUICK_VERIFY_SCRIPT:-./plans/verify.sh}"
[[ -x "$verify_script" ]] || die "missing or non-executable verify script: $verify_script"

"$verify_script" quick

echo "OK: workflow quick step passed for $story_id checkpoint=$checkpoint"
