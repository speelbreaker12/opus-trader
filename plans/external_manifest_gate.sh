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

# ── Gate check 4: Python deep validation (Step A-F) ──────────────────
# The v2 Python validator performs the full 6-step algorithm:
#   A: schema validation, B: provenance, C: combos, D: artifact integrity,
#   E: cycle-specific semantics (including review_basis_check), F: consistency.

validator_py="$repo_root/plans/validators/validate_external_manifest.py"
if [[ ! -f "$validator_py" ]]; then
  # Fall back to legacy location
  validator_py="$repo_root/plans/validate_external_manifest.py"
fi
if [[ ! -f "$validator_py" ]]; then
  die "$gate_name: Python validator not found"
fi

# Resolve schema path
schema_r3="$repo_root/specs/schemas/recon/r3_external_manifest.schema.json"
schema_r7="$repo_root/specs/schemas/recon/r7_external_manifest.schema.json"
schema_path=""
if [[ "$gate_type" == "r3" && -f "$schema_r3" ]]; then
  schema_path="$schema_r3"
elif [[ "$gate_type" == "r7" && -f "$schema_r7" ]]; then
  schema_path="$schema_r7"
fi

# Build validator command
py_args=(
  --manifest "$manifest_path"
  --format json
  --repo-root "$repo_root"
  --cycle "$expected_cycle"
  --expect-phase "$expected_phase"
  --expect-story-id "$story_id"
  --expect-slice-id "$slice_id"
  --require-combo codex:enriched
  --require-combo codex:generic
  --require-combo opus:enriched
  --require-combo opus:generic
)
if [[ -n "$schema_path" ]]; then
  py_args+=(--schema "$schema_path")
fi

py_output=$(python3 "$validator_py" "${py_args[@]}" 2>&1) || true
py_status=$(echo "$py_output" | python3 -c "import sys,json; print(json.load(sys.stdin).get('status','UNKNOWN'))" 2>/dev/null) || py_status="UNKNOWN"
# Extract first failure_code for structured gate block message
first_failure=$(echo "$py_output" | python3 -c "
import sys,json
try:
    d=json.load(sys.stdin)
    codes=d.get('failure_codes',[])
    print(codes[0] if codes else '')
except: print('')
" 2>/dev/null) || first_failure=""

echo "  Python validator status: $py_status" >&2
if [[ "$py_status" != "PASS" ]]; then
  echo "$py_output" >&2
  # Block with structured gate name including first failure code
  incomplete_gate="${gate_name/COMPLETE/INCOMPLETE}"
  if [[ -n "$first_failure" ]]; then
    die "$incomplete_gate:$first_failure"
  else
    die "$incomplete_gate"
  fi
fi

# Extract review count from validator output
review_count=$(echo "$py_output" | python3 -c "import sys,json; print(len(json.load(sys.stdin).get('artifacts',[])))" 2>/dev/null) || review_count="?"

# ── All checks passed ────────────────────────────────────────────────

echo ""
echo "GATE PASS: $gate_name"
echo "  story_id:  $story_id"
echo "  slice_id:  $slice_id"
echo "  manifest:  $manifest_path"
echo "  reviews:   $review_count"
echo "  status:    PASS"
exit 0
