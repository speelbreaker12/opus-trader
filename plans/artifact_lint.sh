#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

MATRIX_DOC="docs/recon/artifact_field_contract.md"
RECON_VALIDATOR="plans/validate_recon_artifact.sh"
CONTRACT_SCHEMA="docs/schemas/contract_review.schema.json"
CONTRACT_VALIDATOR="plans/contract_review_validate.sh"

MODE="quick"
LINT_SCOPE="changed"
VERIFY_ARTIFACTS_DIR=""

known_schemas=""
json_checked=0
recon_validated=0
contract_review_validated=0
strict_markers_checked=0

errors=()

usage() {
  cat <<'USAGE'
Usage: plans/artifact_lint.sh [--changed|--all] [--mode quick|full] [--verify-artifacts-dir DIR]

Options:
  --changed                    Lint only changed/untracked JSON artifacts (default)
  --all                        Lint all JSON artifacts in artifacts/story, reviews/reconciliations, artifacts/verify
  --mode quick|full            Set lint mode semantics (default: quick)
  --verify-artifacts-dir DIR   Verify-run artifact directory for strict full-mode checks
USAGE
}

add_error() {
  errors+=("$1")
}

require_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    add_error "missing required file: $file"
  fi
}

require_exec() {
  local file="$1"
  if [[ ! -x "$file" ]]; then
    add_error "missing executable file: $file"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --changed)
        LINT_SCOPE="changed"
        shift
        ;;
      --all)
        LINT_SCOPE="all"
        shift
        ;;
      --mode)
        if [[ $# -lt 2 ]]; then
          echo "FAIL: --mode requires quick|full" >&2
          usage >&2
          exit 2
        fi
        MODE="$2"
        shift 2
        ;;
      --mode=*)
        MODE="${1#*=}"
        shift
        ;;
      --verify-artifacts-dir)
        if [[ $# -lt 2 ]]; then
          echo "FAIL: --verify-artifacts-dir requires a path" >&2
          usage >&2
          exit 2
        fi
        VERIFY_ARTIFACTS_DIR="$2"
        shift 2
        ;;
      --verify-artifacts-dir=*)
        VERIFY_ARTIFACTS_DIR="${1#*=}"
        shift
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "FAIL: unknown option: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done
}

validate_args() {
  case "$MODE" in
    quick|full) ;;
    *)
      echo "FAIL: invalid --mode '$MODE' (expected quick|full)" >&2
      exit 2
      ;;
  esac

  case "$LINT_SCOPE" in
    changed|all) ;;
    *)
      echo "FAIL: invalid lint scope '$LINT_SCOPE'" >&2
      exit 2
      ;;
  esac
}

run_recon_validator() {
  local schema_name="$1"
  local artifact_path="$2"
  local out=""
  local rc=0

  set +e
  out="$($RECON_VALIDATOR "$schema_name" "$artifact_path" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    add_error "recon schema '$schema_name' failed for $artifact_path :: ${out//$'\n'/ ; }"
    return
  fi

  recon_validated=$((recon_validated + 1))
}

run_contract_validator() {
  local artifact_path="$1"
  local out=""
  local rc=0

  set +e
  out="$($CONTRACT_VALIDATOR "$artifact_path" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -ne 0 ]]; then
    add_error "contract_review schema failed for $artifact_path :: ${out//$'\n'/ ; }"
    return
  fi

  contract_review_validated=$((contract_review_validated + 1))
}

check_matrix_coverage() {
  local schema_lines=""
  local schema=""
  local required_fields=""
  local field=""

  require_file "$MATRIX_DOC"
  require_exec "$RECON_VALIDATOR"
  require_exec "$CONTRACT_VALIDATOR"
  require_file "$CONTRACT_SCHEMA"

  if [[ ${#errors[@]} -gt 0 ]]; then
    return
  fi

  known_schemas="$(sed -n 's/^known_schemas="\(.*\)"/\1/p' "$RECON_VALIDATOR" | head -n1)"
  if [[ -z "$known_schemas" ]]; then
    known_schemas="gap_list verify_result review_receipt phase_mapping premortem_ready lead_eval_sidecar self_review_sidecar review_artifact_sidecar r3_external_manifest r7_external_manifest"
  fi

  schema_lines="$(printf '%s\n' "$known_schemas" | tr ' ' '\n' | sed '/^$/d')"
  while IFS= read -r schema; do
    [[ -n "$schema" ]] || continue
    if ! grep -Eq "(^|[^A-Za-z0-9_])${schema}([^A-Za-z0-9_]|$)" "$MATRIX_DOC"; then
      add_error "matrix missing validator schema row/token: $schema"
    fi
  done <<< "$schema_lines"

  required_fields="$(jq -r '.required[]' "$CONTRACT_SCHEMA" 2>/dev/null || true)"
  if [[ -z "$required_fields" ]]; then
    add_error "failed to read required fields from $CONTRACT_SCHEMA"
    return
  fi

  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    if ! grep -Eq "\`${field}\`|(^|[^A-Za-z0-9_])${field}([^A-Za-z0-9_]|$)" "$MATRIX_DOC"; then
      add_error "matrix missing contract_review required field: $field"
    fi
  done <<< "$required_fields"
}

check_verify_artifacts_dir_strict() {
  local required_gates=("preflight" "verify_gate_contract")
  local gate=""
  local marker=""
  local rc_value=""

  if [[ "$MODE" != "full" ]]; then
    return
  fi

  if [[ -z "$VERIFY_ARTIFACTS_DIR" ]]; then
    add_error "full mode requires --verify-artifacts-dir"
    return
  fi

  if [[ ! -d "$VERIFY_ARTIFACTS_DIR" ]]; then
    add_error "verify artifacts dir not found: $VERIFY_ARTIFACTS_DIR"
    return
  fi

  for gate in "${required_gates[@]}"; do
    for marker in log rc time; do
      if [[ ! -f "$VERIFY_ARTIFACTS_DIR/${gate}.${marker}" ]]; then
        add_error "verify artifacts dir missing marker: ${gate}.${marker}"
      else
        strict_markers_checked=$((strict_markers_checked + 1))
      fi
    done

    if [[ -f "$VERIFY_ARTIFACTS_DIR/${gate}.rc" ]]; then
      rc_value="$(tr -d '[:space:]' < "$VERIFY_ARTIFACTS_DIR/${gate}.rc" 2>/dev/null || true)"
      if [[ "$rc_value" != "0" ]]; then
        add_error "verify artifacts dir marker ${gate}.rc is non-zero: ${rc_value:-<empty>}"
      fi
    fi
  done

  if [[ -f "$VERIFY_ARTIFACTS_DIR/FAILED_GATE" ]]; then
    add_error "verify artifacts dir contains FAILED_GATE"
  fi
}

collect_candidate_json() {
  local out_file="$1"
  local rel=""

  : > "$out_file"

  if [[ "$LINT_SCOPE" == "all" ]]; then
    if [[ -d "$ROOT/artifacts/story" ]]; then
      find "$ROOT/artifacts/story" -type f -name '*.json' -print >> "$out_file"
    fi
    if [[ -d "$ROOT/reviews/reconciliations" ]]; then
      find "$ROOT/reviews/reconciliations" -type f -name '*.json' -print >> "$out_file"
    fi
    if [[ -d "$ROOT/artifacts/verify" ]]; then
      find "$ROOT/artifacts/verify" -type f -name '*.json' -print >> "$out_file"
    fi
  else
    while IFS= read -r rel; do
      [[ -n "$rel" ]] || continue
      [[ "$rel" == *.json ]] || continue
      [[ -f "$ROOT/$rel" ]] || continue
      printf '%s\n' "$ROOT/$rel" >> "$out_file"
    done < <(
      {
        git diff --name-only HEAD -- artifacts/story reviews/reconciliations artifacts/verify 2>/dev/null || true
        git ls-files --others --exclude-standard -- artifacts/story reviews/reconciliations artifacts/verify 2>/dev/null || true
      } | sed '/^$/d' | sort -u
    )
  fi

  # In strict full mode, always include JSON in the verify artifacts dir (if provided).
  if [[ -n "$VERIFY_ARTIFACTS_DIR" && -d "$VERIFY_ARTIFACTS_DIR" ]]; then
    find "$VERIFY_ARTIFACTS_DIR" -type f -name '*.json' -print >> "$out_file"
  fi

  if [[ -s "$out_file" ]]; then
    sort -u "$out_file" -o "$out_file"
  fi
}

lint_candidate_json() {
  local list_file=""
  local file=""
  local base=""
  local schema_version=""

  list_file="$(mktemp)"
  collect_candidate_json "$list_file"

  if [[ ! -s "$list_file" ]]; then
    rm -f "$list_file"
    return
  fi

  while IFS= read -r file; do
    [[ -n "$file" ]] || continue

    if ! jq empty "$file" >/dev/null 2>&1; then
      add_error "invalid JSON: $file"
      continue
    fi
    json_checked=$((json_checked + 1))

    base="$(basename "$file")"

    if [[ "$base" == "contract_review.json" ]]; then
      run_contract_validator "$file"
      continue
    fi

    if [[ "$base" == "R3_EXTERNAL_MANIFEST.json" ]]; then
      run_recon_validator "r3_external_manifest" "$file"
      continue
    fi

    if [[ "$base" == "R7_EXTERNAL_MANIFEST.json" ]]; then
      run_recon_validator "r7_external_manifest" "$file"
      continue
    fi

    schema_version="$(jq -r '.schema_version // empty' "$file" 2>/dev/null || true)"
    case "$schema_version" in
      gap_list.v*) run_recon_validator "gap_list" "$file" ;;
      verify_result.v*) run_recon_validator "verify_result" "$file" ;;
      review_receipt.v*) run_recon_validator "review_receipt" "$file" ;;
      phase_mapping.v*) run_recon_validator "phase_mapping" "$file" ;;
      premortem_ready.v*) run_recon_validator "premortem_ready" "$file" ;;
      lead_eval_sidecar.v*) run_recon_validator "lead_eval_sidecar" "$file" ;;
      self_review_sidecar.v*) run_recon_validator "self_review_sidecar" "$file" ;;
      review_artifact_sidecar.v*) run_recon_validator "review_artifact_sidecar" "$file" ;;
      *) ;;
    esac
  done < "$list_file"

  rm -f "$list_file"
}

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required but not found" >&2
  exit 2
fi

parse_args "$@"
validate_args
check_matrix_coverage
check_verify_artifacts_dir_strict
lint_candidate_json

if [[ ${#errors[@]} -gt 0 ]]; then
  echo "FAIL: artifact lint found ${#errors[@]} issue(s)" >&2
  for err in "${errors[@]}"; do
    echo "  - $err" >&2
  done
  exit 1
fi

echo "OK: artifact lint passed (mode=$MODE scope=$LINT_SCOPE json_checked=$json_checked recon_validated=$recon_validated contract_review_validated=$contract_review_validated strict_markers_checked=$strict_markers_checked)"
exit 0
