#!/usr/bin/env bash
set -euo pipefail

# Workflow step progress tracker.
#
# Tracks which steps are done, enforces ordering, writes simple JSON receipts.
#
# Usage:
#   plans/wf_step.sh <STORY_ID> <step> [options]
#   plans/wf_step.sh <STORY_ID> --run-sequence [--stop-on-blocker] [options]
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
#   --run-sequence Run ordered steps from <step> (or preflight if omitted) to pass
#   --stop-on-blocker
#                 Only valid with --run-sequence; stop at first non-zero step
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
       plans/wf_step.sh <STORY_ID> --run-sequence [--stop-on-blocker] [<step>] [--dry-run]

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
  --run-sequence Run ordered steps from <step> (or preflight) through pass
  --stop-on-blocker
                Stop sequence mode at first non-zero step exit
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
RUN_SEQUENCE=0
STOP_ON_BLOCKER=0
STATUS_MODE=0
RESET_MODE=0
YES=0
STEP=""

shift $(( $# >= 1 ? 1 : 0 ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check-only)   CHECK_ONLY=1 ;;
    --dry-run)      DRY_RUN=1 ;;
    --run-sequence) RUN_SEQUENCE=1 ;;
    --stop-on-blocker) STOP_ON_BLOCKER=1 ;;
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

if [[ "$STOP_ON_BLOCKER" -eq 1 && "$RUN_SEQUENCE" -ne 1 ]]; then
  die "--stop-on-blocker requires --run-sequence"
fi

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

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  return 1
}

is_fix_diff_basis() {
  local basis="$1"
  case "$basis" in
    FIX_DIFF_AT_REGRESSION|"FIX_DIFF + AT_REGRESSION (Cycle 2)") return 0 ;;
  esac
  return 1
}

verify_review_artifact_provenance() {
  # Ensure artifacts used for cycle gates are produced by review_logged-style output
  # with sidecar provenance and logger marker.
  local artifact="$1"
  local allowed_phases="${2:-R3|R7}"
  local required_basis="${3:-any}" # any | story_scope | fix_diff
  local sidecar="${artifact%.md}.sidecar.json"
  local schema_version review_type basis_line_present phase_eq sidecar_basis sidecar_tool
  local sidecar_md_sha actual_md_sha sidecar_md_path artifact_abs phase_ok=1

  if [[ ! -f "$sidecar" ]]; then
    echo "WF_STEP: provenance sidecar missing for $artifact (expected $sidecar)" >&2
    return 1
  fi
  if ! jq empty "$sidecar" >/dev/null 2>&1; then
    echo "WF_STEP: provenance sidecar is not valid JSON: $sidecar" >&2
    return 1
  fi

  schema_version="$(jq -r '.schema_version // empty' "$sidecar" 2>/dev/null || true)"
  review_type="$(jq -r '.review_type // empty' "$sidecar" 2>/dev/null || true)"
  basis_line_present="$(jq -r '.basis_line_present // empty' "$sidecar" 2>/dev/null || true)"
  phase_eq="$(jq -r '.phase_equivalent // empty' "$sidecar" 2>/dev/null || true)"
  sidecar_basis="$(jq -r '.review_basis // empty' "$sidecar" 2>/dev/null || true)"
  sidecar_tool="$(jq -r '.tool // empty' "$sidecar" 2>/dev/null || true)"
  sidecar_md_sha="$(jq -r '.markdown_sha256 // empty' "$sidecar" 2>/dev/null || true)"
  sidecar_md_path="$(jq -r '.markdown_path // empty' "$sidecar" 2>/dev/null || true)"

  if [[ "$schema_version" != "review_artifact_sidecar.v1" ]]; then
    echo "WF_STEP: provenance sidecar schema_version must be review_artifact_sidecar.v1: $sidecar" >&2
    return 1
  fi
  if [[ "$review_type" != "external" ]]; then
    echo "WF_STEP: provenance sidecar review_type must be external: $sidecar" >&2
    return 1
  fi
  if [[ "$basis_line_present" != "true" ]]; then
    echo "WF_STEP: provenance sidecar basis_line_present must be true: $sidecar" >&2
    return 1
  fi

  phase_ok=1
  for p in ${allowed_phases//|/ }; do
    if [[ "$phase_eq" == "$p" ]]; then
      phase_ok=0
      break
    fi
  done
  if [[ "$phase_ok" -ne 0 ]]; then
    echo "WF_STEP: provenance sidecar phase_equivalent '$phase_eq' not in [$allowed_phases]: $sidecar" >&2
    return 1
  fi

  case "$required_basis" in
    any) ;;
    story_scope)
      if [[ "$sidecar_basis" != "STORY_SCOPE" ]]; then
        echo "WF_STEP: provenance sidecar review_basis must be STORY_SCOPE for C1: $sidecar" >&2
        return 1
      fi
      ;;
    fix_diff)
      if ! is_fix_diff_basis "$sidecar_basis"; then
        echo "WF_STEP: provenance sidecar review_basis must be FIX_DIFF for C2: $sidecar" >&2
        return 1
      fi
      ;;
    *)
      echo "WF_STEP: internal error — unknown required provenance basis: $required_basis" >&2
      return 1
      ;;
  esac

  actual_md_sha="$(sha256_file "$artifact" 2>/dev/null || true)"
  if [[ -z "$actual_md_sha" ]]; then
    echo "WF_STEP: unable to compute markdown sha256 for $artifact" >&2
    return 1
  fi
  if [[ "$sidecar_md_sha" != "$actual_md_sha" ]]; then
    echo "WF_STEP: provenance sidecar markdown_sha256 mismatch for $artifact" >&2
    return 1
  fi

  artifact_abs="$artifact"
  if [[ "$artifact_abs" != /* ]]; then
    artifact_abs="$ROOT/$artifact_abs"
  fi
  if [[ -n "$sidecar_md_path" && "$sidecar_md_path" != "$artifact" && "$sidecar_md_path" != "$artifact_abs" ]]; then
    if [[ ! -e "$sidecar_md_path" || ! "$sidecar_md_path" -ef "$artifact" ]]; then
      echo "WF_STEP: provenance sidecar markdown_path mismatch for $artifact" >&2
      return 1
    fi
  fi

  local expected_tool
  expected_tool="$(basename "$(dirname "$artifact")")"
  if [[ -z "$sidecar_tool" || "$sidecar_tool" == "null" || "$sidecar_tool" != "$expected_tool" ]]; then
    echo "WF_STEP: provenance sidecar tool mismatch for $artifact (expected $expected_tool)" >&2
    return 1
  fi

  if ! grep -Eq 'artifact_provenance:[[:space:]]*"logger-v2"' "$artifact" 2>/dev/null; then
    echo "WF_STEP: review artifact missing logger-v2 provenance marker: $artifact" >&2
    return 1
  fi

  return 0
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

run_recon_precheck() {
  local step_name="$1"
  local precheck_script="$ROOT/plans/recon_precheck.sh"
  if [[ ! -x "$precheck_script" ]]; then
    echo "WF_STEP: recon precheck missing or not executable at $precheck_script" >&2
    return 1
  fi
  if ! "$precheck_script" "$STORY"; then
    echo "WF_STEP: recon precheck failed for $STORY before step '$step_name'" >&2
    return 1
  fi
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

if [[ "$STATUS_MODE" -eq 0 && "$RESET_MODE" -eq 0 && "$RUN_SEQUENCE" -eq 0 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
fi

if [[ "$RUN_SEQUENCE" -eq 1 ]]; then
  if [[ "$STATUS_MODE" -eq 1 || "$RESET_MODE" -eq 1 || "$CHECK_ONLY" -eq 1 ]]; then
    die "--run-sequence cannot be combined with --status, --reset, or --check-only"
  fi
  if [[ -n "$STEP" ]]; then
    step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
  else
    STEP="preflight"
  fi

  start_idx="$(step_index "$STEP")"
  end_idx="$(( ${#STEPS[@]} - 1 ))"
  seq_rc=0
  for i in $(seq "$start_idx" "$end_idx"); do
    seq_step="${STEPS[$i]}"
    child_cmd=(bash "$ROOT/plans/wf_step.sh" "$STORY" "$seq_step")
    if [[ "$DRY_RUN" -eq 1 ]]; then
      child_cmd+=(--dry-run)
    fi
    echo "WF_STEP ORCH: running step '$seq_step' for $STORY" >&2
    set +e
    "${child_cmd[@]}"
    rc=$?
    set -e
    if [[ "$rc" -ne 0 ]]; then
      seq_rc="$rc"
      if [[ "$STOP_ON_BLOCKER" -eq 1 ]]; then
        echo "WF_STEP ORCH: stop-on-blocker active — halted at step '$seq_step' (exit=$rc)" >&2
        exit "$rc"
      fi
    fi
  done
  exit "$seq_rc"
fi

HEAD_SHA="$(git rev-parse HEAD)"
STEP_IDX="$(step_index "$STEP")"

if [[ "$WF_RECON_MODE" -eq 1 ]]; then
  if ! run_recon_precheck "$STEP"; then
    exit 3
  fi
fi

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
    local line
    while IFS= read -r line || [[ -n "$line" ]]; do
      [[ -n "$line" ]] || continue
      if [[ "$line" =~ ^PATH:[[:space:]]*(GREEN|YELLOW)[[:space:]]*$ ]]; then
        case "${BASH_REMATCH[1]}" in
          GREEN) return 0 ;;
          YELLOW) return 1 ;;
        esac
      fi
    done < "$ledger"
    # Unrecognized/missing PATH signal in canonical path — fall back for legacy artifacts.
    echo "WF_STEP: unrecognized PATH signal in $ledger; falling back to legacy findings detection" >&2
    cycle1_had_zero_findings "$art_dir"
    return $?
  fi
  # No canonical evidence ledger — fall back to legacy text detection for backward compat
  echo "WF_STEP: no cycle1/evidence_ledger.md at $ledger; falling back to legacy findings detection" >&2
  cycle1_had_zero_findings "$art_dir"
}

verify_cycle1_citations() {
  # Pre-flight citation check for C1 review artifacts before writing cycle1 receipt.
  # Select the most recent C1-valid artifact per tool directory to avoid stale-history
  # files while also ignoring newer C2 artifacts that are not valid for C1 gating.
  local art_dir="$1"
  local d
  local artifact
  local review_files=()
  local verifier="$ROOT/plans/verify_citations.sh"
  local newest=""
  local best_c1=""
  local verifier_output=""
  local saw_artifact=0
  local saw_provenance=0

  if [[ ! -x "$verifier" ]]; then
    echo "WF_STEP: citation validator missing or not executable at $verifier" >&2
    return 1
  fi

  for d in "$art_dir/codex" "$art_dir/opus" "$art_dir/kimi"; do
    [[ -d "$d" ]] || continue
    newest=""
    best_c1=""
    saw_artifact=0
    saw_provenance=0
    while IFS= read -r artifact; do
      [[ -f "$artifact" ]] || continue
      saw_artifact=1
      [[ -z "$newest" ]] && newest="$artifact"
      if ! verify_review_artifact_provenance "$artifact" "R3" "story_scope"; then
        continue
      fi
      saw_provenance=1
      # Newest-first scan: keep searching until first C1-valid artifact so a malformed/newer
      # file does not mask an older valid C1 report in the same tool directory.
      if "$verifier" --artifact "$artifact" --mode C1 --json >/dev/null 2>&1; then
        best_c1="$artifact"
        break
      fi
    done < <(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null | LC_ALL=C sort -r)

    if [[ -n "$best_c1" ]]; then
      review_files+=("$best_c1")
    elif [[ "$saw_artifact" -eq 1 && "$saw_provenance" -eq 0 ]]; then
      echo "WF_STEP: no provenance-valid C1 review artifact found in $d" >&2
      echo "  External cycle1 reviews must be generated by review_logged.sh (logger-v2 + sidecar)." >&2
      return 1
    elif [[ -n "$newest" ]]; then
      # Emit deterministic failure diagnostics for the newest candidate in this tool dir.
      verifier_output="$("$verifier" --artifact "$newest" --mode C1 --json 2>&1 || true)"
      [[ -n "$verifier_output" ]] && echo "$verifier_output" >&2
      echo "WF_STEP: citation pre-gate failed for $newest (no C1-valid artifact found in $d)" >&2
      return 1
    fi
  done

  if [[ "${#review_files[@]}" -eq 0 ]]; then
    echo "WF_STEP: no cycle1 review artifacts found for citation check in $art_dir" >&2
    return 1
  fi

  for artifact in "${review_files[@]}"; do
    if ! "$verifier" --artifact "$artifact" --mode C1 --json; then
      echo "WF_STEP: citation pre-gate failed for $artifact" >&2
      return 1
    fi
  done

  return 0
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

    # Evidence ledger readiness check (v3.0): verify R1 output exists before Cycle 1.
    # Prefer the dedicated helper for deterministic path checks + scaffold guidance.
    ledger_helper="$ROOT/plans/recon_evidence_ledger.sh"
    if [[ -x "$ledger_helper" ]]; then
      if ! ledger_check_output="$("$ledger_helper" "$STORY" --check 2>&1)"; then
        echo "$ledger_check_output" >&2
        echo "WF_STEP: cycle1 blocked — evidence ledger readiness check failed for $STORY" >&2
        echo "  Run: $ledger_helper $STORY --scaffold" >&2
        echo "  Then replace scaffold placeholders with real evidence before recording cycle1." >&2
        exit 6
      fi
    else
      # Legacy fallback: deterministic file checks if helper is unavailable.
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
        echo "WF_STEP: no evidence ledger found for $STORY" >&2
        echo "  Run Phase R1 (preflight/implement) before recording cycle1 receipt" >&2
        exit 6
      fi
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
    c2_basis_count=0
    for d in "$story_art/codex" "$story_art/opus" "$story_art/kimi"; do
      if [[ -d "$d" ]]; then
        while IFS= read -r f; do
          if ! verify_review_artifact_provenance "$f" "R3|R7" "any"; then
            continue
          fi
          review_count=$((review_count + 1))
          sidecar="${f%.md}.sidecar.json"
          sidecar_basis="$(jq -r '.review_basis // empty' "$sidecar" 2>/dev/null || true)"
          sidecar_phase="$(jq -r '.phase_equivalent // empty' "$sidecar" 2>/dev/null || true)"
          if [[ "$sidecar_phase" == "R7" ]] && is_fix_diff_basis "$sidecar_basis"; then
            c2_basis_count=$((c2_basis_count + 1))
          fi
        done < <(find "$d" -maxdepth 1 -type f \( -name '*_review.md' -o -name '*.enriched.md' -o -name '*.generic.md' \) ! -type l 2>/dev/null)
      fi
    done
    if [[ "$review_count" -lt "$min_reviews" ]]; then
      echo "WF_STEP: need at least $min_reviews provenance-valid review artifacts in $story_art/{codex,opus,kimi}/" >&2
      echo "  Artifacts must come from review_logged.sh (logger-v2 + sidecar)." >&2
      exit 3
    fi
    # Basis-label check: verify >=1 provenance-valid R7 artifact has FIX_DIFF review basis.
    if [[ "$c2_basis_count" -lt 1 ]]; then
      echo "WF_STEP: cycle2 gate requires >=1 provenance-valid R7 artifact with 'FIX_DIFF' review basis — none found" >&2
      echo "  in $story_art/{codex,opus,kimi}/" >&2
      echo "  C1 artifacts (R3 / STORY_SCOPE) do not satisfy this gate." >&2
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
