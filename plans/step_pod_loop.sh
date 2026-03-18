#!/usr/bin/env bash
set -euo pipefail

# step_pod_loop.sh — minimal supervisor loop
#
# Walks the step array, prints each prompt, waits for the builder,
# then validates via wf_step.sh. That's it.
#
# Usage:
#   STEP_SUPERVISOR_BASE_BRANCH=<branch> ./plans/step_pod_loop.sh <STORY_ID> [--recon]

ID="${1:?usage: step_pod_loop.sh STORY_ID [--recon]}"
RECON="${2:-}"
BASE_BRANCH="${STEP_SUPERVISOR_BASE_BRANCH:-main}"
PROMPT_ROOT="plans/step_prompts"
PREAMBLE="$PROMPT_ROOT/builder_preamble.md"
[[ "$RECON" == "--recon" ]] && PROMPT_ROOT="$PROMPT_ROOT/recon"

steps=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)

# Find the most recent postmortem from a different story (for preflight carry-forward)
find_prior_postmortem() {
  local pm
  pm="$(find "$(git rev-parse --show-toplevel)/artifacts/story" -maxdepth 2 -name 'postmortem.md' \
    -not -path "*/$ID/*" -exec ls -t {} + 2>/dev/null | head -1 || true)"
  echo "${pm:-NONE}"
}

PRIOR_PM="$(find_prior_postmortem)"

for step in "${steps[@]}"; do
  echo "=================================================="
  echo "STEP: $step  STORY: $ID"
  echo "=================================================="

  prompt_file="$PROMPT_ROOT/${step}.md"
  [[ -f "$prompt_file" ]] || { echo "Missing prompt: $prompt_file" >&2; exit 2; }

  HEAD="$(git rev-parse HEAD)"

  echo
  echo "----- PROMPT TO GIVE BUILDER -----"
  [[ -f "$PREAMBLE" ]] && { cat "$PREAMBLE"; echo; echo "---"; echo; }
  sed \
    -e "s|\${STORY_ID}|$ID|g" \
    -e "s|\${BASE_BRANCH}|$BASE_BRANCH|g" \
    -e "s|\${HEAD}|$HEAD|g" \
    -e "s|\${RECON_MODE}|$([[ "$RECON" == "--recon" ]] && echo 1 || echo 0)|g" \
    -e "s|\${PRIOR_POSTMORTEM_PATH}|$PRIOR_PM|g" \
    "$prompt_file"
  echo "----- END PROMPT -----"
  echo

  read -r -p "Press ENTER after builder completes step '$step'..."

  if [[ "$RECON" == "--recon" ]]; then
    WF_RECON_MODE=1 plans/wf_step.sh "$ID" "$step"
  else
    plans/wf_step.sh "$ID" "$step"
  fi

  echo "VALIDATED: $step"
done

echo
echo "All 8 steps validated. Final pass flip is a separate command:"
echo "  plans/prd_set_pass.sh $ID true"
