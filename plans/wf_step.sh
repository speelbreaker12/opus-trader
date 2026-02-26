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
PRD_FILE="$ROOT/plans/prd.json"
SCOPE_LOCK_DIR="${RECON_SCOPE_LOCK_DIR:-$ROOT/.wf/recon_scope_lock}"
SCOPE_LOCK_FILE="$SCOPE_LOCK_DIR/${STORY}.scope_lock.json"
REVIEW_LOGGED_SCRIPT="$ROOT/plans/review_logged.sh"
mkdir -p "$SCOPE_LOCK_DIR"

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

story_scope_json() {
  local scope_json
  scope_json="$(jq -c --arg sid "$STORY" '.items[]? | select(.id == $sid) | .scope' "$PRD_FILE" 2>/dev/null || true)"
  if [[ -z "$scope_json" || "$scope_json" == "null" ]]; then
    scope_json="$(jq -c --arg sid "$STORY" '.stories[$sid]? | .scope' "$PRD_FILE" 2>/dev/null || true)"
  fi
  printf '%s' "$scope_json"
}

scope_lock_hash() {
  local scope_json="$1"
  printf '%s' "$scope_json" | jq -S -c . | sha256sum | awk '{print $1}'
}

write_scope_lock() {
  local scope_json="$1"
  local scope_sha="$2"
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  jq -n \
    --arg schema "recon_scope_lock.v1" \
    --arg story "$STORY" \
    --arg lock_head "$HEAD_SHA" \
    --arg locked_at "$ts" \
    --arg scope_sha "$scope_sha" \
    --arg scope_source "$PRD_FILE" \
    --argjson scope "$scope_json" \
    '{schema_version: $schema, story_id: $story, lock_head_sha: $lock_head, locked_at: $locked_at, scope_source_file: $scope_source, scope_sha256: $scope_sha, scope: $scope}' \
    > "$SCOPE_LOCK_FILE"
}

check_scope_lock_matches() {
  local scope_json="$1"
  local current_scope_sha
  local lock_scope_sha
  local lock_story
  local lock_head
  local preflight_head

  if [[ ! -f "$SCOPE_LOCK_FILE" ]]; then
    echo "WF_STEP: scope lock missing for $STORY at R1 completion (expected $SCOPE_LOCK_FILE)" >&2
    return 1
  fi

  lock_story="$(jq -r '.story_id // empty' "$SCOPE_LOCK_FILE" 2>/dev/null || true)"
  lock_scope_sha="$(jq -r '.scope_sha256 // empty' "$SCOPE_LOCK_FILE" 2>/dev/null || true)"
  lock_head="$(jq -r '.lock_head_sha // empty' "$SCOPE_LOCK_FILE" 2>/dev/null || true)"
  if [[ "$lock_story" != "$STORY" || -z "$lock_scope_sha" || -z "$lock_head" ]]; then
    echo "WF_STEP: scope lock malformed for $STORY at $SCOPE_LOCK_FILE" >&2
    return 1
  fi

  current_scope_sha="$(scope_lock_hash "$scope_json")"
  if [[ "$current_scope_sha" != "$lock_scope_sha" ]]; then
    echo "WF_STEP: scope lock mismatch for $STORY — scope changed after preflight." >&2
    echo "  Re-run: plans/wf_step.sh $STORY preflight" >&2
    return 1
  fi

  preflight_head="$(jq -r '.head_sha // empty' "$(receipt_file preflight)" 2>/dev/null || true)"
  if [[ -n "$preflight_head" && "$lock_head" != "$preflight_head" ]]; then
    echo "WF_STEP: scope lock head mismatch for $STORY." >&2
    echo "  lock_head=$lock_head preflight_head=$preflight_head" >&2
    echo "  Re-run: plans/wf_step.sh $STORY preflight" >&2
    return 1
  fi
}

check_review_logged_sidecar_patch() {
  local missing=0
  local p
  local patterns=(
    'sidecar_schema="$root/specs/schemas/recon/review_artifact_sidecar.schema.json"'
    'cat > "$sidecar_file" <<SIDECAR_EOF'
    'validator="$root/plans/validate_recon_artifact.sh"'
    'if ! "$validator" review_artifact_sidecar "$sidecar_file"; then'
  )
  for p in "${patterns[@]}"; do
    if ! grep -qF -- "$p" "$REVIEW_LOGGED_SCRIPT"; then
      echo "WF_STEP: review_logged.sh missing required sidecar patch marker: $p" >&2
      missing=1
    fi
  done
  [[ "$missing" -eq 0 ]]
}

validate_receipt_story_ids() {
  local f
  local recorded_story

  for f in "$RECEIPT_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    recorded_story="$(jq -r '.story_id // empty' "$f" 2>/dev/null || true)"
    if [[ -n "$recorded_story" && "$recorded_story" != "$STORY" ]]; then
      echo "WF_STEP: receipt mismatch in $f: story_id=$recorded_story (expected=$STORY)" >&2
      return 1
    fi
  done
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

if ! validate_receipt_story_ids; then
  fail "one or more existing receipts in $RECEIPT_DIR do not match STORY=$STORY"
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

read_cycle1_path() {
  # Reads the explicit PATH: GREEN / PATH: YELLOW signal written by the cycle1 agent.
  # Returns 0 (green/zero-findings) if PATH: GREEN, 1 otherwise.
  # Falls back to cycle1_had_zero_findings() for pre-existing artifacts without the signal.
  local art_dir="$1"
  local ledger="$art_dir/cycle1/evidence_ledger.md"
  if [[ -f "$ledger" ]]; then
    local first_line
    first_line="$(head -1 "$ledger" 2>/dev/null || true)"
    case "$first_line" in
      "PATH: GREEN")
        return 0
        ;;
      "PATH: YELLOW")
        return 1
        ;;
      *)
        # Unrecognized signal in canonical path — fall back for legacy artifacts.
        echo "WF_STEP: unrecognized PATH signal in $ledger: '$first_line'; falling back to legacy findings detection" >&2
        cycle1_had_zero_findings "$art_dir"
        return $?
        ;;
    esac
  fi
  # No canonical evidence ledger — fall back to legacy text detection for backward compat
  echo "WF_STEP: no cycle1/evidence_ledger.md at $ledger; falling back to legacy findings detection" >&2
  cycle1_had_zero_findings "$art_dir"
}

verify_cycle1_citations() {
  # Pre-flight citation check for C1 review artifacts before writing cycle1 receipt.
  local art_dir="$1"
  local artifact
  local review_files=()
  local citations_ok=1
  local verifier="$ROOT/plans/verify_citations.sh"

  if [[ ! -x "$verifier" ]]; then
    echo "WF_STEP: citation validator missing or not executable at $verifier" >&2
    return 1
  fi

  for d in "$art_dir/codex" "$art_dir/opus" "$art_dir/kimi"; do
    if [[ -d "$d" ]]; then
      while IFS= read -r artifact; do
        [[ -f "$artifact" ]] || continue
        review_files+=("$artifact")
      done < <(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null | LC_ALL=C sort)
    fi
  done

  if [[ "${#review_files[@]}" -eq 0 ]]; then
    echo "WF_STEP: no cycle1 review artifacts found for citation check in $art_dir" >&2
    return 1
  fi

  for artifact in "${review_files[@]}"; do
    if ! "$verifier" --artifact "$artifact" --mode C1 --json; then
      echo "WF_STEP: citation pre-gate failed for $artifact" >&2
      citations_ok=0
      break
    fi
  done

  [[ "$citations_ok" -eq 1 ]]
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

    scope_json="$(story_scope_json)"
    if [[ -z "$scope_json" || "$scope_json" == "null" ]]; then
      echo "WF_STEP: preflight scope lock failed — story scope missing in $PRD_FILE for $STORY" >&2
      exit 3
    fi
    scope_sha="$(scope_lock_hash "$scope_json")"
    write_scope_lock "$scope_json" "$scope_sha"
    echo "WF_STEP: scope lock recorded at $SCOPE_LOCK_FILE"
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
    scope_json="$(story_scope_json)"
    if [[ -z "$scope_json" || "$scope_json" == "null" ]]; then
      echo "WF_STEP: cycle1 requires scope lock data for $STORY — story scope missing in $PRD_FILE" >&2
      exit 3
    fi
    if ! check_scope_lock_matches "$scope_json"; then
      exit 3
    fi

    if ! check_review_logged_sidecar_patch; then
      echo "WF_STEP: blocking cycle1 — review_logged.sh sidecar patch not present on HEAD" >&2
      echo "  Ensure review_logged.sh includes sidecar schema generation + sidecar validation before cycle1 runs." >&2
      exit 3
    fi

    # Evidence ledger check (v3.0): verify R1 output exists before Cycle 1
    # Accepts multiple naming patterns: canonical (<ID>_reconciliation.md), legacy (evidence_ledger.*), or preflight artifacts
    # Also checks slice-level recon dir (reviews/reconciliations/<SLICE>/) for stories that store ledgers there
    slice_id="${STORY%%-*}"
    evidence_found=false
    for candidate in \
      "$story_art/${STORY}_reconciliation.md" \
      "$story_art/${STORY}_reconciliation.json" \
      "$story_art/evidence_ledger.json" \
      "$story_art/evidence_ledger.md" \
      "$story_art/preflight/audit.md" \
      "$ROOT/reviews/reconciliations/$slice_id/${STORY}_reconciliation.md" \
      "$ROOT/reviews/reconciliations/$slice_id/${STORY}_reconciliation.json"; do
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
      echo "    - $story_art/preflight/audit.md" >&2
      echo "    - $ROOT/reviews/reconciliations/$slice_id/${STORY}_reconciliation.md" >&2
      echo "    - $ROOT/reviews/reconciliations/$slice_id/${STORY}_reconciliation.json" >&2
      echo "  Run Phase R1 (preflight/implement) before recording cycle1 receipt" >&2
      exit 6
    fi

    # Hard citation gate: all cycle1 reviews must pass pre-existing citation checks.
    if ! verify_cycle1_citations "$story_art"; then
      exit 3
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
    if read_cycle1_path "$story_art"; then
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
    # Prefer manifest-driven C2 mode when available; legacy fallback uses recon mode signals.
    manifest_cycle2_path="$story_art/external/cycle2/$STORY/R7_EXTERNAL_MANIFEST.json"
    cycle2_mode=""
    if [[ -f "$manifest_cycle2_path" ]]; then
      cycle2_mode="$(jq -r '.cycle2_path.mode // empty' "$manifest_cycle2_path" 2>/dev/null || true)"
      case "$cycle2_mode" in
        ""|null)
          echo "WF_STEP: cycle2_path.mode missing in $manifest_cycle2_path; assuming dual_combo for legacy compatibility"
          ;;
        dual_combo)
          echo "WF_STEP: cycle2_path.mode=dual_combo for $STORY -> requiring full dual-style cycle2 coverage"
          ;;
        recon_clean_single)
          min_reviews=1
          echo "WF_STEP: cycle2_path.mode=recon_clean_single for $STORY -> requiring single-style cycle2 coverage"
          ;;
        *)
          echo "WF_STEP: unsupported cycle2_path.mode '$cycle2_mode' in $manifest_cycle2_path" >&2
          exit 3
          ;;
      esac
    elif [[ "$WF_RECON_MODE" -eq 1 ]]; then
      # GREEN path: recon + cycle1 clean + fix didn't change code → abbreviated (1 review)
      # YELLOW/RED path: findings exist OR fix changed code → full (2 reviews)
      fix_receipt="$(receipt_file fix)"
      fix_code_changed="$(jq -r '.code_changed // "false"' "$fix_receipt" 2>/dev/null || echo "false")"
      if read_cycle1_path "$story_art" && [[ "$fix_code_changed" != "true" ]]; then
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
    # Basis-label check: verify >=1 artifact has FIX_DIFF review basis.
    # Without this, C1 artifacts (STORY_SCOPE basis) satisfy the cycle2 gate spuriously.
    c2_basis_count=0
    for d in "$story_art/codex" "$story_art/opus" "$story_art/kimi"; do
      if [[ -d "$d" ]]; then
        while IFS= read -r f; do
          sidecar="${f%.md}.sidecar.json"
          if [[ -f "$sidecar" ]]; then
            sidecar_basis="$(jq -r '.review_basis // empty' "$sidecar" 2>/dev/null || true)"
            case "$sidecar_basis" in
              FIX_DIFF_AT_REGRESSION|"FIX_DIFF + AT_REGRESSION (Cycle 2)")
                c2_basis_count=$((c2_basis_count + 1))
                continue
                ;;
            esac
          fi
          # Legacy fallback: parse canonical review basis line in markdown header.
          if grep -Eqm1 '^[[:space:]-]*Review basis:[[:space:]]*FIX_DIFF([[:space:]]*\+[[:space:]]*AT_REGRESSION[[:space:]]*\(Cycle 2\))?[[:space:]]*$' "$f" 2>/dev/null; then
            c2_basis_count=$((c2_basis_count + 1))
          fi
        done < <(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null)
      fi
    done
    if [[ "$c2_basis_count" -lt 1 ]]; then
      echo "WF_STEP: cycle2 gate requires >=1 review artifact with 'FIX_DIFF' review basis — none found" >&2
      echo "  in $story_art/{codex,opus,kimi}/" >&2
      echo "  C1 artifacts (STORY_SCOPE basis) do not satisfy this gate." >&2
      echo "  Run cycle2 reviews via review_logged.sh --cycle C2 before recording this receipt." >&2
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
