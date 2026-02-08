#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# Guard 1: legacy workflow files must not reappear in active harness paths.
forbidden_paths=(
  plans/ralph.sh
  plans/ralph_day.sh
  plans/workflow_acceptance.sh
  plans/workflow_acceptance_parallel.sh
  plans/test_parallel_smoke.sh
  plans/tests/test_ralph_needs_human.sh
  plans/tests/test_workflow_acceptance_fallback.sh
  prompts/Workflow_Auditor.md
  prompts/architect_advisor.md
  prompts/contact_arbiter.md
  prompts/workflow_121.md
  reviews/parallel_verify_compounding.md
  reviews/parallel_verify_evidence.md
  reviews/ROLE/PATCH.diff
  reviews/ROLE/PATCH_NOTES.md
  reviews/ROLE/REVIEW.md
)

present=()
for path in "${forbidden_paths[@]}"; do
  if [[ -e "$path" ]]; then
    present+=("$path")
  fi
done

if [[ "${#present[@]}" -gt 0 ]]; then
  fail "legacy files found in active paths: ${present[*]}"
fi

# Guard 2: postmortems with legacy references must be explicitly labeled archival.
legacy_pattern='ralph|workflow_acceptance|workflow acceptance|plans/ralph\.sh|plans/workflow_acceptance\.sh'
label='ARCHIVAL NOTE (Legacy Workflow):'

if command -v rg >/dev/null 2>&1; then
  matched_files="$(rg -l --no-messages "$legacy_pattern" reviews/postmortems --glob '*.md' || true)"
else
  matched_files="$(grep -RIlE "$legacy_pattern" reviews/postmortems 2>/dev/null || true)"
fi

unlabeled=()
if [[ -n "$matched_files" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    if ! grep -Fq "$label" "$file"; then
      unlabeled+=("$file")
    fi
  done <<< "$matched_files"
fi

if [[ "${#unlabeled[@]}" -gt 0 ]]; then
  fail "postmortems with legacy references require archival label: ${unlabeled[*]}"
fi

echo "PASS: legacy layout guard"
