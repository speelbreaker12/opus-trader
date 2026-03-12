#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/plans/prd_ref_check.sh"

die() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_rc() {
  local expected_rc="$1"
  shift

  set +e
  "$@" >"$tmp_dir/out.txt" 2>"$tmp_dir/err.txt"
  local rc=$?
  set -e

  if [[ "$rc" -ne "$expected_rc" ]]; then
    echo "stdout:" >&2
    cat "$tmp_dir/out.txt" >&2 || true
    echo "stderr:" >&2
    cat "$tmp_dir/err.txt" >&2 || true
    die "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -x "$CHECKER" ]] || die "checker is not executable: $CHECKER"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_repo="$tmp_dir/repo"
mkdir -p "$fixture_repo/specs" "$fixture_repo/docs" "$fixture_repo/docs/architecture"

cat > "$fixture_repo/specs/CONTRACT.md" <<'EOF_CONTRACT'
# Contract

## Policy Guard
EOF_CONTRACT

cat > "$fixture_repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF_PLAN'
# Implementation Plan

## Phase 0
EOF_PLAN

cat > "$fixture_repo/docs/architecture/contract_anchors.md" <<'EOF_ANCHORS'
# Contract Anchors
EOF_ANCHORS

cat > "$fixture_repo/docs/ROADMAP.md" <<'EOF_ROADMAP'
# ROADMAP

## P0-A Launch Policy Baseline
- Capture launch policy evidence.
EOF_ROADMAP

valid_prd="$fixture_repo/valid_prd.json"
cat > "$valid_prd" <<'JSON'
{
  "items": [
    {
      "id": "S0-200",
      "category": "policy",
      "story_ref": "Policy roadmap guard",
      "contract_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 0 bash -c "cd '$fixture_repo' && '$CHECKER' '$valid_prd'"

missing_prd="$fixture_repo/missing_prd.json"
cat > "$missing_prd" <<'JSON'
{
  "items": [
    {
      "id": "S0-201",
      "category": "infra",
      "story_ref": "Missing roadmap guard",
      "contract_refs": ["ROADMAP.md P0-Z Missing Policy Anchor"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 1 bash -c "cd '$fixture_repo' && '$CHECKER' '$missing_prd'"
if ! grep -Fq "unresolved roadmap_ref for S0-201" "$tmp_dir/err.txt"; then
  echo "stderr:" >&2
  cat "$tmp_dir/err.txt" >&2 || true
  die "missing unresolved roadmap_ref diagnostic"
fi

echo "PASS: prd_ref_check roadmap refs"
