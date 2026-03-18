#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/crossref_burnin_check.sh \
    --clean-merge-count <n> \
    --unexplained-drift-count <n> \
    --unknown-gap-count <n> \
    [--min-clean-merges <n>] \
    [--max-unexplained-drift <n>] \
    [--max-unknown-gaps <n>] \
    [--out <path>]

Returns 0 when burn-in promotion criteria are met, else 1.
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 2
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"
}

need jq

clean_merges=""
unexplained_drift=""
unknown_gaps=""
min_clean=2
max_drift=0
max_unknown=0
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --clean-merge-count)
      clean_merges="${2:?missing value}"
      shift 2
      ;;
    --unexplained-drift-count)
      unexplained_drift="${2:?missing value}"
      shift 2
      ;;
    --unknown-gap-count)
      unknown_gaps="${2:?missing value}"
      shift 2
      ;;
    --min-clean-merges)
      min_clean="${2:?missing value}"
      shift 2
      ;;
    --max-unexplained-drift)
      max_drift="${2:?missing value}"
      shift 2
      ;;
    --max-unknown-gaps)
      max_unknown="${2:?missing value}"
      shift 2
      ;;
    --out)
      out="${2:?missing value}"
      shift 2
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

for name in clean_merges unexplained_drift unknown_gaps min_clean max_drift max_unknown; do
  value="${!name}"
  [[ -n "$value" ]] || die "missing required numeric arg: $name"
  [[ "$value" =~ ^[0-9]+$ ]] || die "invalid numeric value for $name: $value"
done

eligible=1
reasons=()

if (( clean_merges < min_clean )); then
  eligible=0
  reasons+=("clean_merge_count<$min_clean")
fi
if (( unexplained_drift > max_drift )); then
  eligible=0
  reasons+=("unexplained_drift_count>$max_drift")
fi
if (( unknown_gaps > max_unknown )); then
  eligible=0
  reasons+=("unknown_gap_count>$max_unknown")
fi

if [[ -n "$out" ]]; then
  out_path="$out"
  if [[ "$out_path" != /* ]]; then
    out_path="$(pwd)/$out_path"
  fi
  mkdir -p "$(dirname "$out_path")"

  reasons_json="[]"
  if ((${#reasons[@]} > 0)); then
    reasons_json="$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)"
  fi

  jq -n \
    --argjson clean_merge_count "$clean_merges" \
    --argjson unexplained_drift_count "$unexplained_drift" \
    --argjson unknown_gap_count "$unknown_gaps" \
    --argjson min_clean_merges "$min_clean" \
    --argjson max_unexplained_drift "$max_drift" \
    --argjson max_unknown_gaps "$max_unknown" \
    --argjson eligible "$eligible" \
    --argjson reasons "$reasons_json" \
    '{
      clean_merge_count: $clean_merge_count,
      unexplained_drift_count: $unexplained_drift_count,
      unknown_gap_count: $unknown_gap_count,
      thresholds: {
        min_clean_merges: $min_clean_merges,
        max_unexplained_drift: $max_unexplained_drift,
        max_unknown_gaps: $max_unknown_gaps
      },
      eligible: ($eligible == 1),
      reasons: $reasons
    }' > "$out_path"
fi

if (( eligible == 1 )); then
  echo "OK: burn-in promotion eligible"
  exit 0
fi

echo "FAIL: burn-in promotion ineligible (${reasons[*]})" >&2
exit 1
