#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./plans/prd_set_pass.sh <task_id> <true|false> [--artifacts-dir <dir>] [--contract-review <file>]

If --artifacts-dir is omitted, the latest artifacts/verify/<run_id>/ directory is used.

Rules for passes=true:
  - verify.meta.json must exist and report mode=full
  - verify.meta.json head_sha must equal current HEAD
  - FAILED_GATE must be absent in artifacts dir
  - all *.rc files in artifacts dir must be 0
  - contract review file must exist and contain decision=PASS
  - at least one review artifact must exist for current HEAD (codex/ or opus/)
  - wf_step.sh receipt chain must have all 8 receipts
  - enforcing_contract_ats must be non-empty (exit 6) — exempt: policy/certification categories
  - enforcement_point must be non-empty (exit 6) — exempt: policy/certification categories
  - loss_mode.worst_case, .fail_closed_cap, .drift_metric must all be non-empty (exit 9) — exempt: policy/certification
  - proof_graph.json must exist and validate (exit 10) — exempt: IDs in plans/proof_graph_exempt.txt
  - proof_graph TRADING HALT condition triggers exit 20 (V2 graphs with safety_critical + HIGH/CRITICAL + FAIL_OPEN_RISK/WRONG_IMPL_UNBLOCKED)
USAGE
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ID="${1:-}"
STATUS="${2:-}"
shift $(( $# >= 2 ? 2 : $# ))

PRD_FILE="${PRD_FILE:-plans/prd.json}"
ARTIFACTS_DIR="${VERIFY_ARTIFACTS_DIR:-}"
CONTRACT_REVIEW_FILE=""

if [[ -z "$ARTIFACTS_DIR" ]]; then
  ARTIFACTS_DIR="$(ls -dt "$ROOT"/artifacts/verify/*/ 2>/dev/null | head -n 1 || true)"
fi
ARTIFACTS_DIR="${ARTIFACTS_DIR%/}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifacts-dir)
      ARTIFACTS_DIR="${2:-}"
      shift 2
      ;;
    --contract-review)
      CONTRACT_REVIEW_FILE="${2:-}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

[[ -n "$ID" && -n "$STATUS" ]] || { usage >&2; exit 2; }
[[ "$STATUS" == "true" || "$STATUS" == "false" ]] || { echo "ERROR: status must be true or false" >&2; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
[[ -f "$PRD_FILE" ]] || { echo "ERROR: missing PRD file: $PRD_FILE" >&2; exit 1; }

lock_file="${PRD_FILE}.lock"
lock_dir="${lock_file}.d"
tmp=""
lock_dir_acquired=0

cleanup() {
  if [[ -n "$tmp" && -f "$tmp" ]]; then
    rm -f "$tmp" 2>/dev/null || true
  fi
  if [[ "$lock_dir_acquired" == "1" ]]; then
    rmdir "$lock_dir" 2>/dev/null || true
  fi
}

trap cleanup EXIT

if command -v flock >/dev/null 2>&1; then
  exec 200>"$lock_file"
  if ! flock -n 200; then
    echo "ERROR: PRD is locked by another process" >&2
    exit 7
  fi
else
  if ! mkdir "$lock_dir" 2>/dev/null; then
    echo "ERROR: PRD is locked by another process" >&2
    exit 7
  fi
  lock_dir_acquired=1
fi

if ! jq -e . "$PRD_FILE" >/dev/null 2>&1; then
  echo "ERROR: PRD is invalid JSON: $PRD_FILE" >&2
  exit 1
fi

exists="$(jq --arg id "$ID" 'any(.items[]; .id==$id)' "$PRD_FILE")"
if [[ "$exists" != "true" ]]; then
  echo "ERROR: task id not found in PRD: $ID" >&2
  exit 3
fi

if [[ "$STATUS" == "true" ]]; then
  # ── PRD field validation ──────────────────────────────────────────
  story_category="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.category // "")' "$PRD_FILE")"
  if [[ "$story_category" != "policy" && "$story_category" != "certification" ]]; then
    eca_count="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.enforcing_contract_ats // []) | if type == "array" then length else 0 end' "$PRD_FILE")"
    if [[ "$eca_count" -eq 0 ]]; then
      echo "ERROR: cannot set passes=true for $ID: enforcing_contract_ats is empty (PASS requires AT ownership)" >&2
      exit 6
    fi
    enf_point="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.enforcement_point // "")' "$PRD_FILE")"
    if [[ -z "$enf_point" ]]; then
      echo "ERROR: cannot set passes=true for $ID: enforcement_point is missing/empty (PASS requires a named enforcement point)" >&2
      exit 6
    fi
  fi

  # ── loss_mode gate ──
  if [[ "$story_category" != "policy" && "$story_category" != "certification" ]]; then
    loss_ok=$(jq -r --arg id "$ID" '
      .items[] | select(.id == $id) |
      (.loss_mode // {}) | if type == "object" then . else {} end |
      ((.worst_case // "") | length > 0) and
      ((.fail_closed_cap // "") | length > 0) and
      ((.drift_metric // "") | length > 0)
    ' "$PRD_FILE")
    if [[ "$loss_ok" != "true" ]]; then
      echo "ERROR: loss_mode incomplete for $ID (worst_case, fail_closed_cap, drift_metric required)" >&2
      exit 9
    fi
  fi

  # ── Verify artifacts ──────────────────────────────────────────────
  [[ -d "$ARTIFACTS_DIR" ]] || { echo "ERROR: missing artifacts dir: $ARTIFACTS_DIR" >&2; exit 4; }

  meta_file="$ARTIFACTS_DIR/verify.meta.json"
  [[ -f "$meta_file" ]] || { echo "ERROR: missing verify metadata artifact: $meta_file" >&2; exit 4; }
  verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
  if [[ "$verify_mode" != "full" ]]; then
    echo "ERROR: verify artifacts are not from full mode (mode=${verify_mode:-<missing>}) in $meta_file" >&2
    exit 4
  fi
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read current HEAD" >&2; exit 4; }
  [[ -n "$HEAD_SHA" ]] || { echo "ERROR: HEAD_SHA is empty" >&2; exit 4; }
  verify_head_sha="$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null || true)"
  if [[ -z "$verify_head_sha" ]]; then
    echo "ERROR: verify metadata missing head_sha in $meta_file" >&2
    exit 4
  fi
  if [[ "$verify_head_sha" != "$HEAD_SHA" ]]; then
    echo "ERROR: verify metadata HEAD mismatch (verify=$verify_head_sha current=$HEAD_SHA)" >&2
    exit 4
  fi

  if [[ -f "$ARTIFACTS_DIR/FAILED_GATE" ]]; then
    echo "ERROR: FAILED_GATE present in $ARTIFACTS_DIR" >&2
    exit 4
  fi

  rc_count=0
  bad_rc=0
  while IFS= read -r rc_file; do
    rc_count=$((rc_count + 1))
    rc_val="$(tr -d '[:space:]' < "$rc_file" 2>/dev/null || true)"
    if [[ "$rc_val" != "0" ]]; then
      echo "ERROR: non-zero gate rc in $rc_file: ${rc_val:-<empty>}" >&2
      bad_rc=1
    fi
  done < <(find "$ARTIFACTS_DIR" -maxdepth 1 -type f -name '*.rc' | sort)

  if [[ "$rc_count" -eq 0 ]]; then
    echo "ERROR: no *.rc gate artifacts found in $ARTIFACTS_DIR" >&2
    exit 4
  fi
  if [[ "$bad_rc" -ne 0 ]]; then
    exit 4
  fi

  # Required artifact-backed gate proofs for pass flips.
  required_gate_artifacts=(
    "preflight.rc"
    "fail_closed_coverage.rc"
  )
  for required_gate_rc in "${required_gate_artifacts[@]}"; do
    required_gate_path="$ARTIFACTS_DIR/$required_gate_rc"
    if [[ ! -f "$required_gate_path" ]]; then
      echo "ERROR: missing required gate artifact: $required_gate_path" >&2
      exit 4
    fi
    required_rc_val="$(tr -d '[:space:]' < "$required_gate_path" 2>/dev/null || true)"
    if [[ "$required_rc_val" != "0" ]]; then
      echo "ERROR: required gate artifact is non-zero: $required_gate_path (${required_rc_val:-<empty>})" >&2
      exit 4
    fi
  done

  # ── Contract review ───────────────────────────────────────────────
  if [[ -z "$CONTRACT_REVIEW_FILE" ]]; then
    CONTRACT_REVIEW_FILE="$ARTIFACTS_DIR/contract_review.json"
  fi
  [[ -f "$CONTRACT_REVIEW_FILE" ]] || { echo "ERROR: missing contract review artifact: $CONTRACT_REVIEW_FILE" >&2; exit 4; }

  if ! jq -e '.decision == "PASS"' "$CONTRACT_REVIEW_FILE" >/dev/null 2>&1; then
    echo "ERROR: contract review decision is not PASS in $CONTRACT_REVIEW_FILE" >&2
    exit 4
  fi

  # ── Inline review check ──────────────────────────────────────────
  # At least one review artifact must exist for current HEAD
  review_found=0
  art_root="${STORY_ARTIFACTS_ROOT:-$ROOT/artifacts/story}"
  for dir in "$art_root/$ID/codex" "$art_root/$ID/opus"; do
    [[ -d "$dir" ]] || continue
    if grep -rlF "$HEAD_SHA" "$dir"/ 2>/dev/null | head -1 | grep -q .; then
      review_found=1; break
    fi
  done
  if [[ "$review_found" -eq 1 ]]; then
    echo "OK: review gate passed for $ID @ $HEAD_SHA"
  else
    echo "ERROR: no review artifact for HEAD=$HEAD_SHA in $art_root/$ID/{codex,opus}" >&2
    exit 4
  fi

  # ── External manifest gates (R3 + R7d) ──────────────────────────
  # If external_manifest_gate.sh exists, run both gates.
  # Derive slice_id from story ID prefix (e.g., S1-004 → S1).
  ext_gate="$ROOT/plans/external_manifest_gate.sh"
if [[ -x "$ext_gate" ]]; then
    slice_prefix="${ID%%-*}"  # S1-004 → S1
    for gate_type in r3 r7; do
      gate_type_uc="$(printf '%s' "$gate_type" | tr '[:lower:]' '[:upper:]')"
      if "$ext_gate" "$gate_type" "$ID" "$slice_prefix" 2>&1; then
        echo "OK: ${gate_type_uc} external manifest gate passed for $ID"
      else
        gate_rc=$?
        # Gate failure is non-fatal if manifest doesn't exist yet
        # (not all stories have reconciliation manifests)
        if [[ "$gate_rc" -eq 1 ]]; then
          echo "WARN: ${gate_type_uc} external manifest gate failed for $ID (exit $gate_rc)" >&2
          echo "  This is expected if reconciliation has not been run for this story." >&2
        else
          echo "ERROR: ${gate_type_uc} external manifest gate failed for $ID (exit $gate_rc)" >&2
          exit 4
        fi
      fi
    done
  fi

  # ── Fail-closed coverage ──────────────────────────────────────────
  if [[ -x "./plans/fail_closed_coverage.sh" ]]; then
    if ! ./plans/fail_closed_coverage.sh; then
      echo "ERROR: fail-closed test coverage minimum not met" >&2
      exit 8
    fi
  fi

  # ── Proof graph validation ──────────────────────────────────────────
  proof_graph_file="$art_root/$ID/proof_graph.json"
  exempt_list="$ROOT/plans/proof_graph_exempt.txt"
  if [[ -f "$proof_graph_file" ]]; then
    command -v python3 >/dev/null 2>&1 || {
      echo "ERROR: python3 required for proof graph validation" >&2
      exit 10
    }
    pg_rc=0
    python3 "$ROOT/python/proof_graph/validate.py" "$proof_graph_file" \
         --contract-path "$ROOT/specs/CONTRACT.md" \
         --prd-path "$PRD_FILE" \
         --strict || pg_rc=$?

    if [[ "$pg_rc" -eq 20 ]]; then
      echo "CRITICAL: proof graph triggered TRADING HALT for $ID" >&2
      exit 20
    elif [[ "$pg_rc" -ne 0 ]]; then
      echo "ERROR: proof graph validation failed for $ID (exit $pg_rc)" >&2
      exit 10
    fi
  elif [[ -f "$exempt_list" ]] && grep -qxF "$ID" "$exempt_list"; then
    echo "INFO: $ID is exempt from proof graph requirement (legacy)" >&2
  else
    echo "ERROR: proof_graph.json missing for $ID (not in exempt list)" >&2
    echo "  Generate skeleton: python3 python/proof_graph/scaffold.py $ID" >&2
    exit 10
  fi


  # ── Receipt chain (all 8 receipts must exist) ─────────────────────
  WF_STEP="${WF_STEP:-./plans/wf_step.sh}"
  if [[ -x "$WF_STEP" ]]; then
    if ! "$WF_STEP" "$ID" pass; then
      echo "ERROR: receipt chain validation failed for $ID" >&2
      echo "  Run: plans/wf_step.sh $ID --status  to see missing steps" >&2
      exit 4
    fi

    WF_RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$ID}"
    if [[ ! -d "$WF_RECEIPT_DIR" ]]; then
      echo "ERROR: workflow receipt directory missing: $WF_RECEIPT_DIR" >&2
      exit 4
    fi

    required_wf_steps=(preflight implement self_review cycle1 fix cycle2 resolution verify_full pass)
    for idx in $(seq 0 7); do
      step_name="${required_wf_steps[$idx]}"
      receipt_file="${WF_RECEIPT_DIR}/$(printf '%02d_%s.json' "$idx" "$step_name")"
      if [[ ! -f "$receipt_file" ]]; then
        echo "ERROR: missing required workflow receipt: $receipt_file" >&2
        exit 4
      fi

      if ! jq -e '.head_sha and .timestamp_utc' "$receipt_file" >/dev/null 2>&1; then
        echo "ERROR: workflow receipt missing required metadata: $receipt_file" >&2
        exit 4
      fi
    done
  fi
fi

tmp="$(mktemp)"
jq --arg id "$ID" --argjson status "$STATUS" '
  .items = (.items | map(if .id == $id then .passes = $status else . end))
' "$PRD_FILE" > "$tmp"
if [[ "$STATUS" == "true" ]]; then
  final_head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to re-read current HEAD before pass flip" >&2; rm -f "$tmp"; exit 4; }
  if [[ "$final_head_sha" != "$HEAD_SHA" ]]; then
    echo "ERROR: HEAD changed during pass flip validation (initial=$HEAD_SHA current=$final_head_sha)" >&2
    rm -f "$tmp"
    exit 4
  fi
fi
mv "$tmp" "$PRD_FILE"

echo "Updated task $ID: passes=$STATUS"
