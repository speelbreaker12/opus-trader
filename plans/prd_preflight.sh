#!/usr/bin/env bash
set -euo pipefail

# Pre-flight validation for PRD files
# Fast schema checks before LLM audit to catch obvious errors

PRD_FILE="${1:-${PRD_FILE:-plans/prd.json}}"

if [[ ! -f "$PRD_FILE" ]]; then
  echo "[preflight] ERROR: PRD file not found: $PRD_FILE" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "[preflight] ERROR: jq required" >&2
  exit 2
fi

# Check 1: Valid JSON
if ! jq -e . "$PRD_FILE" >/dev/null 2>&1; then
  echo "[preflight] ERROR: Invalid JSON in $PRD_FILE" >&2
  exit 2
fi

# Check 2: Required top-level keys
missing=$(jq -r '
  ["project","source","rules","items"] - keys | .[]
' "$PRD_FILE")
if [[ -n "$missing" ]]; then
  echo "[preflight] ERROR: Missing top-level keys: $missing" >&2
  exit 2
fi

# Check 3: Each item has required fields
errors=$(jq -r '
  .items[] |
  . as $item |
  ["id","priority","phase","slice","category","description","contract_refs","plan_refs","scope","acceptance","steps","verify","evidence","dependencies","est_size","risk","needs_human_decision","passes"] as $required |
  ($required - ($item | keys)) as $missing |
  if ($missing | length) > 0 then
    "\($item.id // "unknown"): missing \($missing | join(", "))"
  else empty end
' "$PRD_FILE" 2>/dev/null || echo "parse_error")
if [[ -n "$errors" ]]; then
  echo "[preflight] ERROR: Schema violations:" >&2
  echo "$errors" >&2
  exit 2
fi

# Check 4: verify[] includes "./plans/verify.sh"
missing_verify=$(jq -r '
  .items[] |
  select(.verify | map(select(. == "./plans/verify.sh")) | length == 0) |
  .id
' "$PRD_FILE" 2>/dev/null || true)
if [[ -n "$missing_verify" ]]; then
  echo "[preflight] ERROR: Items missing ./plans/verify.sh in verify[]: $missing_verify" >&2
  exit 2
fi

# Check 5: Minimum acceptance (3) and steps (5)
short_items=$(jq -r '
  .items[] |
  select((.acceptance | length) < 3 or (.steps | length) < 5) |
  "\(.id): acceptance=\(.acceptance | length), steps=\(.steps | length)"
' "$PRD_FILE" 2>/dev/null || true)
if [[ -n "$short_items" ]]; then
  echo "[preflight] ERROR: Items with insufficient acceptance/steps:" >&2
  echo "$short_items" >&2
  exit 2
fi

# Check 6: All items have valid slice (integer)
invalid_slice=$(jq -r '
  .items[] |
  select(.slice | type != "number" or . != floor) |
  "\(.id): slice=\(.slice)"
' "$PRD_FILE" 2>/dev/null || true)
if [[ -n "$invalid_slice" ]]; then
  echo "[preflight] ERROR: Items with invalid slice values:" >&2
  echo "$invalid_slice" >&2
  exit 2
fi

# Check 7: No duplicate item IDs
dupes=$(jq -r '
  [.items[].id] | group_by(.) | map(select(length > 1) | .[0]) | .[]
' "$PRD_FILE" 2>/dev/null || true)
if [[ -n "$dupes" ]]; then
  echo "[preflight] ERROR: Duplicate item IDs: $dupes" >&2
  exit 2
fi

echo "[preflight] PASS: $PRD_FILE" >&2
exit 0
