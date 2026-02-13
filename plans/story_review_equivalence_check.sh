#!/usr/bin/env bash
set -euo pipefail

die_drift() {
  local detail="$1"
  echo "ERROR: STORY_REVIEW_EQUIVALENCE_DRIFT ($detail)" >&2
  exit 1
}

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

matrix_file="${1:-plans/story_review_equivalence_matrix.json}"

[[ -f "$matrix_file" ]] || die_drift "missing matrix file: $matrix_file"
jq -e 'type == "array"' "$matrix_file" >/dev/null 2>&1 || die_drift "matrix must be a JSON array: $matrix_file"

for field in id gate_requirement attested_field verifier_check; do
  jq -e --arg field "$field" '
    all(.[]; has($field) and (.[$field] | type == "string") and (.[$field] | length > 0))
  ' "$matrix_file" >/dev/null 2>&1 || die_drift "matrix rows must include non-empty field: $field"
done

expected_ids=(
  self_review_pass
  self_review_markers_done
  kimi_review_for_head
  codex_two_reviews
  code_review_expert_complete
  resolution_blocking_cleared
  resolution_reference_consistency
  evidence_head_consistency
)

matrix_ids="$(jq -r '.[].id' "$matrix_file" | LC_ALL=C sort)"
expected_ids_sorted="$(printf '%s\n' "${expected_ids[@]}" | LC_ALL=C sort)"

duplicate_ids="$(jq -r '.[].id' "$matrix_file" | LC_ALL=C sort | uniq -d || true)"
[[ -z "$duplicate_ids" ]] || die_drift "duplicate ids: $duplicate_ids"

if [[ "$matrix_ids" != "$expected_ids_sorted" ]]; then
  echo "expected ids:" >&2
  printf '%s\n' "$expected_ids_sorted" >&2
  echo "actual ids:" >&2
  printf '%s\n' "$matrix_ids" >&2
  die_drift "matrix ids diverged from required story_review_gate invariants"
fi

echo "PASS: story review equivalence matrix"
