#!/usr/bin/env bash
set -euo pipefail

# step_supervisor.sh — single-step orchestration wrapper around plans/wf_step.sh
#
# Feeds the builder exactly ONE step at a time. Validates completion via wf_step.sh
# receipt chain, then advances. Builder never sees future steps.
#
# Usage:
#   ./plans/step_supervisor.sh <STORY_ID> next
#   ./plans/step_supervisor.sh <STORY_ID> prompt            # prints prompt for next step
#   ./plans/step_supervisor.sh <STORY_ID> run               # validates + writes receipt
#   ./plans/step_supervisor.sh <STORY_ID> status            # shows receipt chain
#   ./plans/step_supervisor.sh <STORY_ID> reset             # deletes receipts for story
#
# Environment:
#   STEP_SUPERVISOR_BASE_BRANCH  — required for prompt variable substitution
#   STORY_ARTIFACTS_ROOT         — override artifacts/story root (optional)
#
# Exit codes:
#   0 — success
#   1 — validation failed (wf_step.sh prerequisite missing or step validation failed)
#   2 — usage/setup error (bad args, missing env vars, path traversal)
#   5 — HEAD mismatch (drift since last receipt)

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
ARTIFACTS_ROOT="${STORY_ARTIFACTS_ROOT:-$ROOT/artifacts/story}"
WF_STEP="$ROOT/plans/wf_step.sh"
PRD_SET_PASS="$ROOT/plans/prd_set_pass.sh"

usage() {
  cat >&2 <<'EOF'
Usage: step_supervisor.sh <STORY_ID> <cmd> [options]

Commands:
  next      Print the next required step (or "pass" when all 8 done).
  prompt    Print the prompt for the next step (with variable substitution).
  run       Validate the next step and write receipt via wf_step.sh.
  status    Show receipt chain for story.
  reset     Delete all receipts for story.

Environment:
  STEP_SUPERVISOR_BASE_BRANCH  Base branch for review diffs (required for prompt)

Exit codes:
  0  success
  1  validation failed (prerequisites not met)
  2  usage/setup error
  5  HEAD mismatch

Rollback:
  plans/wf_step.sh <STORY_ID> --reset --yes   # clear all receipts
  plans/prd_set_pass.sh <STORY_ID> false       # flip passes back if needed
EOF
}

die() { echo "STEP_SUPERVISOR ERROR: $*" >&2; exit 2; }

# ── Argument parsing ────────────────────────────────────────────────
STORY="${1:-}"; CMD="${2:-}"
[[ -n "$STORY" && -n "$CMD" ]] || { usage; exit 2; }
shift 2

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --artifacts-root) ARTIFACTS_ROOT="$2"; shift 2 ;;
    --wf-step) WF_STEP="$2"; shift 2 ;;
    --prd-set-pass) PRD_SET_PASS="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown arg: $1" ;;
  esac
done

# ── Security: STORY_ID validation (prevent path traversal) ─────────
if [[ ! "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  die "invalid STORY_ID '$STORY' — must match ^[A-Za-z0-9][A-Za-z0-9_-]*\$"
fi

[[ -x "$WF_STEP" ]] || die "wf_step.sh not executable at: $WF_STEP"

RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"
PROMPTS_DIR="$ROOT/plans/step_prompts"

# Must match wf_step.sh STEPS array (minus 'pass' which is handled specially).
STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)

# ── Receipt filename helpers (must match wf_step.sh:receipt_file pattern) ───

step_index() {
  local s="$1"
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$s" ]] && { echo "$i"; return 0; }
  done
  return 1
}

receipt_file() {
  local s="$1" idx
  idx="$(step_index "$s")"
  printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$idx" "$s"
}

# ── Core functions ──────────────────────────────────────────────────

last_receipt_head() {
  local latest="" s f
  for s in "${STEPS[@]}"; do
    f="$(receipt_file "$s")"
    [[ -f "$f" ]] && latest="$f"
  done
  if [[ -n "$latest" ]]; then
    jq -r '.head_sha // empty' "$latest" 2>/dev/null || true
  fi
}

first_missing_step() {
  local s
  local current_head
  current_head="$(git rev-parse HEAD 2>/dev/null || echo '')"

  for s in "${STEPS[@]}"; do
    if [[ ! -f "$(receipt_file "$s")" ]]; then
      # Check for gaps: if this step is missing but a LATER step exists, that's a problem.
      local later found_later=0
      for later in "${STEPS[@]}"; do
        if [[ "$later" == "$s" ]]; then
          found_later=1
          continue
        fi
        if [[ "$found_later" -eq 1 && -f "$(receipt_file "$later")" ]]; then
          echo "STEP_SUPERVISOR: receipt gap detected — '$s' missing but '$later' exists" >&2
          exit 4
        fi
      done
      echo "$s"
      return 0
    fi
  done

  # All steps done — check HEAD monotonicity before declaring complete.
  local last_head
  last_head="$(last_receipt_head)"
  if [[ -n "$last_head" && -n "$current_head" && "$last_head" != "$current_head" ]]; then
    echo "STEP_SUPERVISOR: HEAD changed since last receipt (receipt=$last_head current=$current_head)" >&2
    echo "STEP_SUPERVISOR: run 'plans/wf_step.sh $STORY --reset' to restart" >&2
    exit 5
  fi

  echo "pass"
}

print_next() {
  first_missing_step
}

prompt_file_for_step() {
  local step="$1"
  local f="$PROMPTS_DIR/$step.md"
  [[ -f "$f" ]] || die "missing prompt file: $f"
  echo "$f"
}

substitute_vars() {
  local text="$1"
  local head_sha
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo 'UNKNOWN')"
  local base_branch="${STEP_SUPERVISOR_BASE_BRANCH:-UNSET}"

  text="${text//\$\{STORY_ID\}/$STORY}"
  text="${text//\$\{BASE_BRANCH\}/$base_branch}"
  text="${text//\$\{HEAD\}/$head_sha}"
  echo "$text"
}

run_step() {
  local step="$1"

  if [[ "$step" == "pass" ]]; then
    echo "STEP_SUPERVISOR: all 8 steps complete for $STORY"
    echo "STEP_SUPERVISOR: running final chain validation..."
    local rc=0
    "$WF_STEP" "$STORY" pass || rc=$?
    case "$rc" in
      0)
        echo
        echo "STEP_SUPERVISOR: receipt chain validated. Next action:"
        echo "  $PRD_SET_PASS $STORY true"
        echo "(step_supervisor does NOT run prd_set_pass for you.)"
        ;;
      1) echo "STEP_SUPERVISOR BLOCKED: prerequisite missing for pass step" >&2; exit 1 ;;
      5) echo "STEP_SUPERVISOR HALT: HEAD mismatch — receipts stale" >&2; exit 5 ;;
      *) echo "STEP_SUPERVISOR: wf_step.sh exited $rc for pass step" >&2; exit "$rc" ;;
    esac
    return 0
  fi

  # Run wf_step.sh (mechanical validation + receipt write)
  echo "STEP_SUPERVISOR: validating step '$step' for $STORY..."
  local rc=0
  "$WF_STEP" "$STORY" "$step" || rc=$?

  case "$rc" in
    0) ;;  # Success
    1)
      echo "STEP_SUPERVISOR BLOCKED: prerequisite missing for '$step'" >&2
      echo "STEP_SUPERVISOR: check receipt chain with: $0 $STORY status" >&2
      exit 1
      ;;
    3)
      echo "STEP_SUPERVISOR BLOCKED: step validation failed for '$step'" >&2
      echo "STEP_SUPERVISOR: builder must produce the required artifacts" >&2
      exit 1
      ;;
    5)
      echo "STEP_SUPERVISOR HALT: HEAD mismatch for '$step'" >&2
      exit 5
      ;;
    *)
      echo "STEP_SUPERVISOR: wf_step.sh exited $rc for step '$step'" >&2
      exit "$rc"
      ;;
  esac

  echo "STEP_SUPERVISOR: step '$step' COMPLETE"
}

# ── Mutual exclusion for run command ────────────────────────────────
run_with_lock() {
  local lockfile="/tmp/step_supervisor_${STORY}.lock"
  local lockdir="${lockfile}.d"
  if command -v flock >/dev/null 2>&1; then
    (
      if ! flock -n 9; then
        die "another supervisor is running for story $STORY (lock: $lockfile)"
      fi
      run_step "$1"
    ) 9>"$lockfile"
  else
    # macOS fallback: mkdir is atomic
    if ! mkdir "$lockdir" 2>/dev/null; then
      die "another supervisor is running for story $STORY (lock: $lockdir)"
    fi
    local rc=0
    run_step "$1" || rc=$?
    rmdir "$lockdir" 2>/dev/null || true
    return "$rc"
  fi
}

# ── Main dispatch ───────────────────────────────────────────────────
case "$CMD" in
  next)
    print_next
    ;;
  prompt)
    step="$(print_next)"
    if [[ "$step" == "pass" ]]; then
      echo "# NEXT STEP: pass"
      echo "# No builder prompt — supervisor runs prd_set_pass.sh directly."
      echo
      echo "All 8 builder steps are complete."
      echo "Run: $0 $STORY run"
      exit 0
    fi
    f="$(prompt_file_for_step "$step")"
    echo "# NEXT STEP: $step"
    echo "# PROMPT FILE: $f"
    echo
    content="$(cat "$f")"
    substitute_vars "$content"
    ;;
  run)
    step="$(print_next)"
    run_with_lock "$step"
    ;;
  status)
    "$WF_STEP" "$STORY" --status
    ;;
  reset)
    "$WF_STEP" "$STORY" --reset --yes
    ;;
  *)
    die "unknown command: $CMD (expected: next|prompt|run|status|reset)"
    ;;
esac
