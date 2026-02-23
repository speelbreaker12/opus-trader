#!/usr/bin/env bash
# validate_recon_artifact.sh — Validate reconciliation artifact JSON files
# against expected structure for each artifact type.
#
# Usage: validate_recon_artifact.sh <artifact_type> <file.json>
#
# Artifact types: r3_external_manifest, r7_external_manifest
set -euo pipefail

usage() {
    echo "Usage: validate_recon_artifact.sh <artifact_type> <file.json>" >&2
    echo "" >&2
    echo "Artifact types:" >&2
    echo "  r3_external_manifest   R3 External Manifest (Cycle 1)" >&2
    echo "  r7_external_manifest   R7 External Manifest (Cycle 2)" >&2
    exit 2
}

if [[ $# -lt 2 ]]; then
    usage
fi

ARTIFACT_TYPE="$1"
FILE="$2"

if [[ ! -f "$FILE" ]]; then
    echo "ERROR: file not found: $FILE" >&2
    exit 1
fi

# Validate JSON syntax
if ! jq empty "$FILE" 2>/dev/null; then
    echo "ERROR: invalid JSON in $FILE" >&2
    exit 1
fi

ERRORS=0

check_field() {
    local field="$1"
    local desc="$2"
    if ! jq -e ".$field" "$FILE" >/dev/null 2>&1; then
        echo "  FAIL: missing required field '$field' ($desc)" >&2
        ERRORS=$((ERRORS + 1))
    fi
}

check_const() {
    local field="$1"
    local expected="$2"
    local actual
    actual=$(jq -r ".$field // empty" "$FILE" 2>/dev/null)
    if [[ "$actual" != "$expected" ]]; then
        echo "  FAIL: '$field' must be '$expected', got '$actual'" >&2
        ERRORS=$((ERRORS + 1))
    fi
}

check_enum() {
    local field="$1"
    shift
    local actual
    actual=$(jq -r ".$field // empty" "$FILE" 2>/dev/null)
    for allowed in "$@"; do
        if [[ "$actual" == "$allowed" ]]; then
            return 0
        fi
    done
    echo "  FAIL: '$field' must be one of [$*], got '$actual'" >&2
    ERRORS=$((ERRORS + 1))
}

check_min_array_len() {
    local field="$1"
    local min_len="$2"
    local actual_len
    actual_len=$(jq -r ".$field | if type == \"array\" then length else -1 end" "$FILE" 2>/dev/null)
    if [[ "$actual_len" -lt "$min_len" ]]; then
        echo "  FAIL: '$field' must have >= $min_len items, got $actual_len" >&2
        ERRORS=$((ERRORS + 1))
    fi
}

check_hexsha() {
    local field="$1"
    local min_len="${2:-7}"
    local val
    val=$(jq -r ".$field // empty" "$FILE" 2>/dev/null)
    if [[ -z "$val" ]]; then
        return 0  # Missing field caught by check_field
    fi
    if ! echo "$val" | grep -qE "^[0-9a-f]{${min_len},40}$"; then
        echo "  FAIL: '$field' must be hex SHA (>=${min_len} chars), got '$val'" >&2
        ERRORS=$((ERRORS + 1))
    fi
}

# -----------------------------------------------------------------------
# R3 External Manifest
# -----------------------------------------------------------------------
validate_r3_external_manifest() {
    echo "Validating R3 External Manifest: $FILE"

    # Top-level required fields
    check_field "provenance" "top-level provenance object"
    check_field "story_id" "story identifier"
    check_field "slice_id" "slice identifier"
    check_field "phase" "phase constant"
    check_field "cycle" "cycle constant"
    check_field "required_combinations" "required tool x prompt combos"
    check_field "reviews" "review entries array"
    check_field "validation" "validation results object"

    # Semantic checks
    check_const "phase" "R3"
    check_const "cycle" "C1"
    check_min_array_len "reviews" 4
    check_min_array_len "required_combinations" 4
    check_enum "validation.status" "PASS" "FAIL"

    # Provenance checks
    check_field "provenance.tool" "provenance tool"
    check_const "provenance.tool" "script"
    check_const "provenance.cycle" "C1"
    check_const "provenance.phase_equivalent" "R3"
    check_field "provenance.head_commit" "provenance head commit"
    check_hexsha "provenance.head_commit"
    check_field "provenance.schema_version" "schema version"
    check_const "provenance.schema_version" "r3_external_manifest.v2"

    # Validation object checks
    check_field "validation.review_basis_check" "review basis check"
    check_field "validation.preexisting_enforcement_citation_check" "enforcement citation check"
    check_field "validation.preexisting_test_citation_check" "test citation check"
    check_field "validation.diff_only_review_check" "diff-only review check"
    for ck in review_basis_check preexisting_enforcement_citation_check preexisting_test_citation_check diff_only_review_check; do
        check_enum "validation.$ck" "PASS" "FAIL"
    done
}

# -----------------------------------------------------------------------
# R7 External Manifest
# -----------------------------------------------------------------------
validate_r7_external_manifest() {
    echo "Validating R7 External Manifest: $FILE"

    # Top-level required fields
    check_field "provenance" "top-level provenance object"
    check_field "story_id" "story identifier"
    check_field "slice_id" "slice identifier"
    check_field "phase" "phase constant"
    check_field "cycle" "cycle constant"
    check_field "required_combinations" "required tool x prompt combos"
    check_field "reviews" "review entries array"
    check_field "regression_scope" "regression scope object"
    check_field "validation" "validation results object"

    # Semantic checks
    check_const "phase" "R7d"
    check_const "cycle" "C2"
    check_min_array_len "reviews" 4
    check_min_array_len "required_combinations" 4
    check_enum "validation.status" "PASS" "FAIL"

    # Provenance checks
    check_field "provenance.tool" "provenance tool"
    check_const "provenance.tool" "script"
    check_const "provenance.cycle" "C2"
    check_const "provenance.phase_equivalent" "R7d"
    check_field "provenance.head_commit" "provenance head commit"
    check_hexsha "provenance.head_commit"
    check_field "provenance.base_commit" "provenance base commit"
    check_hexsha "provenance.base_commit"
    check_field "provenance.schema_version" "schema version"
    check_const "provenance.schema_version" "r7_external_manifest.v2"

    # Regression scope checks
    check_field "regression_scope.base_commit" "regression base commit"
    check_hexsha "regression_scope.base_commit"
    check_field "regression_scope.head_commit" "regression head commit"
    check_hexsha "regression_scope.head_commit"
    check_field "regression_scope.affected_ats" "affected ATs"
    check_field "regression_scope.changed_files" "changed files"

    # Validation object checks
    check_field "validation.review_basis_check" "review basis check"
    check_field "validation.required_combinations_check" "required combinations check"
    check_field "validation.head_commit_alignment_check" "head commit alignment check"
    check_field "validation.base_commit_alignment_check" "base commit alignment check"
    for ck in review_basis_check required_combinations_check head_commit_alignment_check base_commit_alignment_check; do
        check_enum "validation.$ck" "PASS" "FAIL"
    done
}

# -----------------------------------------------------------------------
# Dispatch
# -----------------------------------------------------------------------
case "$ARTIFACT_TYPE" in
    r3_external_manifest)
        validate_r3_external_manifest
        ;;
    r7_external_manifest)
        validate_r7_external_manifest
        ;;
    *)
        echo "ERROR: unknown artifact type '$ARTIFACT_TYPE'" >&2
        usage
        ;;
esac

if [[ $ERRORS -gt 0 ]]; then
    echo "FAIL: $ERRORS validation error(s)" >&2
    exit 1
fi

echo "PASS: $ARTIFACT_TYPE validated successfully"
exit 0
