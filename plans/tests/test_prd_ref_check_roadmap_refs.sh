#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/plans/prd_ref_check.sh"

fail() {
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
    fail "expected rc=$expected_rc got rc=$rc for: $*"
  fi
}

[[ -x "$CHECKER" ]] || fail "checker is not executable: $CHECKER"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/specs" "$repo/docs" "$repo/docs/architecture"
cp "$CHECKER" "$repo/plans/prd_ref_check.sh"
chmod +x "$repo/plans/prd_ref_check.sh"

cat > "$repo/specs/CONTRACT.md" <<'EOF_CONTRACT'
# Contract

## General Rule
All items must resolve their references.
EOF_CONTRACT

cat > "$repo/specs/IMPLEMENTATION_PLAN.md" <<'EOF_PLAN'
# Implementation Plan

## Phase 0
Launch sequencing.
EOF_PLAN

cat > "$repo/docs/architecture/contract_anchors.md" <<'EOF_ANCHORS'
# Contract Anchors
EOF_ANCHORS

cat > "$repo/docs/ROADMAP.md" <<'EOF_ROADMAP'
# ROADMAP

## P0-A Launch Policy Baseline
Owner docs and drills.
EOF_ROADMAP

valid_prd="$repo/plans/valid_prd.json"
cat > "$valid_prd" <<'JSON'
{
  "items": [
    {
      "id": "INF-001",
      "category": "infra",
      "story_ref": "Infra roadmap stub",
      "contract_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 0 bash -lc "cd '$repo' && ./plans/prd_ref_check.sh '$valid_prd'"

missing_prd="$repo/plans/missing_prd.json"
cat > "$missing_prd" <<'JSON'
{
  "items": [
    {
      "id": "INF-002",
      "category": "policy",
      "story_ref": "Policy roadmap stub",
      "contract_refs": ["ROADMAP.md P0-B Missing Anchor"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 1 bash -lc "cd '$repo' && ./plans/prd_ref_check.sh '$missing_prd'"
grep -Fq "unresolved roadmap_ref for INF-002" "$tmp_dir/err.txt" \
  || fail "missing roadmap-specific unresolved ref diagnostic"

echo "PASS: prd_ref_check roadmap refs"
