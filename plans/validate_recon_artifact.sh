#!/usr/bin/env bash
set -euo pipefail

# Validates a reconciliation JSON artifact against its schema rules.
#
# Usage: plans/validate_recon_artifact.sh <schema_name> <artifact.json>
#
# Schema names: gap_list, verify_result, review_receipt, phase_mapping,
#               premortem_ready, lead_eval_sidecar, self_review_sidecar,
#               review_artifact_sidecar, r3_external_manifest, r7_external_manifest
#
# Exit codes:
#   0 = valid
#   1 = invalid (field-level errors on stderr)
#   2 = usage error
#   3 = artifact file not found
#   4 = artifact is not valid JSON
#
# Validates:
#   - File exists and is valid JSON
#   - Required guardrail fields present: schema_version, head_commit, created_at
#   - schema_version matches expected pattern (<schema_name>.v<N>)
#   - For sidecar schemas: markdown_sha256 and markdown_path present
#   - For sidecar schemas: markdown_sha256 matches actual file hash (if file exists)
#   - Schema-specific required fields present and non-null

usage() {
  cat <<'USAGE'
Usage: plans/validate_recon_artifact.sh <schema_name> <artifact.json>

Schema names:
  gap_list, verify_result, review_receipt, phase_mapping,
  premortem_ready, lead_eval_sidecar, self_review_sidecar,
  review_artifact_sidecar, r3_external_manifest, r7_external_manifest

Exit codes:
  0 = valid
  1 = invalid (field-level errors on stderr)
  2 = usage error
  3 = artifact file not found
  4 = artifact is not valid JSON
USAGE
}

# --- args ---
schema_name="${1:-}"
artifact_path="${2:-}"

if [[ -z "$schema_name" || -z "$artifact_path" ]]; then
  usage >&2
  exit 2
fi

# Validate schema_name is known
known_schemas="gap_list verify_result review_receipt phase_mapping premortem_ready lead_eval_sidecar self_review_sidecar review_artifact_sidecar r3_external_manifest r7_external_manifest"
schema_valid=false
for s in $known_schemas; do
  if [[ "$s" == "$schema_name" ]]; then
    schema_valid=true
    break
  fi
done
if [[ "$schema_valid" == "false" ]]; then
  echo "ERROR: unknown schema name: $schema_name" >&2
  echo "Known schemas: $known_schemas" >&2
  exit 2
fi

# --- check jq available ---
if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found" >&2
  exit 2
fi

# --- check artifact file exists ---
if [[ ! -f "$artifact_path" ]]; then
  echo "ERROR: artifact file not found: $artifact_path" >&2
  exit 3
fi

# --- check valid JSON ---
if ! jq empty "$artifact_path" 2>/dev/null; then
  echo "ERROR: artifact is not valid JSON: $artifact_path" >&2
  exit 4
fi

errors=()

# ==== Guardrail checks (all schemas) ====

# schema_version: must exist
if ! jq -e '.schema_version' "$artifact_path" >/dev/null 2>&1; then
  errors+=("missing required field: schema_version")
else
  # schema_version must match pattern: <schema_name>.v<N>
  sv="$(jq -re '.schema_version' "$artifact_path" 2>/dev/null || true)"
  expected_pattern="^${schema_name}\.v[0-9]+$"
  if [[ ! "$sv" =~ $expected_pattern ]]; then
    errors+=("schema_version '$sv' does not match expected pattern '${schema_name}.v<N>'")
  fi
fi

# head_commit: must exist, length >= 7
if ! jq -e '.head_commit' "$artifact_path" >/dev/null 2>&1; then
  errors+=("missing required field: head_commit")
else
  hc_len="$(jq -re '.head_commit | length' "$artifact_path" 2>/dev/null || echo 0)"
  if [[ "$hc_len" -lt 7 ]]; then
    errors+=("head_commit too short (length=$hc_len, need >= 7)")
  fi
fi

# created_at: must exist
if ! jq -e '.created_at' "$artifact_path" >/dev/null 2>&1; then
  errors+=("missing required field: created_at")
fi

# ==== Sidecar checks (schema names ending in _sidecar) ====
if [[ "$schema_name" == *_sidecar ]]; then
  # markdown_sha256 must exist
  if ! jq -e '.markdown_sha256' "$artifact_path" >/dev/null 2>&1; then
    errors+=("sidecar missing required field: markdown_sha256")
  fi

  # markdown_path must exist
  if ! jq -e '.markdown_path' "$artifact_path" >/dev/null 2>&1; then
    errors+=("sidecar missing required field: markdown_path")
  else
    md_path="$(jq -re '.markdown_path' "$artifact_path" 2>/dev/null || true)"
    md_sha="$(jq -re '.markdown_sha256' "$artifact_path" 2>/dev/null || true)"

    # If markdown file exists, verify sha256 matches
    if [[ -n "$md_path" && -f "$md_path" ]]; then
      # macOS uses shasum, Linux uses sha256sum
      if command -v shasum >/dev/null 2>&1; then
        actual_sha="$(shasum -a 256 "$md_path" | cut -d' ' -f1)"
      elif command -v sha256sum >/dev/null 2>&1; then
        actual_sha="$(sha256sum "$md_path" | cut -d' ' -f1)"
      else
        actual_sha=""
        echo "WARN: neither shasum nor sha256sum available, skipping hash check" >&2
      fi

      if [[ -n "$actual_sha" && -n "$md_sha" && "$actual_sha" != "$md_sha" ]]; then
        errors+=("markdown_sha256 mismatch: expected=$md_sha actual=$actual_sha for $md_path")
      fi
    fi
  fi
fi

# ==== Schema-specific required field checks ====
required_fields=()

case "$schema_name" in
  gap_list)
    required_fields=("gaps" "systemic_gaps" "priority_summary")
    ;;
  verify_result)
    required_fields=("story_id" "verdict" "p0_closed" "p1_closed_or_deferred" "tests_pass")
    ;;
  review_receipt)
    required_fields=("story_id" "review_basis" "review_basis_cycle" "tool" "prompt_style" "citations" "findings" "finding_counts")
    ;;
  phase_mapping)
    required_fields=("story_id" "mappings" "unmapped_count" "unmapped_p0_p1_count")
    ;;
  premortem_ready)
    required_fields=("story_id" "ready" "premortem_exists" "stoplight")
    ;;
  lead_eval_sidecar)
    required_fields=("story_ids" "citation_checks_performed" "overall_ratings")
    ;;
  self_review_sidecar)
    required_fields=("story_id" "skills_run" "total_blockers" "premortem_crosscheck")
    ;;
  review_artifact_sidecar)
    required_fields=("story_id" "review_type" "review_basis" "finding_counts" "basis_line_present")
    ;;
  r3_external_manifest)
    required_fields=("story_id" "cycle" "review_basis" "tools" "validated_preexisting_enforcement_citation" "validated_preexisting_test_citation" "validation_status")
    ;;
  r7_external_manifest)
    required_fields=("story_id" "cycle" "review_basis" "base_commit" "tools" "validation_status")
    ;;
esac

for field in "${required_fields[@]}"; do
  if ! jq -e ".$field != null" "$artifact_path" >/dev/null 2>&1; then
    errors+=("missing or null required field: $field")
  fi
done

# ==== Special semantic checks ====

case "$schema_name" in
  verify_result)
    # verdict must be one of the allowed values
    verdict="$(jq -re '.verdict // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ -n "$verdict" ]]; then
      case "$verdict" in
        RECONCILED|RECONCILED_WITH_DEBT|NOT_RECONCILED) ;;
        *) errors+=("verdict '$verdict' not in allowed values: RECONCILED, RECONCILED_WITH_DEBT, NOT_RECONCILED") ;;
      esac
    fi
    ;;
  review_receipt)
    # review_basis must be one of the allowed values
    basis="$(jq -re '.review_basis // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ -n "$basis" ]]; then
      case "$basis" in
        STORY_SCOPE|FIX_DIFF_AT_REGRESSION) ;;
        *) errors+=("review_basis '$basis' not in allowed values: STORY_SCOPE, FIX_DIFF_AT_REGRESSION") ;;
      esac
    fi
    ;;
  phase_mapping)
    # unmapped_p0_p1_count == 0 is a warning (not hard fail)
    unmapped="$(jq -re '.unmapped_p0_p1_count // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ -n "$unmapped" && "$unmapped" != "0" ]]; then
      echo "WARN: unmapped_p0_p1_count=$unmapped (expected 0)" >&2
    fi
    ;;
  r3_external_manifest)
    # cycle must be C1
    cycle="$(jq -re '.cycle // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ -n "$cycle" && "$cycle" != "C1" ]]; then
      errors+=("cycle '$cycle' must be 'C1' for r3_external_manifest")
    fi
    # citation booleans must be true
    enf="$(jq -re '.validated_preexisting_enforcement_citation // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ "$enf" != "true" ]]; then
      errors+=("validated_preexisting_enforcement_citation must be true for C1")
    fi
    test_cit="$(jq -re '.validated_preexisting_test_citation // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ "$test_cit" != "true" ]]; then
      errors+=("validated_preexisting_test_citation must be true for C1")
    fi
    # tools must have at least 1 entry
    tool_count="$(jq -re '.tools | length' "$artifact_path" 2>/dev/null || echo 0)"
    if [[ "$tool_count" -lt 1 ]]; then
      errors+=("tools array must have at least 1 entry")
    fi
    ;;
  r7_external_manifest)
    # cycle must be C2
    cycle="$(jq -re '.cycle // empty' "$artifact_path" 2>/dev/null || true)"
    if [[ -n "$cycle" && "$cycle" != "C2" ]]; then
      errors+=("cycle '$cycle' must be 'C2' for r7_external_manifest")
    fi
    # base_commit length
    bc_len="$(jq -re '.base_commit | length' "$artifact_path" 2>/dev/null || echo 0)"
    if [[ "$bc_len" -lt 7 ]]; then
      errors+=("base_commit too short (length=$bc_len, need >= 7)")
    fi
    # tools must have at least 1 entry
    tool_count="$(jq -re '.tools | length' "$artifact_path" 2>/dev/null || echo 0)"
    if [[ "$tool_count" -lt 1 ]]; then
      errors+=("tools array must have at least 1 entry")
    fi
    ;;
esac

# ==== Result ====

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "FAIL: $artifact_path failed validation for schema '$schema_name'" >&2
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

echo "OK: $artifact_path is valid ($schema_name)"
exit 0
