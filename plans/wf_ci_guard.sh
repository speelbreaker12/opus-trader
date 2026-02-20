#!/usr/bin/env bash
set -euo pipefail

# CI guard: detects passes=true flips in prd.json and validates receipt chains.
#
# Catches direct prd.json edits that bypass prd_set_pass.sh.
# Should be added to CI pipeline as a blocking check.
#
# Usage: plans/wf_ci_guard.sh [--require-sigs]
#
# Environment:
#   WF_BASE_REF       Base ref to diff against (default: origin/main)
#   WF_HMAC_KEY       If set with --require-sigs, validates HMAC signatures
#   REQUIRE_RECEIPT_CHAIN  Set to 0 to skip (default: 1)
#
# Exit codes:
#   0 — OK (no flips detected, or all flips have valid receipts)
#   1 — receipt validation failed
#   2 — usage/setup error

exec < /dev/null

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "WF_CI_GUARD: not in a git repo" >&2; exit 2; }
cd "$ROOT"

REQUIRE_SIGS=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --require-sigs) REQUIRE_SIGS=1 ;;
    -h|--help)
      echo "Usage: plans/wf_ci_guard.sh [--require-sigs]"
      exit 0
      ;;
    *) echo "WF_CI_GUARD ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
  shift
done

REQUIRE_RECEIPT_CHAIN="${REQUIRE_RECEIPT_CHAIN:-1}"
if [[ "$REQUIRE_RECEIPT_CHAIN" -eq 0 ]]; then
  echo "WF_CI_GUARD: skipped (REQUIRE_RECEIPT_CHAIN=0)"
  exit 0
fi

command -v jq >/dev/null 2>&1 || { echo "WF_CI_GUARD ERROR: jq required" >&2; exit 2; }

PRD_FILE="plans/prd.json"
[[ -f "$PRD_FILE" ]] || { echo "WF_CI_GUARD: no prd.json found, skipping"; exit 0; }

# Determine base ref
BASE_REF="${WF_BASE_REF:-origin/main}"
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  # Fallback: try main, then HEAD~1
  if git rev-parse --verify "main" >/dev/null 2>&1; then
    BASE_REF="main"
  else
    BASE_REF="HEAD~1"
  fi
fi

# Check if prd.json changed
CHANGED="$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || git diff --name-only "$BASE_REF"..HEAD 2>/dev/null || true)"
if ! echo "$CHANGED" | grep -q "^plans/prd\.json$"; then
  echo "WF_CI_GUARD: prd.json not changed"
  exit 0
fi

# Extract story IDs that flipped to passes=true
# Use jq to compare base vs HEAD versions for reliability (not regex on diff)
base_prd="$(mktemp)"
head_prd="$(mktemp)"
cleanup() { rm -f "$base_prd" "$head_prd"; }
trap cleanup EXIT

git show "$BASE_REF:$PRD_FILE" > "$base_prd" 2>/dev/null || echo '{"items":[]}' > "$base_prd"
cp "$PRD_FILE" "$head_prd"

# Find IDs where passes changed from false/null to true
FLIPPED="$(jq -r --slurpfile base "$base_prd" '
  .items[] |
  select(.passes == true) |
  .id as $id |
  if ($base[0].items // [] | map(select(.id == $id)) | length) == 0 then
    $id
  elif ($base[0].items // [] | map(select(.id == $id and .passes != true)) | length) > 0 then
    $id
  else
    empty
  end
' "$head_prd" 2>/dev/null || true)"

if [[ -z "$FLIPPED" ]]; then
  echo "WF_CI_GUARD: no passes=true flips detected"
  exit 0
fi

echo "WF_CI_GUARD: passes=true flips detected:"
echo "$FLIPPED" | while IFS= read -r id; do
  echo "  - $id"
done

# Validate receipt chain for each flipped story
HEAD_SHA="$(git rev-parse HEAD)"
WF_STEP="./plans/wf_step.sh"
if [[ ! -x "$WF_STEP" ]]; then
  echo "WF_CI_GUARD ERROR: wf_step.sh not found or not executable" >&2
  exit 1
fi

FAILED=0
while IFS= read -r story_id; do
  [[ -n "$story_id" ]] || continue
  echo ""
  echo "WF_CI_GUARD: validating receipt chain for $story_id..."

  # Check chain exists and is valid
  if ! "$WF_STEP" "$story_id" pass 2>&1; then
    echo "WF_CI_GUARD FAIL: receipt chain invalid for $story_id" >&2
    FAILED=1
    continue
  fi

  # Verify HEAD matches
  RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$story_id}"
  vf_receipt="$RECEIPT_DIR/07_verify_full.json"
  if [[ -f "$vf_receipt" ]]; then
    vf_head="$(jq -r '.head_sha // empty' "$vf_receipt" 2>/dev/null || true)"
    if [[ "$vf_head" != "$HEAD_SHA" ]]; then
      echo "WF_CI_GUARD FAIL: verify_full receipt HEAD mismatch for $story_id (receipt=$vf_head current=$HEAD_SHA)" >&2
      FAILED=1
      continue
    fi
  else
    echo "WF_CI_GUARD FAIL: no verify_full receipt for $story_id" >&2
    FAILED=1
    continue
  fi

  # Check for tainted receipts
  for rf in "$RECEIPT_DIR"/*.json; do
    [[ -f "$rf" ]] || continue
    t="$(jq -r '.tainted // false' "$rf" 2>/dev/null || echo 'false')"
    if [[ "$t" == "true" ]]; then
      echo "WF_CI_GUARD FAIL: tainted receipt for $story_id: $rf" >&2
      FAILED=1
    fi
  done

  # Verify HMAC signatures if requested
  if [[ "$REQUIRE_SIGS" -eq 1 ]]; then
    WF_HMAC_KEY="${WF_HMAC_KEY:-}"
    if [[ -z "$WF_HMAC_KEY" ]]; then
      echo "WF_CI_GUARD FAIL: --require-sigs but WF_HMAC_KEY not set" >&2
      FAILED=1
      continue
    fi
    if ! "$WF_STEP" "$story_id" --verify-sigs 2>&1; then
      echo "WF_CI_GUARD FAIL: HMAC signature verification failed for $story_id" >&2
      FAILED=1
      continue
    fi
  fi

  echo "WF_CI_GUARD: $story_id — OK"
done <<< "$FLIPPED"

echo ""
if [[ "$FAILED" -ne 0 ]]; then
  echo "WF_CI_GUARD: FAILED — one or more receipt chains invalid" >&2
  exit 1
fi

echo "WF_CI_GUARD: OK — all flipped stories have valid receipt chains"
