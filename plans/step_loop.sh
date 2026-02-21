#!/usr/bin/env bash
set -euo pipefail

# step_loop.sh — thin supervisor loop
#
# Does NOT duplicate any validation. All checks live in wf_step.sh.
# This script only does: next → prompt → (builder works) → validate → next
#
# Usage:
#   STEP_SUPERVISOR_BASE_BRANCH=<branch> ./plans/step_loop.sh <STORY_ID> [--recon]

STORY_ID="${1:?usage: step_loop.sh <STORY_ID> [--recon]}"
RECON_FLAG="${2:-}"
SUP="./plans/step_supervisor.sh"

while true; do
  step="$("$SUP" "$STORY_ID" next ${RECON_FLAG:+$RECON_FLAG})"

  if [[ "$step" == "done" ]]; then
    echo "All steps complete for $STORY_ID."
    break
  fi

  echo
  echo "=== STEP: $step ==="
  "$SUP" "$STORY_ID" prompt ${RECON_FLAG:+$RECON_FLAG}
  echo
  read -r -p "Press Enter after builder finishes '$step'..."

  if ! "$SUP" "$STORY_ID" validate ${RECON_FLAG:+$RECON_FLAG}; then
    echo "Step '$step' failed validation. Fix and re-run." >&2
    "$SUP" "$STORY_ID" status ${RECON_FLAG:+$RECON_FLAG} || true
    exit 1
  fi

  echo "Validated: $step"
  "$SUP" "$STORY_ID" status ${RECON_FLAG:+$RECON_FLAG} || true
done

exit 0
