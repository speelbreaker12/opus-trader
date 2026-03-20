#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF_STEP="$ROOT/plans/wf_step.sh"
RECON_PRECHECK="$ROOT/plans/recon_precheck.sh"
HASH_UTILS="$ROOT/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$WF_STEP" ]] || fail "missing script: $WF_STEP"
[[ -f "$RECON_PRECHECK" ]] || fail "missing script: $RECON_PRECHECK"
[[ -f "$HASH_UTILS" ]] || fail "missing helper: $HASH_UTILS"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"
git init -q
git config core.hooksPath /dev/null
git config user.email "test@example.com"
git config user.name "Test"

mkdir -p plans plans/lib artifacts/story/S3-000/self_review artifacts/story/S3-000/codex artifacts/verify/run_001
cp "$WF_STEP" plans/wf_step.sh
cp "$RECON_PRECHECK" plans/recon_precheck.sh
cp "$HASH_UTILS" plans/lib/hash_utils.sh
chmod +x plans/wf_step.sh plans/recon_precheck.sh

echo "seed" > seed.txt
git add -A
git commit -q -m "seed"

cat > plans/prd.json <<'EOF'
{
  "items": [
    { "id": "S3-000", "passes": true, "scope": { "touches": ["seed.txt"] }, "primary_owner_for": ["AT-004"] },
    { "id": "S3-002", "passes": true, "scope": { "touches": ["seed.txt"] }, "primary_owner_for": ["AT-005"] }
  ]
}
EOF

set +e
bad_combo_out="$(WF_RECON_MODE=1 bash plans/wf_step.sh S3-000 preflight --stop-on-blocker 2>&1)"
bad_combo_rc=$?
set -e
[[ "$bad_combo_rc" -eq 2 ]] || fail "expected --stop-on-blocker without --run-sequence to fail with exit 2, got $bad_combo_rc"
echo "$bad_combo_out" | grep -q "requires --run-sequence" || fail "missing bad combination error"

set +e
stop_out="$(WF_RECON_MODE=1 bash plans/wf_step.sh S3-000 --run-sequence --stop-on-blocker 2>&1)"
stop_rc=$?
set -e
[[ "$stop_rc" -eq 3 ]] || fail "expected stop-on-blocker run to exit 3, got $stop_rc"
echo "$stop_out" | grep -q "halted at step 'preflight'" || fail "missing halt message for stop-on-blocker"
echo "$stop_out" | grep -q "running step 'implement'" && fail "should not continue past preflight under stop-on-blocker"

receipt_dir="$tmp_dir/.wf/receipts/S3-000"
count_stop="$(find "$receipt_dir" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
[[ "$count_stop" == "0" ]] || fail "no receipts should be written when preflight blocks immediately"

set +e
nostop_out="$(WF_RECON_MODE=1 bash plans/wf_step.sh S3-000 --run-sequence 2>&1)"
nostop_rc=$?
set -e
[[ "$nostop_rc" -ne 0 ]] || fail "expected non-zero without stop-on-blocker when preflight blocks"
echo "$nostop_out" | grep -q "running step 'pass'" || fail "expected sequence mode without stop to continue through pass"

echo "test_wf_step_stop_on_blocker.sh: ok"
