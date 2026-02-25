#!/usr/bin/env bash
set -euo pipefail

# external_manifest_gate.sh — Gate for R3/R7 external manifest validation.
#
# Fail-closed gate that validates external manifest JSON against v2 schemas
# and emits named verdicts for the reconciliation pipeline.
#
# Gate verdicts:
#   R3_EXTERNAL_REVIEWS_C1_COMPLETE  (all 4 combos, provenance, citation checks)
#   R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO
#   R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE (1 combo, 1-path flow)
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
  r7 → R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO
        R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE
USAGE
}

die() { echo "GATE FAIL: $*" >&2; exit 2; }
# exit 1 = manifest not found (non-fatal in prd_set_pass.sh)
# exit 2 = real gate failure (fatal in prd_set_pass.sh)
die_not_found() { echo "GATE SKIP: $*" >&2; exit 1; }

gate_type="${1:-}"
story_id="${2:-}"
slice_id="${3:-}"

[[ -n "$gate_type" && -n "$story_id" && -n "$slice_id" ]] || { usage >&2; exit 2; }
shift 3

manifest_path=""
check_files=""
artifacts_root=""
# resolved C2 required combos
legacy_cycle2_path=0
required_combos=()

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
    gate_name="R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO"
    bash_artifact_type="r7_external_manifest"
    default_manifest="$artifacts_root/$slice_id/external/cycle2/$story_id/R7_EXTERNAL_MANIFEST.json"
    expected_phase="R7d"
    expected_cycle="C2"
    expected_review_basis="FIX_DIFF + AT_REGRESSION (Cycle 2)"
    gate_incomplete_prefix="R7D_EXTERNAL_REVIEWS_C2_INCOMPLETE"
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
  die_not_found "$gate_name: manifest not found at $manifest_path"
fi

echo "INFO: Validating $gate_name for $story_id ($slice_id)" >&2
echo "  manifest: $manifest_path" >&2

# ── Gate check 2: Valid JSON ─────────────────────────────────────────

if ! jq empty "$manifest_path" 2>/dev/null; then
  die "$gate_name: manifest is not valid JSON"
fi

# ── Gate check 2b: cycle2 mode + required combinations ─────────────

if [[ "$gate_type" == "r7" ]]; then
  cycle2_mode="$(jq -r '.cycle2_path.mode // empty' "$manifest_path" 2>/dev/null || true)"
  if [[ -z "$cycle2_mode" || "$cycle2_mode" == "null" ]]; then
    cycle2_mode="dual_combo"
    legacy_cycle2_path=1
  fi

  gate_name="R7D_EXTERNAL_REVIEWS_C2_COMPLETE_DUAL_COMBO"

  case "$cycle2_mode" in
    dual_combo)
      c2_single_combo_tool=""
      c2_single_combo_ps=""
      echo "INFO: cycle2_path.mode=dual_combo: dual prompt coverage required for ${story_id}" >&2
      required_combos=(
        "codex:enriched"
        "codex:generic"
        "kimi:enriched"
        "kimi:generic"
      )
      ;;
    recon_clean_single)
      gate_name="R7D_EXTERNAL_REVIEWS_C2_COMPLETE_RECON_CLEAN_SINGLE"
      c2_single_combo_tool="$(jq -r '.cycle2_path.single_combo_choice.tool // empty' "$manifest_path" 2>/dev/null || true)"
      c2_single_combo_ps="$(jq -r '.cycle2_path.single_combo_choice.prompt_style // empty' "$manifest_path" 2>/dev/null || true)"
      c2_single_combo_justification="$(jq -r '.cycle2_path.single_combo_justification // empty' "$manifest_path" 2>/dev/null || true)"
      c2_single_combo_justification="$(echo "$c2_single_combo_justification" | tr -d '[:space:]')"
      if [[ -z "$c2_single_combo_tool" || -z "$c2_single_combo_ps" ]]; then
        die "$gate_incomplete_prefix:R7D_C2_SINGLE_MISMATCH:single_combo_choice.tool/prompt_style missing for recon_clean_single"
      fi
      if [[ -z "$c2_single_combo_justification" ]]; then
        die "$gate_incomplete_prefix:R7D_C2_SINGLE_MISMATCH:single_combo_justification required for recon_clean_single"
      fi
      required_combos=("$c2_single_combo_tool:$c2_single_combo_ps")

      if ! jq -e --arg tool "$c2_single_combo_tool" --arg ps "$c2_single_combo_ps" \
        '.required_combinations == [ {tool:$tool, prompt_style:$ps} ]' \
        "$manifest_path" >/dev/null; then
        die "$gate_incomplete_prefix:R7D_C2_SINGLE_MISMATCH"
      fi

      if [[ -n "$c2_single_combo_justification" ]]; then
        echo "INFO: cycle2_path.mode=recon_clean_single for ${story_id}; single combo: $c2_single_combo_tool:$c2_single_combo_ps" >&2
      fi
      ;;
    *)
      die "$gate_incomplete_prefix:R7D_C2_MODE_MISMATCH:unsupported cycle2_path.mode '$cycle2_mode'"
      ;;
  esac

  if [[ "$legacy_cycle2_path" -eq 1 ]]; then
    echo "INFO: cycle2_path absent; assuming legacy dual-combo C2 path for $story_id (WARN: set cycle2_path.mode before regenerating manifest)" >&2
  fi
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
)
if [[ "$gate_type" == "r7" && "${#required_combos[@]}" -gt 0 ]]; then
  for required_combo in "${required_combos[@]}"; do
    py_args+=(--require-combo "$required_combo")
  done
fi
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
