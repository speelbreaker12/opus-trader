#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/crossref_gate.sh [--contract <path>] [--prd <path>] [--inputs <path|@list>] [--allowlist <path>] [--artifacts-dir <path>] [--ci] [--strict] [--fuzzy]

Runs fail-closed crossref gates:
  1) validate_crossref_invariants.py (spec + semantic invariants)
  2) check_contract_profiles.py (profile completeness)
  3) at_coverage_report.py (shared parser consumer)
  4) check_contract_profile_map_parity.py (exact map equality)
  5) roadmap_evidence_audit.py (marker-based evidence gating)

Exit codes propagate from underlying gates.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

contract="specs/CONTRACT.md"
prd="plans/prd.json"
inputs="@plans/evidence_sources.txt"
allowlist="plans/global_manual_allowlist.json"
artifacts_dir="${VERIFY_ARTIFACTS_DIR:-}"
ci=0
strict=0
fuzzy=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --contract)
      contract="${2:?missing value}"
      shift 2
      ;;
    --prd)
      prd="${2:?missing value}"
      shift 2
      ;;
    --inputs)
      inputs="${2:?missing value}"
      shift 2
      ;;
    --allowlist)
      allowlist="${2:?missing value}"
      shift 2
      ;;
    --artifacts-dir)
      artifacts_dir="${2:?missing value}"
      shift 2
      ;;
    --ci)
      ci=1
      shift
      ;;
    --strict)
      strict=1
      shift
      ;;
    --fuzzy)
      fuzzy=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown argument: $1"
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$repo_root"

if [[ -z "$artifacts_dir" ]]; then
  run_id="manual_$(date -u +%Y%m%dT%H%M%SZ)"
  artifacts_dir="$repo_root/artifacts/verify/$run_id"
fi

if [[ "$artifacts_dir" != /* ]]; then
  artifacts_dir="$repo_root/$artifacts_dir"
fi

crossref_dir="$artifacts_dir/crossref"
mkdir -p "$crossref_dir"

checker_map="$crossref_dir/contract_at_profile_map.json"
report_map="$crossref_dir/report_at_profile_map.json"
checker_summary="$crossref_dir/contract_profile_summary.json"
coverage_json="$crossref_dir/at_coverage_report.json"
coverage_md="$crossref_dir/at_coverage_report.md"
parity_json="$crossref_dir/at_profile_parity.json"
audit_json="$crossref_dir/roadmap_evidence_audit.json"
invariants_json="$crossref_dir/crossref_invariants.json"

python3 plans/validate_crossref_invariants.py > "$invariants_json"

python3 tools/ci/check_contract_profiles.py \
  --contract "$contract" \
  --emit-map "$checker_map" \
  --emit-summary "$checker_summary"

python3 tools/at_coverage_report.py \
  --contract "$contract" \
  --prd "$prd" \
  --emit-map "$report_map" \
  --output-json "$coverage_json" \
  --output-md "$coverage_md"

python3 tools/ci/check_contract_profile_map_parity.py \
  --checker-map "$checker_map" \
  --report-map "$report_map" \
  --out "$parity_json"

audit_cmd=(
  python3 tools/roadmap_evidence_audit.py
  --prd "$prd"
  --inputs "$inputs"
  --global-manual-allowlist "$allowlist"
  --output-json "$audit_json"
)

if [[ "$ci" == "1" ]]; then
  audit_cmd+=(--ci)
fi
if [[ "$strict" == "1" ]]; then
  audit_cmd+=(--strict)
fi
if [[ "$fuzzy" == "1" ]]; then
  audit_cmd+=(--fuzzy)
fi

"${audit_cmd[@]}"

echo "OK: crossref gate passed"
echo "  artifacts: $crossref_dir"
