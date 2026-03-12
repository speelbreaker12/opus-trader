#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CHECKER="$ROOT/plans/prd_ref_check.sh"
SLICE_PREPARE="$ROOT/plans/prd_slice_prepare.sh"

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
[[ -x "$SLICE_PREPARE" ]] || fail "slice prepare is not executable: $SLICE_PREPARE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/specs" "$repo/docs" "$repo/docs/architecture"
cp "$CHECKER" "$repo/plans/prd_ref_check.sh"
chmod +x "$repo/plans/prd_ref_check.sh"
cp "$SLICE_PREPARE" "$repo/plans/prd_slice_prepare.sh"
chmod +x "$repo/plans/prd_slice_prepare.sh"

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

execution_prd="$repo/plans/execution_prd.json"
cat > "$execution_prd" <<'JSON'
{
  "items": [
    {
      "id": "EXE-001",
      "category": "execution",
      "story_ref": "Execution roadmap misuse",
      "contract_refs": ["ROADMAP.md P0-A Launch Policy Baseline"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 1 bash -lc "cd '$repo' && ./plans/prd_ref_check.sh '$execution_prd'"
grep -Eq "roadmap.*policy|infra|ROADMAP" "$tmp_dir/err.txt" \
  || fail "missing category restriction diagnostic for roadmap refs"

cat > "$repo/specs/CONTRACT.md" <<'EOF_CONTRACT_2'
# Contract

## 6. Implementation Roadmap v4.0
Important contract heading.
EOF_CONTRACT_2

contract_roadmap_word_prd="$repo/plans/contract_heading_prd.json"
cat > "$contract_roadmap_word_prd" <<'JSON'
{
  "items": [
    {
      "id": "EXE-002",
      "category": "execution",
      "story_ref": "Contract heading contains roadmap word",
      "contract_refs": ["6. Implementation Roadmap v4.0"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "enforcing_contract_ats": []
    }
  ]
}
JSON

expect_rc 0 bash -lc "cd '$repo' && ./plans/prd_ref_check.sh '$contract_roadmap_word_prd'"

cat > "$repo/.context_contract_digest.json" <<'JSON'
{
  "source_path": "specs/CONTRACT.md",
  "source_sha256": "contract",
  "anchors": {},
  "sections": []
}
JSON

cat > "$repo/.context_plan_digest.json" <<'JSON'
{
  "source_path": "specs/IMPLEMENTATION_PLAN.md",
  "source_sha256": "plan",
  "anchors": {},
  "sections": []
}
JSON

cat > "$repo/.context_roadmap_digest.json" <<'JSON'
{
  "source_path": "docs/ROADMAP.md",
  "source_sha256": "roadmap",
  "anchors": {},
  "sections": [
    {
      "id": "P0-A",
      "title": "Launch Policy Baseline",
      "text": ""
    }
  ]
}
JSON

slice_prd="$repo/plans/slice_prd.json"
cat > "$slice_prd" <<'JSON'
{
  "project": "Fixture",
  "source": {},
  "rules": {},
  "items": [
    {
      "id": "S0-000",
      "slice": 0,
      "story_ref": "P0-A Launch Policy Baseline",
      "category": "policy",
      "contract_refs": ["P0-A Launch Policy Baseline"],
      "plan_refs": [],
      "acceptance": [],
      "verify": [],
      "dependencies": []
    }
  ]
}
JSON

expect_rc 0 bash -lc "cd '$repo' && PRD_FILE='$slice_prd' PRD_SLICE=0 CONTRACT_DIGEST='$repo/.context_contract_digest.json' PLAN_DIGEST='$repo/.context_plan_digest.json' ROADMAP_DIGEST='$repo/.context_roadmap_digest.json' OUT_PRD_SLICE='$repo/.context_prd_slice.json' OUT_CONTRACT_DIGEST='$repo/.context_contract_slice.json' OUT_PLAN_DIGEST='$repo/.context_plan_slice.json' OUT_ROADMAP_DIGEST='$repo/.context_roadmap_slice.json' OUT_AUDIT_FILE='$repo/plans/prd_audit.json' OUT_META='$repo/.context_meta.json' ./plans/prd_slice_prepare.sh"
[[ "$(jq '.sections | length' "$repo/.context_roadmap_slice.json")" == "1" ]] \
  || fail "implicit roadmap anchor should survive slice preparation"

echo "PASS: prd_ref_check roadmap refs"
