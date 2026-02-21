#!/usr/bin/env bash
set -euo pipefail

# step_supervisor.sh — thin orchestration wrapper around wf_step.sh
#
# All validation lives in wf_step.sh. This script only does:
#   next → prompt → (builder works) → validate → next
#
# Usage:
#   step_supervisor.sh <STORY_ID> next [--machine] [--recon]
#   step_supervisor.sh <STORY_ID> prompt [<step>] [--recon]
#   step_supervisor.sh <STORY_ID> validate|run [<step>] [--recon]
#   step_supervisor.sh <STORY_ID> status [--machine] [--recon]
#   step_supervisor.sh <STORY_ID> reset

STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)
WF_STEP="./plans/wf_step.sh"
PROMPTS_DIR="plans/step_prompts"
PREAMBLE="$PROMPTS_DIR/builder_preamble.md"

usage() {
  cat >&2 <<'EOF'
Usage: step_supervisor.sh <STORY_ID> <cmd> [<step>] [--recon] [--machine]

Commands:
  next          Print the next required step (or "done").
  prompt        Print the builder prompt for the next step.
  validate|run  Validate the next step via wf_step.sh + write receipt.
  status        Show receipt chain.
  reset         Delete all receipts for story.

Options:
  --recon     Reconciliation mode (audit already-passing stories)
  --machine   Machine-readable output (pipe-delimited)

Environment:
  STEP_SUPERVISOR_BASE_BRANCH  Base branch for review diffs
EOF
  exit 2
}

# ── Arg parsing ─────────────────────────────────────────────────────
[[ $# -ge 2 ]] || usage
STORY="$1"; shift
CMD="$1"; shift

RECON_MODE=0
MACHINE=0
BASE_BRANCH="${STEP_SUPERVISOR_BASE_BRANCH:-}"
STEP_ARG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --recon)   RECON_MODE=1 ;;
    --machine) MACHINE=1 ;;
    -h|--help) usage ;;
    -*)        echo "Unknown option: $1" >&2; usage ;;
    *)
      if [[ -z "$STEP_ARG" ]]; then
        STEP_ARG="$1"
      else
        echo "Unexpected arg: $1" >&2; usage
      fi
      ;;
  esac
  shift
done

# Security: prevent path traversal
[[ "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || { echo "Invalid STORY_ID: $STORY" >&2; exit 2; }

# ── Paths ───────────────────────────────────────────────────────────
ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"

# ── Helpers ─────────────────────────────────────────────────────────

receipt_file() {
  local step="$1" i
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$step" ]] && { printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$i" "$step"; return; }
  done
  return 1
}

first_missing_step() {
  local step f
  for step in "${STEPS[@]}"; do
    f="$(receipt_file "$step")"
    [[ -f "$f" ]] || { echo "$step"; return; }
  done
  echo "done"
}

prompt_file_for_step() {
  local step="$1"
  if [[ "$RECON_MODE" -eq 1 ]]; then
    echo "$ROOT/$PROMPTS_DIR/recon/$step.md"
  else
    echo "$ROOT/$PROMPTS_DIR/$step.md"
  fi
}

run_wf_step() {
  local step="$1"
  if [[ "$RECON_MODE" -eq 1 ]]; then
    WF_RECON_MODE=1 "$WF_STEP" "$STORY" "$step"
  else
    "$WF_STEP" "$STORY" "$step"
  fi
}

find_prior_postmortem() {
  # Find the most recently modified postmortem in artifacts/story/*/postmortem.md
  # excluding the current story.
  # Uses -exec {} + so ls is never invoked on empty results (portability fix).
  local pm
  pm="$(find "$ROOT/artifacts/story" -maxdepth 2 -name 'postmortem.md' -not -path "*/$STORY/*" \
    -exec ls -t {} + 2>/dev/null | head -1 || true)"
  echo "${pm:-NONE}"
}

# ── Resolve pending step ────────────────────────────────────────────
pending="$(first_missing_step)"
step="${STEP_ARG:-$pending}"

# ── Commands ────────────────────────────────────────────────────────
case "$CMD" in
  next)
    if [[ "$MACHINE" -eq 1 ]]; then
      [[ "$pending" == "done" ]] && echo "DONE|-" || echo "PENDING|$pending"
    else
      echo "$pending"
    fi
    ;;

  prompt)
    [[ "$pending" != "done" ]] || { echo "All steps complete."; exit 0; }

    # Skip guard
    if [[ -n "$STEP_ARG" && "$step" != "$pending" ]]; then
      echo "Refusing prompt for '$step' — next required step is '$pending'" >&2
      exit 3
    fi

    pf="$(prompt_file_for_step "$step")"
    [[ -f "$pf" ]] || { echo "Missing prompt: $pf" >&2; exit 1; }

    HEAD_SHA="$(git rev-parse HEAD 2>/dev/null || echo UNKNOWN)"
    PRIOR_PM="$(find_prior_postmortem)"

    # Preamble
    [[ -f "$ROOT/$PREAMBLE" ]] && { cat "$ROOT/$PREAMBLE"; echo; echo "---"; echo; }

    # Render with variable substitution
    sed \
      -e "s|\${STORY_ID}|$STORY|g" \
      -e "s|\${BASE_BRANCH}|${BASE_BRANCH:-main}|g" \
      -e "s|\${HEAD}|$HEAD_SHA|g" \
      -e "s|\${RECON_MODE}|$RECON_MODE|g" \
      -e "s|\${PRIOR_POSTMORTEM_PATH}|$PRIOR_PM|g" \
      "$pf"
    ;;

  validate|run)
    [[ "$pending" != "done" ]] || { echo "All steps complete."; exit 0; }

    # Skip guard
    if [[ -n "$STEP_ARG" && "$step" != "$pending" ]]; then
      echo "Refusing '$step' — next required step is '$pending'" >&2
      exit 3
    fi

    rc=0
    run_wf_step "$step" || rc=$?
    if [[ "$rc" -ne 0 ]]; then
      case "$rc" in
        1) echo "Hint: prerequisite receipt missing." >&2 ;;
        3) echo "Hint: required artifacts not found or format wrong." >&2 ;;
        5) echo "Hint: HEAD drift or receipt mismatch." >&2 ;;
      esac
      exit "$rc"
    fi
    echo "Validated: $step"
    ;;

  status)
    if [[ "$MACHINE" -eq 1 ]]; then
      done_count=0; current="-"
      for s in "${STEPS[@]}"; do
        [[ -f "$(receipt_file "$s")" ]] && { done_count=$((done_count + 1)); current="$s"; }
      done
      echo "STATUS|story=${STORY}|current=${current}|next=${pending}|receipts=${done_count}/8|recon=${RECON_MODE}"
    else
      echo "Story: $STORY"
      echo "Mode: $([[ "$RECON_MODE" -eq 1 ]] && echo recon || echo normal)"
      echo "Next: $pending"
      echo "Receipts:"
      for s in "${STEPS[@]}"; do
        if [[ -f "$(receipt_file "$s")" ]]; then
          echo "  [x] $s"
        else
          echo "  [ ] $s"
        fi
      done
    fi
    ;;

  reset)
    "$WF_STEP" "$STORY" --reset --yes
    ;;

  *)
    usage
    ;;
esac
