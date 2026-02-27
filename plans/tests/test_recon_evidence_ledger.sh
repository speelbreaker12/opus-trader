#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_evidence_ledger.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans"
git -C "$tmp_dir" init -q repo
cp "$SCRIPT" "$repo/plans/recon_evidence_ledger.sh"
chmod +x "$repo/plans/recon_evidence_ledger.sh"

story_id="S9-999"
scaffold_path="$repo/reviews/reconciliations/S9/${story_id}_reconciliation.md"

(
  cd "$repo"
  plans/recon_evidence_ledger.sh "$story_id" --scaffold >/dev/null
)

[[ -f "$scaffold_path" ]] || fail "expected scaffold path to be created"

set +e
placeholder_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
placeholder_rc=$?
set -e
[[ "$placeholder_rc" -eq 1 ]] || fail "check should fail on scaffold placeholder content"
echo "$placeholder_out" | grep -Fq "scaffold placeholder content" || fail "missing placeholder failure diagnostic"

cat > "$scaffold_path" <<'EOF'
# S9-999 Reconciliation Evidence Ledger
Review basis: STORY_SCOPE (Cycle 1)
Story: S9-999
Status: PARTIAL

## AT Verdicts
| AT | Verdict | Enforcement | Test | Notes |
|----|---------|-------------|------|-------|
| AT-100 | PROVEN | file:10::enforce | file:30::test | evidence verified |
EOF

check_out="$(
  cd "$repo" && plans/recon_evidence_ledger.sh "$story_id" --check 2>&1
)"
echo "$check_out" | grep -Fq "OK: evidence ledger found" || fail "expected check mode success"

echo "test_recon_evidence_ledger.sh: ok"
