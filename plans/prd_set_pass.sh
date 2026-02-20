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
  - story review gate must pass for current HEAD (self/Kimi/Codex/code-review-expert/resolution evidence)
  - receipt chain must exist and be valid (all steps, no breaks, no tainted receipts)
  - if Phase-0 stories exist in PRD, non-Phase-0 stories cannot flip true until all Phase-0 stories are passes=true
  - enforcing_contract_ats must be non-empty (exit 6) — exempt: policy/certification categories
  - enforcement_point must be non-empty (exit 6) — exempt: policy/certification categories
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
  target_phase="$(jq -r --arg id "$ID" '.items[] | select(.id==$id) | (.phase // -1)' "$PRD_FILE")"
  phase0_count="$(jq -r '[.items[] | select((.phase // -1) == 0)] | length' "$PRD_FILE")"
  if [[ "$target_phase" =~ ^[0-9]+$ ]] && [[ "$phase0_count" =~ ^[0-9]+$ ]]; then
    if (( target_phase > 0 && phase0_count > 0 )); then
      incomplete_phase0="$(
        jq -r '.items[]
          | select((.phase // -1) == 0 and (.passes != true))
          | .id' "$PRD_FILE"
      )"
      if [[ -n "$incomplete_phase0" ]]; then
        echo "ERROR: cannot set passes=true for $ID while Phase-0 stories are incomplete: ${incomplete_phase0//$'\n'/, }" >&2
        exit 4
      fi
    fi
  fi

  # H-1: "PASS implies precision" — enforcing_contract_ats and enforcement_point must be non-empty
  # Exempt: policy/certification categories (no AT ownership required, matching prd_lint.sh)
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

  [[ -d "$ARTIFACTS_DIR" ]] || { echo "ERROR: missing artifacts dir: $ARTIFACTS_DIR" >&2; exit 4; }

  meta_file="$ARTIFACTS_DIR/verify.meta.json"
  [[ -f "$meta_file" ]] || { echo "ERROR: missing verify metadata artifact: $meta_file" >&2; exit 4; }
  verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
  if [[ "$verify_mode" != "full" ]]; then
    echo "ERROR: verify artifacts are not from full mode (mode=${verify_mode:-<missing>}) in $meta_file" >&2
    exit 4
  fi
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read current HEAD" >&2; exit 4; }
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

  if [[ -z "$CONTRACT_REVIEW_FILE" ]]; then
    CONTRACT_REVIEW_FILE="$ARTIFACTS_DIR/contract_review.json"
  fi
  [[ -f "$CONTRACT_REVIEW_FILE" ]] || { echo "ERROR: missing contract review artifact: $CONTRACT_REVIEW_FILE" >&2; exit 4; }

  if ! jq -e '.decision == "PASS"' "$CONTRACT_REVIEW_FILE" >/dev/null 2>&1; then
    echo "ERROR: contract review decision is not PASS in $CONTRACT_REVIEW_FILE" >&2
    exit 4
  fi

  # ── Receipt chain validation ──────────────────────────────────────
  REQUIRE_RECEIPT_CHAIN="${REQUIRE_RECEIPT_CHAIN:-1}"
  if [[ "$REQUIRE_RECEIPT_CHAIN" -eq 1 ]]; then
    WF_STEP="./plans/wf_step.sh"
    if [[ ! -x "$WF_STEP" ]]; then
      echo "ERROR: missing or non-executable wf_step.sh: $WF_STEP" >&2
      exit 4
    fi

    # Validate the full chain by running the 'pass' step (validates all prerequisites)
    if ! "$WF_STEP" "$ID" pass; then
      echo "ERROR: receipt chain validation failed for $ID" >&2
      echo "  Run: plans/wf_step.sh $ID --status  to see missing steps" >&2
      exit 4
    fi

    # Additional check: verify_full receipt HEAD must match current HEAD
    RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$ID}"
    vf_receipt="$RECEIPT_DIR/07_verify_full.json"
    if [[ -f "$vf_receipt" ]]; then
      vf_head="$(jq -r '.head_sha // empty' "$vf_receipt" 2>/dev/null || true)"
      if [[ "$vf_head" != "$HEAD_SHA" ]]; then
        echo "ERROR: verify_full receipt HEAD mismatch (receipt=$vf_head current=$HEAD_SHA)" >&2
        exit 4
      fi
      # Reject tainted receipts
      tainted_count=0
      for rf in "$RECEIPT_DIR"/*.json; do
        [[ -f "$rf" ]] || continue
        t="$(jq -r '.tainted // false' "$rf" 2>/dev/null || echo 'false')"
        if [[ "$t" == "true" ]]; then
          echo "ERROR: tainted receipt found: $rf (--force was used during workflow)" >&2
          tainted_count=$((tainted_count + 1))
        fi
      done
      if [[ "$tainted_count" -gt 0 ]]; then
        echo "ERROR: $tainted_count tainted receipt(s) — re-run workflow steps without --force" >&2
        exit 4
      fi
    else
      echo "ERROR: verify_full receipt not found at $vf_receipt" >&2
      exit 4
    fi
    # Verify HMAC signatures if key is available
    WF_HMAC_KEY="${WF_HMAC_KEY:-}"
    if [[ -n "$WF_HMAC_KEY" ]]; then
      if ! "$WF_STEP" "$ID" --verify-sigs; then
        echo "ERROR: HMAC signature verification failed for receipt chain" >&2
        exit 4
      fi
      echo "Receipt chain: OK (all steps present, chain valid, no taint, signatures verified)"
    else
      echo "Receipt chain: OK (all steps present, chain valid, no taint)"
    fi
  else
    echo "WARNING: receipt chain validation skipped (REQUIRE_RECEIPT_CHAIN=0)" >&2
  fi

  REVIEW_GATE="./plans/story_review_gate.sh"
  [[ -x "$REVIEW_GATE" ]] || { echo "ERROR: missing or non-executable review gate: $REVIEW_GATE" >&2; exit 4; }
  "$REVIEW_GATE" "$ID" --head "$HEAD_SHA"

  if [[ -x "./plans/fail_closed_coverage.sh" ]]; then
    if ! ./plans/fail_closed_coverage.sh; then
      echo "ERROR: fail-closed test coverage minimum not met" >&2
      exit 8
    fi
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
