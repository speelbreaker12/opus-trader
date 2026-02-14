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
  local out_file="$tmp_dir/expect_rc.out"
  local err_file="$tmp_dir/expect_rc.err"

  set +e
  "$@" >"$out_file" 2>"$err_file"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$out_file" >&2 || true
    echo "stderr:" >&2
    cat "$err_file" >&2 || true
    fail "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

expect_err_contains() {
  local needle="$1"
  if ! grep -Fq "$needle" "$tmp_dir/expect_rc.err"; then
    echo "stderr:" >&2
    cat "$tmp_dir/expect_rc.err" >&2 || true
    fail "expected stderr to contain: $needle"
  fi
}

[[ -f "$CHECKER" ]] || fail "missing checker script: $CHECKER"
[[ -f "$COVERAGE" ]] || fail "missing coverage script: $COVERAGE"
[[ -f "$PARITY" ]] || fail "missing parity script: $PARITY"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

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
expect_err_contains "has no Profile tag in scope"

# Malformed spacing must fail checker and coverage with rc=5.
contract_bad_spacing="$tmp_dir/bad_profile_spacing.md"
cat > "$contract_bad_spacing" <<'EOF_BAD_PROFILE_SPACING'
Profile : CSP
AT-001
EOF_BAD_PROFILE_SPACING

expect_rc 5 python3 "$CHECKER" --contract "$contract_bad_spacing"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"
expect_rc 5 python3 "$COVERAGE" --contract "$contract_bad_spacing" --prd "$prd_ok"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"


# Malformed profile after a valid scope must clear inheritance and report unscoped AT IDs.
contract_bad_rescope="$tmp_dir/bad_profile_rescope.md"
cat > "$contract_bad_rescope" <<'EOF_BAD_PROFILE_RESCOPE'
Profile: CSP
AT-001
Profile : GOP
AT-002
EOF_BAD_PROFILE_RESCOPE

expect_rc 5 python3 "$CHECKER" --contract "$contract_bad_rescope"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"
expect_err_contains "AT-002 has no Profile tag in scope"
expect_rc 5 python3 "$COVERAGE" --contract "$contract_bad_rescope" --prd "$prd_ok"
expect_err_contains "AT-002 has no Profile tag in scope"
# Malformed casing must fail checker and coverage with rc=5.
contract_bad_casing="$tmp_dir/bad_profile_casing.md"
cat > "$contract_bad_casing" <<'EOF_BAD_PROFILE_CASING'
profile: CSP
AT-001
EOF_BAD_PROFILE_CASING

expect_rc 5 python3 "$CHECKER" --contract "$contract_bad_casing"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"
expect_rc 5 python3 "$COVERAGE" --contract "$contract_bad_casing" --prd "$prd_ok"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"

# FULL is forbidden for AT tagging and must fail with rc=5.
contract_bad_full="$tmp_dir/bad_profile_full.md"
cat > "$contract_bad_full" <<'EOF_BAD_PROFILE_FULL'
Profile: FULL
AT-001
EOF_BAD_PROFILE_FULL

expect_rc 5 python3 "$CHECKER" --contract "$contract_bad_full"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"
expect_rc 5 python3 "$COVERAGE" --contract "$contract_bad_full" --prd "$prd_ok"
expect_err_contains "expected exactly one of: Profile: CSP | Profile: GOP"

# Profile-like strings inside fenced blocks are ignored.
contract_fence_backticks="$tmp_dir/profile_in_codeblock_backticks.md"
cat > "$contract_fence_backticks" <<'EOF_PROFILE_IN_CODEBLOCK_BACKTICKS'
```txt
profile: CSP
Profile : GOP
Profile: FULL
```

Profile: CSP
AT-001
EOF_PROFILE_IN_CODEBLOCK_BACKTICKS

expect_rc 0 python3 "$CHECKER" --contract "$contract_fence_backticks"
expect_rc 0 python3 "$COVERAGE" --contract "$contract_fence_backticks" --prd "$prd_ok"

contract_fence_tildes="$tmp_dir/profile_in_codeblock_tildes.md"
cat > "$contract_fence_tildes" <<'EOF_PROFILE_IN_CODEBLOCK_TILDES'
~~~txt
Profile: FULL
~~~

Profile: GOP
AT-003
EOF_PROFILE_IN_CODEBLOCK_TILDES

expect_rc 0 python3 "$CHECKER" --contract "$contract_fence_tildes"
expect_rc 0 python3 "$COVERAGE" --contract "$contract_fence_tildes" --prd "$prd_ok"

# Unterminated fenced blocks must fail closed with rc=5.
contract_unterminated_fence="$tmp_dir/unterminated_fence.md"
cat > "$contract_unterminated_fence" <<'EOF_UNTERMINATED_FENCE'
Profile: CSP
AT-001
```txt
Profile: GOP
AT-999
EOF_UNTERMINATED_FENCE

expect_rc 5 python3 "$CHECKER" --contract "$contract_unterminated_fence"
expect_err_contains "unterminated fenced block"
expect_rc 5 python3 "$COVERAGE" --contract "$contract_unterminated_fence" --prd "$prd_ok"
expect_err_contains "unterminated fenced block"

echo "PASS: contract profile parity gate"
