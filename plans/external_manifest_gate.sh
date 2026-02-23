#!/usr/bin/env bash
set -euo pipefail

# external_manifest_gate.sh — Gate for R3/R7 external manifest validation.
#
# Fail-closed gate that validates external manifest JSON against v2 schemas
# and emits named verdicts for the reconciliation pipeline.
#
# Gate verdicts:
#   R3_EXTERNAL_REVIEWS_C1_COMPLETE  (all 4 combos, provenance, citation checks)
#   R7D_EXTERNAL_REVIEWS_C2_COMPLETE (all 4 combos, provenance, commit alignment)
#
# Usage:
#   plans/external_manifest_gate.sh r3 <STORY_ID> <SLICE_ID> [--manifest <path>] [--check-files]
#   plans/external_manifest_gate.sh r7 <STORY_ID> <SLICE_ID> [--manifest <path>] [--check-files]

usage() {
  cat <<'USAGE'
Usage:
  plans/external_manifest_gate.sh <r3|r7> <STORY_ID> <SLICE_ID> [options]

Options:
  --manifest PATH   Path to manifest JSON (default: auto-discover)
  --check-files     Verify artifact files exist and sha256 matches
  --artifacts-root  Override artifacts root (default: reviews/reconciliations)

Gate names emitted:
  r3 → R3_EXTERNAL_REVIEWS_C1_COMPLETE
  r7 → R7D_EXTERNAL_REVIEWS_C2_COMPLETE
USAGE
}

die() { echo "GATE FAIL: $*" >&2; exit 1; }

gate_type="${1:-}"
story_id="${2:-}"
slice_id="${3:-}"

[[ -n "$gate_type" && -n "$story_id" && -n "$slice_id" ]] || { usage >&2; exit 2; }
shift 3

manifest_path=""
check_files=""
artifacts_root=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --manifest)
      manifest_path="${2:?missing manifest path}"
      shift 2
      ;;
    --check-files)
      check_files="--check-files"
      shift
      ;;
    --artifacts-root)
      artifacts_root="${2:?missing path}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$repo_root"

if [[ -z "$artifacts_root" ]]; then
  artifacts_root="$repo_root/reviews/reconciliations"
fi
if [[ "$artifacts_root" != /* ]]; then
  artifacts_root="$repo_root/$artifacts_root"
fi

# ── Resolve gate name and default manifest path ──────────────────────

case "$gate_type" in
  r3)
    gate_name="R3_EXTERNAL_REVIEWS_C1_COMPLETE"
    bash_artifact_type="r3_external_manifest"
    default_manifest="$artifacts_root/$slice_id/external/cycle1/$story_id/R3_EXTERNAL_MANIFEST.json"
    expected_phase="R3"
    expected_cycle="C1"
    expected_review_basis="STORY_SCOPE (Cycle 1)"
    ;;
  r7)
    gate_name="R7D_EXTERNAL_REVIEWS_C2_COMPLETE"
    bash_artifact_type="r7_external_manifest"
    default_manifest="$artifacts_root/$slice_id/external/cycle2/$story_id/R7_EXTERNAL_MANIFEST.json"
    expected_phase="R7d"
    expected_cycle="C2"
    expected_review_basis="FIX_DIFF + AT_REGRESSION (Cycle 2)"
    ;;
  *)
    die "unknown gate type '$gate_type' (expected: r3 or r7)"
    ;;
esac

if [[ -z "$manifest_path" ]]; then
  manifest_path="$default_manifest"
fi

# ── Gate check 1: Manifest exists ────────────────────────────────────

if [[ ! -f "$manifest_path" ]]; then
  die "$gate_name: manifest not found at $manifest_path"
fi

echo "INFO: Validating $gate_name for $story_id ($slice_id)" >&2
echo "  manifest: $manifest_path" >&2

# ── Gate check 2: Valid JSON ─────────────────────────────────────────

if ! jq empty "$manifest_path" 2>/dev/null; then
  die "$gate_name: manifest is not valid JSON"
fi

# ── Gate check 3: Bash structural validation ─────────────────────────

validator_sh="$repo_root/plans/validate_recon_artifact.sh"
if [[ ! -x "$validator_sh" ]]; then
  die "$gate_name: bash validator not found or not executable: $validator_sh"
fi

if ! "$validator_sh" "$bash_artifact_type" "$manifest_path" 2>&1; then
  die "$gate_name: bash structural validation failed"
fi

# ── Gate check 4: Python deep validation ─────────────────────────────

validator_py="$repo_root/plans/validate_external_manifest.py"
if [[ ! -f "$validator_py" ]]; then
  die "$gate_name: Python validator not found: $validator_py"
fi

if ! python3 "$validator_py" "$manifest_path" $check_files 2>&1; then
  die "$gate_name: Python schema validation failed"
fi

# ── Gate check 5: Semantic field verification ────────────────────────

errors=0

# Verify story_id and slice_id match arguments
manifest_story=$(jq -r '.story_id // empty' "$manifest_path")
manifest_slice=$(jq -r '.slice_id // empty' "$manifest_path")
if [[ "$manifest_story" != "$story_id" ]]; then
  echo "  FAIL: story_id mismatch: manifest='$manifest_story', expected='$story_id'" >&2
  errors=$((errors + 1))
fi
if [[ "$manifest_slice" != "$slice_id" ]]; then
  echo "  FAIL: slice_id mismatch: manifest='$manifest_slice', expected='$slice_id'" >&2
  errors=$((errors + 1))
fi

# Verify phase and cycle
manifest_phase=$(jq -r '.phase // empty' "$manifest_path")
manifest_cycle=$(jq -r '.cycle // empty' "$manifest_path")
if [[ "$manifest_phase" != "$expected_phase" ]]; then
  echo "  FAIL: phase mismatch: manifest='$manifest_phase', expected='$expected_phase'" >&2
  errors=$((errors + 1))
fi
if [[ "$manifest_cycle" != "$expected_cycle" ]]; then
  echo "  FAIL: cycle mismatch: manifest='$manifest_cycle', expected='$expected_cycle'" >&2
  errors=$((errors + 1))
fi

# Verify required combos present in reviews
for combo in "codex:enriched" "codex:generic" "opus:enriched" "opus:generic"; do
  IFS=: read -r tool prompt_style <<< "$combo"
  count=$(jq --arg t "$tool" --arg p "$prompt_style" \
    '[.reviews[] | select(.tool == $t and .prompt_style == $p)] | length' \
    "$manifest_path" 2>/dev/null || echo 0)
  if [[ "$count" -lt 1 ]]; then
    echo "  FAIL: missing required combo: tool=$tool, prompt_style=$prompt_style" >&2
    errors=$((errors + 1))
  fi
done

# Verify every review has provenance with required fields
review_count=$(jq '.reviews | length' "$manifest_path" 2>/dev/null || echo 0)
for ((i=0; i<review_count; i++)); do
  for field in tool model prompt_style cycle phase_equivalent; do
    val=$(jq -r ".reviews[$i].provenance.$field // empty" "$manifest_path" 2>/dev/null)
    if [[ -z "$val" ]]; then
      echo "  FAIL: reviews[$i].provenance missing required field '$field'" >&2
      errors=$((errors + 1))
    fi
  done

  # Verify review_basis on each entry
  entry_basis=$(jq -r ".reviews[$i].review_basis // empty" "$manifest_path" 2>/dev/null)
  if [[ "$entry_basis" != "$expected_review_basis" ]]; then
    echo "  FAIL: reviews[$i].review_basis='$entry_basis', expected='$expected_review_basis'" >&2
    errors=$((errors + 1))
  fi
done

# R3-specific checks
if [[ "$gate_type" == "r3" ]]; then
  # Pre-existing enforcement citation check
  citation_check=$(jq -r '.validation.preexisting_enforcement_citation_check // empty' "$manifest_path" 2>/dev/null)
  if [[ "$citation_check" != "PASS" ]]; then
    echo "  FAIL: validation.preexisting_enforcement_citation_check != PASS (got '$citation_check')" >&2
    errors=$((errors + 1))
  fi

  # Pre-existing test citation check
  test_check=$(jq -r '.validation.preexisting_test_citation_check // empty' "$manifest_path" 2>/dev/null)
  if [[ "$test_check" != "PASS" ]]; then
    echo "  FAIL: validation.preexisting_test_citation_check != PASS (got '$test_check')" >&2
    errors=$((errors + 1))
  fi

  # Diff-only review check
  diff_check=$(jq -r '.validation.diff_only_review_check // empty' "$manifest_path" 2>/dev/null)
  if [[ "$diff_check" != "PASS" ]]; then
    echo "  FAIL: validation.diff_only_review_check != PASS (got '$diff_check')" >&2
    errors=$((errors + 1))
  fi
fi

# R7-specific checks
if [[ "$gate_type" == "r7" ]]; then
  # head_commit matches manifest for all entries
  head_check=$(jq -r '.validation.head_commit_alignment_check // empty' "$manifest_path" 2>/dev/null)
  if [[ "$head_check" != "PASS" ]]; then
    echo "  FAIL: validation.head_commit_alignment_check != PASS (got '$head_check')" >&2
    errors=$((errors + 1))
  fi

  # base_commit matches manifest for all entries
  base_check=$(jq -r '.validation.base_commit_alignment_check // empty' "$manifest_path" 2>/dev/null)
  if [[ "$base_check" != "PASS" ]]; then
    echo "  FAIL: validation.base_commit_alignment_check != PASS (got '$base_check')" >&2
    errors=$((errors + 1))
  fi
fi

# Overall validation status must be PASS
overall=$(jq -r '.validation.status // empty' "$manifest_path" 2>/dev/null)
if [[ "$overall" != "PASS" ]]; then
  echo "  FAIL: validation.status != PASS (got '$overall')" >&2
  errors=$((errors + 1))
fi

if [[ "$errors" -gt 0 ]]; then
  die "$gate_name: $errors semantic check(s) failed"
fi

# ── All checks passed ────────────────────────────────────────────────

echo ""
echo "GATE PASS: $gate_name"
echo "  story_id:  $story_id"
echo "  slice_id:  $slice_id"
echo "  manifest:  $manifest_path"
echo "  reviews:   $review_count"
echo "  status:    PASS"
exit 0
