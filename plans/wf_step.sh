#!/usr/bin/env bash
set -euo pipefail

# Workflow step progress tracker.
#
# Tracks which steps are done, enforces ordering, writes simple JSON receipts.
#
# Usage: plans/wf_step.sh <STORY_ID> <step> [options]
#
# Steps (in order — each requires the previous receipt):
#   preflight      — record HEAD as baseline
#   implement      — validate code changed since preflight
#   self_review    — validate self-review artifacts exist
#   cycle1         — validate cycle 1 review artifact exists
#   fix            — validate fixes applied (code changed since cycle1)
#   cycle2         — validate cycle 2 review artifact exists
#   resolution     — validate review resolution exists
#   verify_full    — validate verify.sh full passed with matching HEAD
#   pass           — final gate (all 8 preceding receipts must exist)
#
# Options:
#   --check-only   Exit 0 if step receipt exists, non-zero if not (no validation, no writing)
#   --dry-run      Validate prerequisites but don't write receipt
#   --status       Show current receipt chain status
#   --reset        Delete all receipts for this story (requires --yes)
#
# Receipt location: .wf/receipts/<STORY_ID>/<NN>_<step>.json
#
# Exit codes:
#   0 — step completed, receipt written
#   1 — prerequisite missing (run the required step first)
#   2 — usage/setup error
#   3 — step validation failed (inputs not ready)
#   5 — HEAD mismatch

STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full pass)

usage() {
  cat <<'EOF'
Usage: plans/wf_step.sh <STORY_ID> <step> [--dry-run|--status|--reset]

Steps (in order):
  preflight      Record HEAD as baseline
  implement      Validate code changed since preflight
  self_review    Validate self-review artifacts exist
  cycle1         Validate cycle 1 review artifact exists
  fix            Validate fixes applied since cycle1
  cycle2         Validate cycle 2 review artifact exists
  resolution     Validate review resolution exists
  verify_full    Validate verify.sh full passed
  pass           Final gate (all 8 receipts required)

Options:
  --check-only   Check if step receipt exists (exit 0=yes, 1=no)
  --dry-run      Validate only, don't write receipt
  --status       Show receipt chain status
  --reset        Delete all receipts for story (requires --yes)
EOF
}

die()  { echo "WF_STEP ERROR: $*" >&2; exit 2; }
fail() { echo "WF_STEP BLOCKED: $*" >&2; exit 1; }

# ── Parse args ──────────────────────────────────────────────────────

STORY="${1:-}"
CHECK_ONLY=0
DRY_RUN=0
STATUS_MODE=0
RESET_MODE=0
YES=0
STEP=""

shift $(( $# >= 1 ? 1 : 0 ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)   CHECK_ONLY=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --status)       STATUS_MODE=1 ;;
    --reset)        RESET_MODE=1 ;;
    --yes)          YES=1 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1" ;;
    *)
      if [[ -z "$STEP" ]]; then
        STEP="$1"
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[[ -n "$STORY" ]] || { usage >&2; exit 2; }

# Security: STORY_ID validation (prevent path traversal)
if [[ ! "$STORY" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  die "invalid STORY_ID '$STORY' — must match ^[A-Za-z0-9][A-Za-z0-9_-]*\$"
fi

# Close stdin to prevent any commands from blocking on input
exec < /dev/null

# ── Reconciliation mode ──────────────────────────────────────────────
WF_RECON_MODE="${WF_RECON_MODE:-0}"
if [[ "$WF_RECON_MODE" != "0" && "$WF_RECON_MODE" != "1" ]]; then
  die "WF_RECON_MODE must be 0 or 1, got: $WF_RECON_MODE"
fi

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$ROOT"

RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"
mkdir -p "$RECEIPT_DIR"

art_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"
if [[ "$art_root" != /* ]]; then art_root="$ROOT/$art_root"; fi
story_art="$art_root/$STORY"

# ── Step index helpers ──────────────────────────────────────────────

step_index() {
  local s="$1"
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$s" ]] && { echo "$i"; return 0; }
  done
  return 1
}

step_is_valid() {
  step_index "$1" >/dev/null 2>&1
}

receipt_file() {
  local s="$1"
  local idx
  idx="$(step_index "$s")"
  printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$idx" "$s"
}

# ── Status mode ─────────────────────────────────────────────────────

if [[ "$STATUS_MODE" -eq 1 ]]; then
  echo "Receipt chain for $STORY:"
  echo "─────────────────────────────"
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo '?')"
  for s in "${STEPS[@]}"; do
    f="$(receipt_file "$s")"
    if [[ -f "$f" ]]; then
      r_head="$(jq -r '.head_sha // "?"' "$f" 2>/dev/null || echo '?')"
      r_ts="$(jq -r '.timestamp_utc // "?"' "$f" 2>/dev/null || echo '?')"
      head_match=""
      [[ "$r_head" != "$head_sha" ]] && head_match=" (HEAD MISMATCH!)"
      printf '  [DONE] %-15s  %s  %s%s\n' "$s" "$r_ts" "$r_head" "$head_match"
    else
      printf '  [    ] %-15s\n' "$s"
    fi
  done
  echo "─────────────────────────────"
  echo "Current HEAD: $head_sha"
  exit 0
fi

# ── Reset mode ──────────────────────────────────────────────────────

if [[ "$RESET_MODE" -eq 1 ]]; then
  count="$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$count" -eq 0 ]]; then
    echo "No receipts to reset for $STORY"
    exit 0
  fi
  if [[ "$YES" -ne 1 ]]; then
    echo "WF_STEP: reset will delete $count receipt(s) for $STORY" >&2
    echo "  Add --yes to confirm: plans/wf_step.sh $STORY --reset --yes" >&2
    exit 2
  fi
  echo "Deleting $count receipt(s) for $STORY in $RECEIPT_DIR"
  rm -f "$RECEIPT_DIR"/*.json
  echo "Reset complete."
  exit 0
fi

# ── Check-only mode (receipt probe, no validation/writing) ─────────

if [[ "$CHECK_ONLY" -eq 1 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
  f="$(receipt_file "$STEP")"
  if [[ -f "$f" ]]; then
    exit 0
  else
    exit 1
  fi
fi

# ── Validate step name (not required for --status/--reset) ──────────

if [[ "$STATUS_MODE" -eq 0 && "$RESET_MODE" -eq 0 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
fi

HEAD_SHA="$(git rev-parse HEAD)"
STEP_IDX="$(step_index "$STEP")"

# ── Validate prerequisites (previous receipts must exist) ───────────

if [[ "$STEP_IDX" -gt 0 ]]; then
  for i in $(seq 0 $((STEP_IDX - 1))); do
    local_step="${STEPS[$i]}"
    f="$(receipt_file "$local_step")"
    if [[ ! -f "$f" ]]; then
      fail "missing receipt for step '$local_step' — run: plans/wf_step.sh $STORY $local_step"
    fi
  done
fi

# ── Step-specific input validation ──────────────────────────────────

get_base_head() {
  local pf
  pf="$(receipt_file preflight)"
  if [[ ! -f "$pf" ]]; then
    die "no preflight receipt — cannot determine BASE_HEAD"
  fi
  jq -r '.head_sha' "$pf" 2>/dev/null || die "cannot read head_sha from preflight receipt"
}

require_code_change_since_base() {
  local base_head="$1"
  local diff_output
  diff_output="$(git diff --name-only "$base_head"..HEAD 2>/dev/null || true)"
  [[ -n "$diff_output" ]]
}

cycle1_had_zero_findings() {
  # Shared detection: returns 0 if cycle1 review had 0 high-severity findings.
  # Used by both fix and cycle2 steps. Do NOT duplicate this logic.
  #
  # Prefers the structured FINDINGS_SUMMARY line emitted by review_logged.sh.
  # Falls back to free-text regex for legacy review artifacts.
  # Fail-closed: if no review artifacts exist, returns 1 (findings assumed).
  local art_dir="$1"
  local review_found=0
  for d in "$art_dir/codex" "$art_dir/opus" "$art_dir/kimi"; do
    [[ -d "$d" ]] || continue
    while IFS= read -r rf; do
      [[ -f "$rf" ]] || continue
      review_found=1

      # Prefer structured line: FINDINGS_SUMMARY: P0=N P1=N P2=N
      local summary_line
      summary_line="$(grep -m1 '^FINDINGS_SUMMARY:' "$rf" 2>/dev/null || true)"
      if [[ -n "$summary_line" ]]; then
        local p0 p1
        p0="$(echo "$summary_line" | sed -n 's/.*P0=\([0-9]*\).*/\1/p')"
        p1="$(echo "$summary_line" | sed -n 's/.*P1=\([0-9]*\).*/\1/p')"
        p0="${p0:-999}"; p1="${p1:-999}"
        if [[ "$p0" -eq 0 && "$p1" -eq 0 ]]; then
          return 0
        fi
        return 1
      fi

      # Legacy fallback: free-text regex (less reliable)
      if grep -qiE '(\b0 findings|no findings|no issues|P0: 0.*P1: 0)' "$rf" 2>/dev/null; then
        return 0
      fi
    done < <(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) 2>/dev/null | LC_ALL=C sort)
  done
  # Fail-closed: no reviews found → assume findings exist
  return 1
}

case "$STEP" in
  preflight)
    # First step — record HEAD as BASE_HEAD.
    if [[ "$WF_RECON_MODE" -eq 1 ]]; then
      # Recon mode: verify story already has passes=true in PRD (fail-closed)
      prd_file="${PRD_FILE:-$ROOT/plans/prd.json}"
      if [[ ! -f "$prd_file" ]]; then
        echo "WF_STEP: recon mode blocked — PRD file not found at $prd_file" >&2
        exit 3
      fi
      story_passes="$(jq -r --arg id "$STORY" '.items[] | select(.id==$id) | .passes // false' "$prd_file" 2>/dev/null || echo "false")"
      if [[ "$story_passes" != "true" ]]; then
        echo "WF_STEP: recon mode blocked — story $STORY does not have passes=true" >&2
        echo "  Reconciliation is only for already-passing stories" >&2
        exit 3
      fi
    fi

    # Validate premortem via gate script (content depth, not just existence)
    premortem_file="$ROOT/reviews/premortems/${STORY}_premortem.md"
    premortem_gate="$ROOT/plans/premortem_gate.sh"
    if [[ -f "$premortem_file" && -x "$premortem_gate" ]]; then
      if ! "$premortem_gate" "$STORY" 2>&1; then
        echo "WF_STEP: premortem gate failed — fix premortem before proceeding" >&2
        exit 3
      fi
    elif [[ -f "$premortem_file" ]]; then
      # Fallback: minimal carry-forward check if gate script missing
      if ! grep -q '^Prior Postmortem: ' "$premortem_file"; then
        echo "WF_STEP: premortem missing required line: 'Prior Postmortem: <path or NONE>'" >&2
        exit 3
      fi
      if ! grep -q '^Reused Guardrail: ' "$premortem_file"; then
        echo "WF_STEP: premortem missing required line: 'Reused Guardrail: <rule or NONE>'" >&2
        exit 3
      fi
    fi

    # PREMORTEM_READY gate (v3.0): comprehensive readiness check
    premortem_ready_script="$ROOT/plans/premortem_ready.sh"
    if [[ -x "$premortem_ready_script" ]]; then
      if ! "$premortem_ready_script" "$STORY" 2>&1; then
        echo "WF_STEP: PREMORTEM_READY gate failed — resolve issues before proceeding" >&2
        exit 3
      fi
    fi
    ;;

  implement)
    if [[ "$WF_RECON_MODE" -eq 1 ]]; then
      echo "WF_STEP: reconciliation mode — bypassing diff requirement" >&2
    else
      base_head="$(get_base_head)"
      if ! require_code_change_since_base "$base_head"; then
        echo "WF_STEP: no code changes since preflight base ($base_head)" >&2
        exit 3
      fi
    fi
    ;;

  self_review)
    sr_dir="$story_art/self_review"
    if [[ ! -d "$sr_dir" ]]; then
      echo "WF_STEP: no self_review directory at $sr_dir" >&2
      exit 3
    fi
    sr_count="$(find "$sr_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "$sr_count" -lt 1 ]]; then
      echo "WF_STEP: no self-review artifacts found in $sr_dir" >&2
      exit 3
    fi
    ;;

  cycle1)
    # Evidence ledger check (v3.0): verify R1 output exists before Cycle 1
    # Accepts multiple naming patterns: canonical (<ID>_reconciliation.md), legacy (evidence_ledger.*), or preflight artifacts
    evidence_found=false
    for candidate in \
      "$story_art/${STORY}_reconciliation.md" \
      "$story_art/${STORY}_reconciliation.json" \
      "$story_art/evidence_ledger.json" \
      "$story_art/evidence_ledger.md"; do
      if [[ -f "$candidate" ]]; then
        evidence_found=true
        break
      fi
    done
    if [[ "$evidence_found" == "false" ]]; then
      # No canonical evidence ledger found — fail hard (no wildcard fallback)
      echo "WF_STEP: no evidence ledger found for $STORY" >&2
      echo "  Expected one of:" >&2
      echo "    - $story_art/${STORY}_reconciliation.md" >&2
      echo "    - $story_art/${STORY}_reconciliation.json" >&2
      echo "    - $story_art/evidence_ledger.json" >&2
      echo "    - $story_art/evidence_ledger.md" >&2
      echo "  Run Phase R1 (preflight/implement) before recording cycle1 receipt" >&2
      exit 6
    fi

    review_count=0
    for d in "$story_art/codex" "$story_art/opus" "$story_art/kimi"; do
      if [[ -d "$d" ]]; then
        # Count both canonical (<tool>.<style>.md) and legacy (<stamp>_review.md) artifacts
        c="$(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null | wc -l | tr -d '[:space:]')"
        review_count=$((review_count + c))
      fi
    done
    if [[ "$review_count" -lt 1 ]]; then
      echo "WF_STEP: no cycle 1 review artifact found in $story_art/{codex,opus,kimi}/" >&2
      exit 3
    fi
    ;;

  fix)
    cycle1_file="$(receipt_file cycle1)"
    cycle1_head="$(jq -r '.head_sha' "$cycle1_file" 2>/dev/null || echo '')"
    if [[ -z "$cycle1_head" ]]; then
      die "cannot read head_sha from cycle1 receipt"
    fi

    # Determine code_changed for receipt (deterministic, used by cycle2 escalation)
    FIX_CODE_CHANGED="false"
    if cycle1_had_zero_findings "$story_art"; then
      echo "WF_STEP: cycle1 had 0 findings — fix step passes with no code changes" >&2
    else
      changed_files="$(git diff --name-only "$cycle1_head"..HEAD 2>/dev/null || true)"
      if [[ -z "$changed_files" ]]; then
        # Fallback: check working tree + staged separately with newline separator
        wt_changes="$(git diff --name-only 2>/dev/null || true)"
        staged_changes="$(git diff --cached --name-only 2>/dev/null || true)"
        changed_files="${wt_changes}${wt_changes:+$'\n'}${staged_changes}"
      fi
      non_artifact_changes="$(echo "$changed_files" | grep -vE '^(artifacts/|\.wf/|plans/prd\.json$|plans/progress)' || true)"

      if [[ -z "$non_artifact_changes" ]]; then
        echo "WF_STEP: no non-artifact code changes since cycle1 receipt (HEAD=$cycle1_head)" >&2
        echo "  Only artifact/metadata files changed. Fix the actual code." >&2
        exit 3
      fi
      FIX_CODE_CHANGED="true"
    fi
    ;;

  cycle2)
    min_reviews=2
    # GREEN path: recon + cycle1 clean + fix didn't change code → abbreviated (1 review)
    # YELLOW/RED path: findings exist OR fix changed code → full (2 reviews)
    if [[ "$WF_RECON_MODE" -eq 1 ]]; then
      fix_receipt="$(receipt_file fix)"
      fix_code_changed="$(jq -r '.code_changed // "false"' "$fix_receipt" 2>/dev/null || echo "false")"
      if cycle1_had_zero_findings "$story_art" && [[ "$fix_code_changed" != "true" ]]; then
        min_reviews=1
        echo "WF_STEP: recon GREEN path — abbreviated cycle2 (min_reviews=1)" >&2
      elif [[ "$fix_code_changed" == "true" ]]; then
        echo "WF_STEP: fix step changed code — full cycle2 required (min_reviews=2)" >&2
      fi
    fi
    review_count=0
    for d in "$story_art/codex" "$story_art/opus" "$story_art/kimi"; do
      if [[ -d "$d" ]]; then
        # Count both canonical and legacy artifacts, excluding symlinks
        c="$(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null | wc -l | tr -d '[:space:]')"
        review_count=$((review_count + c))
      fi
    done
    if [[ "$review_count" -lt "$min_reviews" ]]; then
      echo "WF_STEP: need at least $min_reviews review artifacts in $story_art/{codex,opus,kimi}/" >&2
      exit 3
    fi
    ;;

  resolution)
    res_file="$story_art/review_resolution.md"
    if [[ ! -f "$res_file" ]]; then
      echo "WF_STEP: no review_resolution.md at $res_file" >&2
      exit 3
    fi
    if ! grep -q 'Blocking addressed: YES' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Blocking addressed: YES'" >&2
      exit 3
    fi
    if ! grep -q 'Remaining findings: BLOCKING=0' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Remaining findings: BLOCKING=0'" >&2
      exit 3
    fi
    ;;

  verify_full)
    latest_verify="$(ls -dt "$ROOT"/artifacts/verify/*/ 2>/dev/null | head -1 || true)"
    if [[ -z "$latest_verify" ]]; then
      echo "WF_STEP: no verify artifacts found in artifacts/verify/" >&2
      exit 3
    fi
    meta_file="${latest_verify%/}/verify.meta.json"
    if [[ ! -f "$meta_file" ]]; then
      echo "WF_STEP: no verify.meta.json in $latest_verify" >&2
      exit 3
    fi
    verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_mode" != "full" ]]; then
      echo "WF_STEP: verify was mode=$verify_mode, need mode=full" >&2
      exit 3
    fi
    verify_head="$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_head" != "$HEAD_SHA" ]]; then
      echo "WF_STEP: verify HEAD mismatch (verify=$verify_head current=$HEAD_SHA)" >&2
      exit 5
    fi
    if [[ -f "${latest_verify%/}/FAILED_GATE" ]]; then
      echo "WF_STEP: FAILED_GATE present in $latest_verify" >&2
      exit 3
    fi
    ;;

  pass)
    # Final gate — validate all 8 preceding receipts exist.
    for i in $(seq 0 7); do
      s="${STEPS[$i]}"
      f="$(receipt_file "$s")"
      if [[ ! -f "$f" ]]; then
        fail "missing receipt for step '$s' — run: plans/wf_step.sh $STORY $s"
      fi
    done
    echo "WF_STEP: all 8 receipts present for $STORY"
    echo "WF_STEP: ready for prd_set_pass.sh"
    exit 0
    ;;
esac

# ── Dry run ─────────────────────────────────────────────────────────

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "WF_STEP DRY RUN: step '$STEP' prerequisites OK, would write receipt"
  echo "  HEAD: $HEAD_SHA"
  exit 0
fi

# ── Write receipt ───────────────────────────────────────────────────

receipt_path="$(receipt_file "$STEP")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Build relaxation note for recon mode (empty string for normal mode).
# Note: YELLOW-escalated steps run WITHOUT WF_RECON_MODE (supervisor drops it),
# so their receipts have recon_mode=false by design. The fix receipt's
# code_changed=true serves as the audit trail for escalation.
recon_note=""
if [[ "$WF_RECON_MODE" -eq 1 ]]; then
  case "$STEP" in
    implement) recon_note="implement_diff_check_skipped" ;;
    cycle2)    recon_note="min_reviews_relaxed_to_1" ;;
    *)         recon_note="" ;;
  esac
fi

# Build step-specific extra fields
fix_code_changed="${FIX_CODE_CHANGED:-}"

jq -n \
  --arg story_id "$STORY" \
  --arg step_name "$STEP" \
  --argjson step_index "$STEP_IDX" \
  --arg head_sha "$HEAD_SHA" \
  --arg timestamp_utc "$ts" \
  --argjson recon_mode "$WF_RECON_MODE" \
  --arg recon_relaxation "$recon_note" \
  --arg fix_code_changed "$fix_code_changed" \
  '{
    story_id: $story_id,
    step_name: $step_name,
    step_index: $step_index,
    head_sha: $head_sha,
    timestamp_utc: $timestamp_utc,
    recon_mode: ($recon_mode == 1)
  }
  + (if $recon_relaxation != "" then {recon_relaxation: $recon_relaxation} else {} end)
  + (if $fix_code_changed != "" then {code_changed: ($fix_code_changed == "true")} else {} end)' > "$receipt_path"

echo "WF_STEP: [$STEP] receipt written → $receipt_path"
echo "  HEAD: $HEAD_SHA"
