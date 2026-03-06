#!/usr/bin/env bash
set -euo pipefail

# parallel_review.sh — run multiple reviewer tools in parallel, then aggregate.
#
# Dispatches review_logged.sh to 2-4 tools concurrently, waits for all to finish,
# reports per-tool exit codes, then runs aggregate_proofs.sh if --proof-graph.
#
# Usage:
#   plans/parallel_review.sh <STORY_ID> --base <REF> [options]
#
# Options:
#   --tools <list>     Comma-separated tools (default: codex,opus)
#                      Available: codex, opus, kimi, gemini
#   --review-script <PATH>
#                      review_logged.sh path override
#   --base <REF>       Base ref for diff (passed through to review_logged.sh)
#   --commit <REF>     Commit ref (passed through)
#   --files <LIST>     Files list (passed through)
#   --prompt <STYLE>   Prompt style: generic or enriched (default: enriched)
#   --proof-graph      Generate + aggregate proof graphs
#   --dry-run          Print commands without executing
#   --no-aggregate     Skip aggregate_proofs.sh even with --proof-graph
#
# Exit codes:
#   0 — all reviews passed, aggregation passed (if applicable)
#   1 — one or more reviews failed (details printed)
#   2 — usage error
#   3 — aggregation failed (reviews may have passed)
#
# Examples:
#   plans/parallel_review.sh S1-004 --base main
#   plans/parallel_review.sh S1-004 --base main --tools codex,opus,kimi --proof-graph
#   plans/parallel_review.sh S1-004 --files "src/gate.rs" --tools opus,kimi --prompt generic

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
AGGREGATE_SCRIPT="$ROOT/plans/aggregate_proofs.sh"

usage() {
  sed -n '3,/^$/{ s/^# //; s/^#$//; p; }' "$0" >&2
}

die() { echo "ERROR: $*" >&2; exit 2; }

resolve_story_artifacts_root() {
  local artifacts_root="${STORY_ARTIFACTS_ROOT:-$ROOT/artifacts/story}"
  if [[ "$artifacts_root" != /* ]]; then
    artifacts_root="$ROOT/$artifacts_root"
  fi
  printf '%s' "$artifacts_root"
}

display_artifact_path() {
  local artifact_path="$1"
  if [[ "$artifact_path" == "$ROOT/"* ]]; then
    printf '%s' "${artifact_path#$ROOT/}"
  else
    printf '%s' "$artifact_path"
  fi
}

# ── Defaults ──────────────────────────────────────────────────────────
STORY=""
TOOLS="codex,opus"
REVIEW_SCRIPT_OVERRIDE=""
MODE_ARGS=()
PROMPT_STYLE="enriched"
PROOF_GRAPH=false
DRY_RUN=false
NO_AGGREGATE=false
EXTRA_ARGS=()

# ── Argument parsing ──────────────────────────────────────────────────
[[ $# -ge 1 ]] || { usage; exit 2; }
[[ "$1" == "-h" || "$1" == "--help" ]] && { usage; exit 0; }
STORY="$1"; shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools)       TOOLS="${2:?missing tools list}"; shift 2 ;;
    --review-script) REVIEW_SCRIPT_OVERRIDE="${2:?missing review script path}"; shift 2 ;;
    # G-6 fix: detect conflicting mode flags
    --base)        [[ ${#MODE_ARGS[@]} -gt 0 ]] && die "only one of --base/--commit/--files/--uncommitted allowed"
                   MODE_ARGS=("--base" "${2:?missing ref}"); shift 2 ;;
    --commit)      [[ ${#MODE_ARGS[@]} -gt 0 ]] && die "only one of --base/--commit/--files/--uncommitted allowed"
                   MODE_ARGS=("--commit" "${2:?missing ref}"); shift 2 ;;
    --files)       [[ ${#MODE_ARGS[@]} -gt 0 ]] && die "only one of --base/--commit/--files/--uncommitted allowed"
                   MODE_ARGS=("--files" "${2:?missing files}"); shift 2 ;;
    --uncommitted) [[ ${#MODE_ARGS[@]} -gt 0 ]] && die "only one of --base/--commit/--files/--uncommitted allowed"
                   MODE_ARGS=("--uncommitted"); shift ;;
    --prompt)      PROMPT_STYLE="${2:?missing style}"; shift 2 ;;
    --proof-graph) PROOF_GRAPH=true; shift ;;
    --dry-run)     DRY_RUN=true; shift ;;
    --no-aggregate) NO_AGGREGATE=true; shift ;;
    -h|--help)     usage; exit 0 ;;
    --)            shift; EXTRA_ARGS=("$@"); break ;;
    *)             die "unknown argument: $1" ;;
  esac
done

# Validate
[[ -n "$STORY" ]] || die "STORY_ID is required"
[[ "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || die "invalid STORY_ID: $STORY"
[[ ${#MODE_ARGS[@]} -gt 0 ]] || die "one of --base, --commit, --files, or --uncommitted is required"
REVIEW_SCRIPT="${REVIEW_SCRIPT_OVERRIDE:-${PARALLEL_REVIEW_REVIEW_SCRIPT:-$ROOT/plans/review_logged.sh}}"
[[ -x "$REVIEW_SCRIPT" ]] || die "review_logged.sh not found at $REVIEW_SCRIPT"

# Parse tool list
IFS=',' read -ra TOOL_LIST <<< "$TOOLS"
for t in "${TOOL_LIST[@]}"; do
  case "$t" in
    codex|opus|kimi|gemini) ;;
    *) die "unknown tool: $t (expected: codex, opus, kimi, gemini)" ;;
  esac
done

TOOL_COUNT="${#TOOL_LIST[@]}"
[[ "$TOOL_COUNT" -gt 0 ]] || die "no tools specified"

# ── Parallel arrays (bash 3 compatible — no associative arrays) ───────
# Index matches TOOL_LIST. PID_LIST[i] = pid for TOOL_LIST[i], etc.
PID_LIST=()
LOG_LIST=()
RC_LIST=()

LOG_DIR="$(mktemp -d)"
trap 'rm -rf "$LOG_DIR"' EXIT
STORY_ARTIFACTS_DIR="$(resolve_story_artifacts_root)"

echo "═══════════════════════════════════════════════════════════════"
echo "  parallel_review: $STORY"
echo "  tools: ${TOOL_LIST[*]}"
echo "  mode:  ${MODE_ARGS[*]}"
echo "  prompt: $PROMPT_STYLE"
echo "  proof-graph: $PROOF_GRAPH"
echo "═══════════════════════════════════════════════════════════════"
echo

start_epoch="$(date +%s)"

for i in "${!TOOL_LIST[@]}"; do
  tool="${TOOL_LIST[$i]}"
  log_file="$LOG_DIR/${tool}.log"
  LOG_LIST[$i]="$log_file"

  cmd_args=("$REVIEW_SCRIPT" "$STORY" "--tool" "$tool" "--prompt" "$PROMPT_STYLE")
  cmd_args+=("${MODE_ARGS[@]}")
  # G-4 fix: only pass --proof-graph to tools that support it in the current mode.
  # codex only supports --proof-graph in --files mode; skip it otherwise.
  if [[ "$PROOF_GRAPH" == "true" ]]; then
    if [[ "$tool" == "codex" && "${MODE_ARGS[0]:-}" != "--files" ]]; then
      echo "[note] skipping --proof-graph for codex (not in --files mode)"
    else
      cmd_args+=("--proof-graph")
    fi
  fi
  [[ ${#EXTRA_ARGS[@]} -gt 0 ]] && cmd_args+=("--" "${EXTRA_ARGS[@]}")

  if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] ${cmd_args[*]}"
    continue
  fi

  # G-1 fix: wrap in subshell to record per-tool finish timestamp.
  echo "[launch] $tool → $log_file"
  (
    "${cmd_args[@]}" > "$log_file" 2>&1
    tool_rc=$?
    date +%s > "$log_file.end"
    exit $tool_rc
  ) &
  PID_LIST[$i]=$!
done

if [[ "$DRY_RUN" == "true" ]]; then
  echo
  echo "[dry-run] Would wait for all tools, then aggregate."
  exit 0
fi

# ── Wait for all tools ────────────────────────────────────────────────
echo
echo "Waiting for $TOOL_COUNT reviews..."
echo

any_failed=0
for i in "${!TOOL_LIST[@]}"; do
  tool="${TOOL_LIST[$i]}"
  pid="${PID_LIST[$i]}"
  set +e
  wait "$pid"
  rc=$?
  set -e
  RC_LIST[$i]=$rc

  # G-1 fix: read actual per-tool finish time instead of wall-clock-since-start.
  tool_end="$(cat "${LOG_LIST[$i]}.end" 2>/dev/null || date +%s)"
  duration="$((tool_end - start_epoch))"
  if [[ $rc -eq 0 ]]; then
    echo "[done] $tool  exit=0  (${duration}s)"
  else
    echo "[FAIL] $tool  exit=$rc  (${duration}s)"
    any_failed=1
  fi
done

end_epoch="$(date +%s)"
total_seconds="$((end_epoch - start_epoch))"

# ── Summary ───────────────────────────────────────────────────────────
echo
echo "═══════════════════════════════════════════════════════════════"
echo "  RESULTS ($total_seconds seconds total)"
echo "═══════════════════════════════════════════════════════════════"

for i in "${!TOOL_LIST[@]}"; do
  tool="${TOOL_LIST[$i]}"
  rc="${RC_LIST[$i]}"
  log="${LOG_LIST[$i]}"

  # Extract FINDINGS_SUMMARY from log if present
  findings=""
  if [[ -f "$log" ]]; then
    findings="$(grep -o 'FINDINGS_SUMMARY: .*' "$log" 2>/dev/null | tail -1 || true)"
  fi

  # Extract hard gate failures
  gate_fail=""
  if [[ -f "$log" ]]; then
    gate_fail="$(grep 'HARD_GATE_FAIL:' "$log" 2>/dev/null | head -1 || true)"
  fi

  status="OK"
  if [[ $rc -ne 0 ]]; then
    case $rc in
      3) status="FAIL (missing review basis)" ;;
      4) status="FAIL (missing citations)" ;;
      5) status="FAIL (missing phase equivalent)" ;;
      6) status="FAIL (sidecar validation)" ;;
      *) status="FAIL (exit $rc)" ;;
    esac
  fi

  printf "  %-8s  %s" "$tool" "$status"
  [[ -n "$findings" ]] && printf "  %s" "$findings"
  echo
  [[ -n "$gate_fail" ]] && echo "           $gate_fail"
done

echo "═══════════════════════════════════════════════════════════════"

# ── Proof graph aggregation ───────────────────────────────────────────
agg_rc=0
if [[ "$PROOF_GRAPH" == "true" && "$NO_AGGREGATE" != "true" && "$any_failed" -eq 0 ]]; then
  echo
  # G-5 fix: ensure base proof graph exists before aggregation.
  base_pg="$STORY_ARTIFACTS_DIR/$STORY/proof_graph.json"
  if [[ ! -f "$base_pg" ]]; then
    echo "Initializing base proof graph for $STORY..."
    init_script="$ROOT/python/proof_graph/init.py"
    if [[ -f "$init_script" ]]; then
      set +e
      python3 "$init_script" "$STORY" --output-dir "$STORY_ARTIFACTS_DIR/$STORY/" 2>&1
      init_rc=$?
      set -e
      if [[ $init_rc -ne 0 ]]; then
        echo "WARN: Could not initialize base proof graph (exit $init_rc) — skipping aggregation" >&2
        agg_rc=0
      fi
    else
      echo "WARN: init.py not found at $init_script — skipping aggregation" >&2
    fi
  fi

  # Only aggregate if base graph exists (either pre-existing or just created)
  if [[ -f "$base_pg" ]]; then
  echo "Running proof graph aggregation..."
  if [[ -x "$AGGREGATE_SCRIPT" ]]; then
    set +e
    STORY_ARTIFACTS_ROOT="$STORY_ARTIFACTS_DIR" "$AGGREGATE_SCRIPT" "$STORY"
    agg_rc=$?
    set -e
      if [[ $agg_rc -eq 0 ]]; then
        echo "Aggregation: OK"
      elif [[ $agg_rc -eq 20 ]]; then
        echo "Aggregation: TRADING HALT (exit 20)"
      else
        echo "Aggregation: FAILED (exit $agg_rc)"
      fi
    else
      echo "WARN: aggregate_proofs.sh not found at $AGGREGATE_SCRIPT" >&2
    fi
  fi
elif [[ "$PROOF_GRAPH" == "true" && "$any_failed" -ne 0 ]]; then
  echo
  echo "Skipping aggregation — one or more reviews failed."
  echo "Fix failures and re-run, or use --no-aggregate to force."
fi

# ── Artifact locations ────────────────────────────────────────────────
echo
echo "Artifacts:"
for tool in "${TOOL_LIST[@]}"; do
  artifact_path="$STORY_ARTIFACTS_DIR/$STORY/$tool/${tool}.${PROMPT_STYLE}.md"
  artifact_display="$(display_artifact_path "$artifact_path")"
  if [[ -f "$artifact_path" ]]; then
    echo "  $artifact_display"
  else
    echo "  $artifact_display  (not found — review may have failed)"
  fi
done

# ── Exit code ─────────────────────────────────────────────────────────
# G-2 fix: on failure, copy logs to artifacts dir (not world-readable /tmp),
# then let the EXIT trap clean up the temp dir.
if [[ $any_failed -ne 0 ]]; then
  fail_log_dir="$STORY_ARTIFACTS_DIR/$STORY/review_logs"
  mkdir -p "$fail_log_dir"
  cp "$LOG_DIR"/*.log "$fail_log_dir/" 2>/dev/null || true
  cp "$LOG_DIR"/*.log.end "$fail_log_dir/" 2>/dev/null || true
  echo
  echo "One or more reviews failed. Logs saved to: $(display_artifact_path "$fail_log_dir")/"
  exit 1
fi

if [[ $agg_rc -ne 0 ]]; then
  exit 3
fi

exit 0
