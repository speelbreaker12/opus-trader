#!/usr/bin/env bash
set -euo pipefail

ROOT="${RECON_DOC_BUDGET_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
DEFAULT_MAX_LINES=650
progress_file="${RECON_DOC_BUDGET_PROGRESS_FILE:-$ROOT/plans/progress.txt}"

if [[ "${RECON_DOC_BUDGET_MAX_LINES+x}" == "x" ]]; then
  raw_budget="$RECON_DOC_BUDGET_MAX_LINES"
else
  raw_budget="$DEFAULT_MAX_LINES"
fi

fail() {
  local code="$1"
  local message="$2"
  echo "FAIL: ${code}: ${message}" >&2
  exit 1
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

validate_budget() {
  local value="$1"
  [[ -n "$value" ]] || fail "INVALID_THRESHOLD" "RECON_DOC_BUDGET_MAX_LINES must not be empty"
  [[ "$value" =~ ^[0-9]+$ ]] || fail "INVALID_THRESHOLD" "RECON_DOC_BUDGET_MAX_LINES must be a non-negative integer (got '$value')"
}

require_override_approval() {
  local file="$1"
  [[ -f "$file" ]] || fail "OVERRIDE_APPROVAL_MISSING" "missing override approval log file: $file"

  local approved_by reason expires
  approved_by="$(grep -E '^RECON_DOC_BUDGET_OVERRIDE_APPROVED_BY:[[:space:]]*[^[:space:]].*$' "$file" | tail -1 | sed 's/^RECON_DOC_BUDGET_OVERRIDE_APPROVED_BY:[[:space:]]*//' || true)"
  reason="$(grep -E '^RECON_DOC_BUDGET_OVERRIDE_REASON:[[:space:]]*[^[:space:]].*$' "$file" | tail -1 | sed 's/^RECON_DOC_BUDGET_OVERRIDE_REASON:[[:space:]]*//' || true)"
  expires="$(grep -E '^RECON_DOC_BUDGET_OVERRIDE_EXPIRES:[[:space:]]*[^[:space:]].*$' "$file" | tail -1 | sed 's/^RECON_DOC_BUDGET_OVERRIDE_EXPIRES:[[:space:]]*//' || true)"

  [[ -n "$approved_by" ]] || fail "OVERRIDE_APPROVAL_MISSING" "missing RECON_DOC_BUDGET_OVERRIDE_APPROVED_BY entry in $file"
  [[ -n "$reason" ]] || fail "OVERRIDE_APPROVAL_MISSING" "missing RECON_DOC_BUDGET_OVERRIDE_REASON entry in $file"
  [[ -n "$expires" ]] || fail "OVERRIDE_APPROVAL_MISSING" "missing RECON_DOC_BUDGET_OVERRIDE_EXPIRES entry in $file"
  [[ "$expires" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || fail "OVERRIDE_EXPIRY_INVALID" "RECON_DOC_BUDGET_OVERRIDE_EXPIRES must match YYYY-MM-DD (got '$expires')"

  echo "INFO: local override approved by '$approved_by' (expires $expires)"
  echo "INFO: override rationale: $reason"
}

validate_budget "$raw_budget"
budget="$raw_budget"

if (( budget > DEFAULT_MAX_LINES )); then
  if [[ -n "${CI:-}" ]]; then
    echo "WARN: CI override ignored for recon doc budget (requested $budget, enforced $DEFAULT_MAX_LINES)" >&2
    budget="$DEFAULT_MAX_LINES"
  else
    require_override_approval "$progress_file"
  fi
fi

declare -a docs=()
if [[ -n "${RECON_DOC_BUDGET_DOCS:-}" ]]; then
  IFS=',' read -r -a raw_docs <<< "${RECON_DOC_BUDGET_DOCS}"
  for entry in "${raw_docs[@]}"; do
    doc="$(trim "$entry")"
    [[ -n "$doc" ]] || continue
    docs+=("$doc")
  done
else
  docs=(
    "reviews/reconciliations/PROTOCOL.md"
    "reviews/reconciliations/REFERENCE.md"
    "reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md"
  )
fi

[[ "${#docs[@]}" -gt 0 ]] || fail "DOC_LIST_EMPTY" "no documents configured for recon doc budget gate"

total_lines=0
for doc in "${docs[@]}"; do
  abs="$doc"
  if [[ "$abs" != /* ]]; then
    abs="$ROOT/$doc"
  fi
  [[ -f "$abs" ]] || fail "MISSING_DOC" "$doc"

  lines="$(wc -l < "$abs" | tr -d '[:space:]')"
  [[ "$lines" =~ ^[0-9]+$ ]] || fail "LINE_COUNT_INVALID" "unable to parse line count for $doc"
  total_lines=$((total_lines + lines))
  echo "DOC_LINES $doc $lines"
done

echo "TOTAL_LINES $total_lines"
echo "BUDGET_MAX_LINES $budget"

if (( total_lines > budget )); then
  over_by=$((total_lines - budget))
  fail "BUDGET_EXCEEDED" "reconciliation docs exceed budget by $over_by lines ($total_lines > $budget)"
fi

echo "PASS: recon doc budget ($total_lines/$budget)"
