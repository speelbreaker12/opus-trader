#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/tools/ci/check_contract_profiles.py"
COVERAGE="$ROOT/tools/at_coverage_report.py"
PARITY="$ROOT/tools/ci/check_contract_profile_map_parity.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_rc() {
  local expected_rc="$1"
  shift

  set +e
  "$@" >/tmp/contract_profile_parity_test.out 2>/tmp/contract_profile_parity_test.err
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat /tmp/contract_profile_parity_test.out >&2 || true
    echo "stderr:" >&2
    cat /tmp/contract_profile_parity_test.err >&2 || true
    fail "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -f "$CHECKER" ]] || fail "missing checker script: $CHECKER"
[[ -f "$COVERAGE" ]] || fail "missing coverage script: $COVERAGE"
[[ -f "$PARITY" ]] || fail "missing parity script: $PARITY"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir" /tmp/contract_profile_parity_test.out /tmp/contract_profile_parity_test.err' EXIT

contract_ok="$tmp_dir/contract_ok.md"
prd_ok="$tmp_dir/prd_ok.json"
checker_map="$tmp_dir/checker_map.json"
report_map="$tmp_dir/report_map.json"
parity_report="$tmp_dir/parity_report.json"

cat > "$contract_ok" <<'EOF_CONTRACT_OK'
## Example
Profile: CSP
AT-001
AT-002 trailing description

Profile: GOP
AT-003
EOF_CONTRACT_OK

cat > "$prd_ok" <<'EOF_PRD_OK'
{
  "items": [
    {
      "id": "S-001",
      "contract_refs": ["AT-001", "AT-003"],
      "evidence": ["evidence/phase1/README.md"]
    }
  ]
}
EOF_PRD_OK

expect_rc 0 python3 "$CHECKER" --contract "$contract_ok" --emit-map "$checker_map"
expect_rc 0 python3 "$COVERAGE" --contract "$contract_ok" --prd "$prd_ok" --emit-map "$report_map"
expect_rc 0 python3 "$PARITY" --checker-map "$checker_map" --report-map "$report_map" --out "$parity_report"

[[ -f "$parity_report" ]] || fail "missing parity report"
grep -Fq '"parity_ok": true' "$parity_report" || fail "expected parity_ok=true"

# Introduce a mismatch and ensure parity gate returns 6.
cat > "$report_map" <<'EOF_BAD_REPORT_MAP'
{
  "AT-001": "CSP",
  "AT-002": "GOP",
  "AT-003": "GOP"
}
EOF_BAD_REPORT_MAP

expect_rc 6 python3 "$PARITY" --checker-map "$checker_map" --report-map "$report_map"

# Missing profile inheritance must fail checker with rc=5.
contract_bad="$tmp_dir/contract_bad.md"
cat > "$contract_bad" <<'EOF_CONTRACT_BAD'
AT-001
Profile: CSP
AT-002
EOF_CONTRACT_BAD

expect_rc 5 python3 "$CHECKER" --contract "$contract_bad"

echo "PASS: contract profile parity gate"
