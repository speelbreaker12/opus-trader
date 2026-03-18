#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_evidence_ledger.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"
command -v jq >/dev/null 2>&1 || fail "jq is required for this test"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans"
git -C "$tmp_dir" init -q repo
cp "$SCRIPT" "$repo/plans/recon_evidence_ledger.sh"
chmod +x "$repo/plans/recon_evidence_ledger.sh"

story_id="S9-999"
canonical_path="$repo/artifacts/story/${story_id}/evidence_ledger.json"
legacy_md_path="$repo/artifacts/story/${story_id}/evidence_ledger.md"

cat > "$repo/plans/prd.json" <<'EOF'
{
  "items": [
    {
      "id": "S9-999",
      "enforcing_contract_ats": ["AT-100"]
    }
  ]
}
EOF

(
  cd "$repo"
  plans/recon_evidence_ledger.sh "$story_id" --scaffold >/dev/null
)

[[ -f "$canonical_path" ]] || fail "expected canonical JSON scaffold path to be created"

set +e
placeholder_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
placeholder_rc=$?
set -e
[[ "$placeholder_rc" -eq 1 ]] || fail "check should fail on scaffold placeholder content"
echo "$placeholder_out" | grep -Fq "scaffold placeholder content" || fail "missing placeholder failure diagnostic"

cat > "$canonical_path" <<'EOF'
{
  "story_id": "S9-999",
  "path": "GREEN",
  "at_verdicts": [
    {
      "at_id": "AT-100",
      "verdict": "PROVEN",
      "enforcement": "plans/wf_step.sh:777",
      "test": ""
    }
  ]
}
EOF

set +e
citation_fail_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
citation_fail_rc=$?
set -e
[[ "$citation_fail_rc" -eq 1 ]] || fail "check should fail when PROVEN row has no test citation"
echo "$citation_fail_out" | grep -Fq "missing test file:line citation" || fail "missing citation failure diagnostic"

cat > "$canonical_path" <<'EOF'
{
  "story_id": "S9-999",
  "path": "GREEN",
  "at_verdicts": [
    {
      "at_id": "AT-100",
      "verdict": "PROVEN",
      "enforcement": "plans/wf_step.sh:777",
      "test": "plans/tests/test_wf_step.sh:120"
    }
  ]
}
EOF

check_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
echo "$check_out" | grep -Fq "OK: evidence ledger found" || fail "expected canonical JSON check success"

rm -f "$canonical_path"
cat > "$legacy_md_path" <<'EOF'
# S9-999 Reconciliation Evidence Ledger
Review basis: STORY_SCOPE (Cycle 1)
Story: S9-999
Status: PARTIAL

## AT Verdicts
| AT | Verdict | Enforcement | Test | Notes |
|----|---------|-------------|------|-------|
| AT-100 | PROVEN | plans/wf_step.sh:777 | plans/tests/test_wf_step.sh:120 | legacy evidence |
EOF

legacy_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
echo "$legacy_out" | grep -Fq "OK: evidence ledger found" || fail "expected legacy markdown check success"
echo "$legacy_out" | grep -Fq "WARN: using legacy markdown evidence ledger path" || fail "missing legacy fallback warning"

# Legacy evidence_ledger.v1 object-map payload should parse and normalize verdict values.
mkdir -p "$repo/crates/soldier_core/tests"
cat > "$repo/crates/soldier_core/tests/test_idempotency.rs" <<'EOF'
#[test]
fn test_at100_legacy_proving() {
    assert_eq!(1, 1);
}
EOF

cat > "$canonical_path" <<'EOF'
{
  "evidence_ledger": {
    "schema_version": "evidence_ledger.v1",
    "at_verdicts": {
      "AT-100": {
        "verdict": " proven ",
        "enforcement_file": "plans/recon_evidence_ledger.sh",
        "enforcement_line": 52,
        "proving_tests": [
          "crates/soldier_core/tests/test_idempotency.rs::test_at100_legacy_proving"
        ]
      }
    }
  }
}
EOF
rm -f "$legacy_md_path"

legacy_json_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
echo "$legacy_json_out" | grep -Fq "OK: evidence ledger found" || fail "expected evidence_ledger.v1 object-map compatibility pass"

# Unknown verdicts must fail closed even when citations are present.
cat > "$canonical_path" <<'EOF'
{
  "story_id": "S9-999",
  "path": "GREEN",
  "at_verdicts": [
    {
      "at_id": "AT-100",
      "verdict": "PROVEM",
      "enforcement": "plans/wf_step.sh:777",
      "test": "plans/tests/test_wf_step.sh:120"
    }
  ]
}
EOF

set +e
unknown_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
unknown_rc=$?
set -e
[[ "$unknown_rc" -eq 1 ]] || fail "expected unknown verdict to fail closed"
echo "$unknown_out" | grep -Fq "unknown verdict" || fail "missing unknown verdict diagnostic"

echo "test_recon_evidence_ledger.sh: ok"
