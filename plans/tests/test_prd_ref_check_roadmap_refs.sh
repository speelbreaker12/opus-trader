#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/plans/prd_ref_check.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fixture_rc() {
  local expected_rc="$1"
  local fixture_root="$2"
  local prd_path="$3"

  set +e
  (
    cd "$fixture_root"
    "$CHECKER" "$prd_path"
  ) >"$fixture_root/out.txt" 2>"$fixture_root/err.txt"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$fixture_root/out.txt" >&2 || true
    echo "stderr:" >&2
    cat "$fixture_root/err.txt" >&2 || true
    fail "expected rc=$expected_rc got rc=$rc in $fixture_root"
  fi
}

[[ -x "$CHECKER" ]] || fail "checker is not executable: $CHECKER"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

setup_fixture() {
  local fixture_root="$1"
  mkdir -p "$fixture_root/plans" "$fixture_root/specs" "$fixture_root/docs"

  cat > "$fixture_root/specs/CONTRACT.md" <<'EOF_CONTRACT'
# Contract
EOF_CONTRACT

  cat > "$fixture_root/specs/IMPLEMENTATION_PLAN.md" <<'EOF_PLAN'
# Implementation Plan
EOF_PLAN

  cat > "$fixture_root/docs/ROADMAP.md" <<'EOF_ROADMAP'
# Roadmap

## Phase 0

### P0-A Launch Policy Baseline
- owner policy evidence

### P0-B Launch Infra Baseline
- infra evidence
EOF_ROADMAP
}

valid_fixture="$tmp_dir/valid-roadmap"
setup_fixture "$valid_fixture"
cat > "$valid_fixture/plans/prd.json" <<'JSON'
{
  "items": [
    {
      "id": "S0-100",
      "category": "policy",
      "story_ref": "Policy roadmap fixture",
      "contract_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "plan_refs": ["P0-B Launch Infra Baseline"],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_fixture_rc 0 "$valid_fixture" "$valid_fixture/plans/prd.json"

missing_fixture="$tmp_dir/missing-roadmap"
setup_fixture "$missing_fixture"
cat > "$missing_fixture/plans/prd.json" <<'JSON'
{
  "items": [
    {
      "id": "S0-101",
      "category": "infra",
      "story_ref": "Missing roadmap fixture",
      "contract_refs": ["ROADMAP.md P0-Z Missing Launch Baseline"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_fixture_rc 1 "$missing_fixture" "$missing_fixture/plans/prd.json"
if ! grep -Fq "unresolved roadmap_ref for S0-101" "$missing_fixture/err.txt"; then
  echo "stderr:" >&2
  cat "$missing_fixture/err.txt" >&2 || true
  fail "missing unresolved roadmap_ref diagnostic"
fi

echo "PASS: prd_ref_check roadmap refs"
