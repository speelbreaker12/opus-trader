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
  trap 'rmdir "$lock_dir" 2>/dev/null || true' EXIT
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

  REVIEW_GATE="${STORY_REVIEW_GATE:-./plans/story_review_gate.sh}"
  [[ -x "$REVIEW_GATE" ]] || { echo "ERROR: missing or non-executable review gate: $REVIEW_GATE" >&2; exit 4; }
  "$REVIEW_GATE" "$ID" --head "$HEAD_SHA"
fi

tmp="$(mktemp)"
jq --arg id "$ID" --argjson status "$STATUS" '
  .items = (.items | map(if .id == $id then .passes = $status else . end))
' "$PRD_FILE" > "$tmp"
mv "$tmp" "$PRD_FILE"

echo "Updated task $ID: passes=$STATUS"
