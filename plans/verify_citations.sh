#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: plans/verify_citations.sh --artifact <path> --mode C1 --json

Wrapper around plans/validators/validate_review_header.py that enforces preexisting
citation checks for cycle-1 cycle reviews.

Contract:
  - Exit 0: PASS
  - Exit 1: citation/validation check failures
  - Exit 2: invalid input or schema/usage failure
  - Exit 3: infrastructure/IO failure
  - Output: JSON with keys `validator`, `status`, `artifact`, `failure_codes`

Arguments:
  --artifact PATH   Review artifact path (required)
  --mode {C1,C2}   Review cycle (default: C1)
  --json            Emit JSON result (required by contract)
  -h, --help        Show this message
USAGE
}

artifact=""
mode="C1"
json_mode=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --artifact)
      artifact="${2:?missing artifact path}"
      shift 2
      ;;
    --mode)
      mode="${2:?missing mode}"
      shift 2
      ;;
    --json)
      json_mode=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "verify_citations.sh: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$artifact" ]]; then
  echo 'verify_citations.sh: --artifact is required' >&2
  usage >&2
  exit 2
fi

if [[ "$mode" != "C1" && "$mode" != "C2" ]]; then
  echo "verify_citations.sh: --mode must be C1 or C2, got '$mode'" >&2
  usage >&2
  exit 2
fi

if [[ "$json_mode" -ne 1 ]]; then
  echo "verify_citations.sh: --json must be provided by contract" >&2
  exit 2
fi

validator="$(dirname "$0")/validators/validate_review_header.py"
if [[ ! -f "$validator" ]]; then
  echo "verify_citations.sh: validator script not found: $validator" >&2
  exit 3
fi

# Always request JSON from the underlying validator for deterministic contract output.
out=$({
  python3 "$validator" \
    --artifact "$artifact" \
    --expect-cycle "$mode" \
    --fmt json \
    --require-preexisting-citations \
    --strict
} 2>&1)
status=$?

# Parse validator status and failure codes when present.
parse_status() {
  printf '%s' "$1" | python3 -c 'import sys, json; print(json.loads(sys.stdin.read()).get("status"))' 2>/dev/null || true
}

parse_failures() {
  printf '%s' "$1" | python3 -c 'import sys, json; d=json.loads(sys.stdin.read()); print(" ".join(d.get("failure_codes", [])))' 2>/dev/null || true
}

validator_status=""
if [[ "$status" -eq 0 ]]; then
  validator_status="PASS"
else
  validator_status="$(parse_status "$out")"
  [[ -z "$validator_status" ]] && validator_status="FAIL"
fi

if [[ "$status" -eq 0 ]]; then
  echo '{'
  echo "  \"validator\": \"review-header-citations\"," 
  echo "  \"status\": \"PASS\"," 
  echo "  \"artifact\": \"$artifact\"," 
  echo '  "failure_codes": []'
  echo '}'
  exit 0
fi

# Non-zero from validator: map to wrapper exit code + normalized JSON
case "$status" in
  4)
    mapped=1
    ;;
  1)
    mapped=2
    ;;
  2|3)
    mapped=2
    ;;
  5)
    mapped=3
    ;;
  *)
    mapped=3
    ;;
esac

code_list="$(parse_failures "$out")"
if [[ -z "$code_list" ]]; then
  code_list="[$(if [[ "$mode" == "C1" ]]; then echo '"CITATION_VALIDATION_FAIL"'; else echo '"VALIDATION_FAIL"'; fi)]"
else
  code_list="[$(echo "$code_list" | sed -E 's/[[:space:]]+/", \"/g' | sed -E 's/^/"/;s/$/"/')]"
fi

echo '{'
echo "  \"validator\": \"review-header-citations\"," 
echo "  \"status\": \"FAIL\"," 
echo "  \"artifact\": \"$artifact\"," 
echo "  \"failure_codes\": $code_list"
echo '}'
exit "$mapped"
