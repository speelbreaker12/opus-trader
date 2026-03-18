#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TEMPLATE="$ROOT/reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$TEMPLATE" ]] || fail "missing handoff template: $TEMPLATE"

require_marker() {
  local file="$1"
  local marker="$2"
  grep -Fq "$marker" "$file" || fail "missing marker in $file: $marker"
}

# Template must advertise canonical sources.
for marker in \
  "reviews/reconciliations/PROTOCOL.md" \
  "reviews/reconciliations/REFERENCE.md" \
  "specs/WORKFLOW_CONTRACT.md" \
  "plans/wf_step.sh" \
  "plans/verify.sh" \
  "plans/prd_set_pass.sh"; do
  require_marker "$TEMPLATE" "$marker"
done

if ! grep -Eq '^#{2,3} Source( |-)Of-Truth|^#{2,3} Source Of Truth' "$TEMPLATE"; then
  fail "template missing Source-of-Truth section heading"
fi

# Existing slice handoffs must contain the same canonical source block.
mapfile_fallback() {
  # bash 3.2 compatible list collection
  find "$ROOT/reviews/reconciliations" -maxdepth 2 -type f -path '*/S*/HANDOFF.md' | LC_ALL=C sort
}

handoff_files="$(mapfile_fallback)"
[[ -n "$handoff_files" ]] || fail "no S*/HANDOFF.md files found"

while IFS= read -r handoff; do
  [[ -n "$handoff" ]] || continue
  require_marker "$handoff" "reviews/reconciliations/PROTOCOL.md"
  require_marker "$handoff" "reviews/reconciliations/REFERENCE.md"
  require_marker "$handoff" "specs/WORKFLOW_CONTRACT.md"
  require_marker "$handoff" "plans/wf_step.sh"
  require_marker "$handoff" "plans/verify.sh"
  require_marker "$handoff" "plans/prd_set_pass.sh"
  if ! grep -Eq '^#{2,3} Source-of-Truth Documents \(Current\)|^#{2,3} Source Of Truth' "$handoff"; then
    fail "$handoff missing Source-of-Truth section heading"
  fi
done <<< "$handoff_files"

echo "PASS: reconciliation handoff source-of-truth coverage"
