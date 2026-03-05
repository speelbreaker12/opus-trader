#!/usr/bin/env bash
set -euo pipefail

# Tests for plans/wf_step.sh progress tracker.
#
# Runs in a temporary git repo to isolate from real repo state.

PASS=0
FAIL=0
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WF_STEP="$(cd "$SCRIPT_DIR/.." && pwd)/wf_step.sh"
RECON_PRECHECK="$(cd "$SCRIPT_DIR/.." && pwd)/recon_precheck.sh"
HASH_UTILS="$(cd "$SCRIPT_DIR/.." && pwd)/lib/hash_utils.sh"

assert_exit() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$actual" -eq "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected exit=$expected, got exit=$actual)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_exists() {
  local label="$1" path="$2"
  if [[ -f "$path" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (file not found: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -f "$path" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (file should not exist: $path)"
    FAIL=$((FAIL + 1))
  fi
}

assert_json_field() {
  local label="$1" file="$2" field="$3" expected="$4"
  local actual
  actual="$(jq -r "$field" "$file" 2>/dev/null || echo 'ERROR')"
  if [[ "$actual" == "$expected" ]]; then
    echo "PASS: $label"
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label (expected $field=$expected, got $actual)"
    FAIL=$((FAIL + 1))
  fi
}

write_cycle2_sidecar() {
  local artifact="$1"
  local sidecar="${artifact%.md}.sidecar.json"
cat > "$sidecar" <<'EOF'
{
  "phase_equivalent": "R7d",
  "review_basis": "FIX_DIFF + AT_REGRESSION (Cycle 2)"
}
EOF
}

# ── Setup temp git repo ─────────────────────────────────────────────

TMPDIR="$(mktemp -d)"
cleanup() { rm -rf "$TMPDIR"; }
trap cleanup EXIT

cd "$TMPDIR"
git init -q
git config user.email "test@test.com"
git config user.name "Test"

# Create minimal structure
mkdir -p plans plans/lib artifacts/story/TEST-001/self_review
mkdir -p artifacts/story/TEST-001/codex
mkdir -p artifacts/story/TEST-001/opus
mkdir -p artifacts/story/TEST-001/preflight
mkdir -p artifacts/verify/run_001

# Seed minimal PRD scope so preflight scope-lock can succeed.
cat > plans/prd.json <<'PRD'
{
  "items": [
    {
      "id": "TEST-001",
      "scope": {
        "allow": [
          "feature.rs"
        ]
      }
    }
  ]
}
PRD

# Copy wf_step.sh into this repo
cp "$WF_STEP" plans/wf_step.sh
cp "$RECON_PRECHECK" plans/recon_precheck.sh
cp "$HASH_UTILS" plans/lib/hash_utils.sh
chmod +x plans/wf_step.sh
chmod +x plans/recon_precheck.sh

# This suite focuses on step ordering/state transitions, not sidecar/citation gates.
# Keep those gates covered in dedicated provenance tests.
awk '
  /^case "\$STEP" in$/ {
    print ""
    print "# test shim: sequencing-only suite bypasses provenance-specific gates"
    print "check_review_logged_sidecar_patch() { return 0; }"
    print "verify_review_artifact_provenance() { return 0; }"
    print "verify_cycle1_citations() { return 0; }"
  }
  { print }
' plans/wf_step.sh > plans/wf_step.sh.tmp
mv plans/wf_step.sh.tmp plans/wf_step.sh
chmod +x plans/wf_step.sh

# Legacy preflight fallback evidence for cycle1 readiness in isolated fixture repo.
cat > artifacts/story/TEST-001/preflight/audit.md <<'EOF'
# preflight ledger fixture
EOF

# Initial commit
echo "initial" > src.rs
git add -A && git commit -q -m "initial"

HEAD="$(git rev-parse HEAD)"
RECEIPT_DIR="$TMPDIR/.wf/receipts/TEST-001"

echo "=== PART 1: Step ordering enforcement ==="

# ── Test 1: Can run preflight (first step, no prereqs) ──────────────
echo "--- Test 1: Preflight runs without prereqs ---"
set +e
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
rc=$?
set -e
assert_exit "preflight succeeds" 0 "$rc"
assert_file_exists "preflight receipt created" "$RECEIPT_DIR/00_preflight.json"

# ── Test 2: Skip to cycle1 blocked (missing implement, self_review) ─
echo "--- Test 2: Skip to cycle1 blocked ---"
set +e
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
rc=$?
set -e
assert_exit "skip to cycle1 blocked" 1 "$rc"

# ── Test 3: Skip to verify_full blocked ─────────────────────────────
echo "--- Test 3: Skip to verify_full blocked ---"
set +e
bash plans/wf_step.sh TEST-001 verify_full > /dev/null 2>&1
rc=$?
set -e
assert_exit "skip to verify_full blocked" 1 "$rc"

echo ""
echo "=== PART 2: Full chain build ==="

# ── Test 4: Build full chain step by step ────────────────────────────
echo "--- Test 4: Build full chain ---"

# implement — needs code change
echo "feature code" > feature.rs
git add feature.rs && git commit -q -m "implement feature"

set +e; bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1; rc=$?; set -e
assert_exit "implement succeeds" 0 "$rc"

# self_review — needs artifact
echo "Story: TEST-001
HEAD: $(git rev-parse HEAD)
Decision: PASS
- Failure-Mode Review: DONE
- Strategic Failure Review: DONE" > artifacts/story/TEST-001/self_review/20260219_self_review.md

set +e; bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1; rc=$?; set -e
assert_exit "self_review succeeds" 0 "$rc"

# cycle1 — needs review artifact
cat > artifacts/story/TEST-001/codex/20260219_001_review.md <<CYCLE1
- HEAD: $(git rev-parse HEAD)
- Command Exit Code: 0
- Duration Seconds: 30

<<<REVIEW_TRANSCRIPT_BEGIN>>>
## P1 - High
- **feature.rs:1** Missing error handling
<<<REVIEW_TRANSCRIPT_END>>>
CYCLE1

set +e; bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1; rc=$?; set -e
assert_exit "cycle1 succeeds" 0 "$rc"

# fix — needs code change since cycle1
echo "fixed feature code" > feature.rs
git add feature.rs && git commit -q -m "fix review findings"

set +e; bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1; rc=$?; set -e
assert_exit "fix succeeds" 0 "$rc"

# cycle2 — needs second review artifact
cat > artifacts/story/TEST-001/codex/20260219_002_review.md <<CYCLE2
- HEAD: $(git rev-parse HEAD)
- Command Exit Code: 0
- Duration Seconds: 25

<<<REVIEW_TRANSCRIPT_BEGIN>>>
All findings addressed. No new P0/P1.
<<<REVIEW_TRANSCRIPT_END>>>
CYCLE2
write_cycle2_sidecar "artifacts/story/TEST-001/codex/20260219_002_review.md"

set +e; bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1; rc=$?; set -e
assert_exit "cycle2 succeeds" 0 "$rc"

# resolution — needs resolution file
cat > artifacts/story/TEST-001/review_resolution.md <<RES
Story: TEST-001
HEAD: $(git rev-parse HEAD)
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
RES

set +e; bash plans/wf_step.sh TEST-001 resolution > /dev/null 2>&1; rc=$?; set -e
assert_exit "resolution succeeds" 0 "$rc"

# verify_full — needs verify artifacts
VERIFY_HEAD="$(git rev-parse HEAD)"
cat > artifacts/verify/run_001/verify.meta.json <<META
{
  "mode": "full",
  "head_sha": "$VERIFY_HEAD",
  "timestamp": "2026-02-19T16:00:00Z",
  "exit_code": 0
}
META
echo "0" > artifacts/verify/run_001/gate_01.rc

set +e; bash plans/wf_step.sh TEST-001 verify_full > /dev/null 2>&1; rc=$?; set -e
assert_exit "verify_full succeeds" 0 "$rc"

# pass — validates all 8 receipts exist
set +e; bash plans/wf_step.sh TEST-001 pass > /dev/null 2>&1; rc=$?; set -e
assert_exit "pass validation succeeds" 0 "$rc"

echo ""
echo "=== PART 3: Receipt format ==="

# ── Test 5: Receipt has expected fields ──────────────────────────────
echo "--- Test 5: Receipt format ---"
assert_json_field "receipt has story_id" "$RECEIPT_DIR/00_preflight.json" ".story_id" "TEST-001"
assert_json_field "receipt has step_name" "$RECEIPT_DIR/00_preflight.json" ".step_name" "preflight"
assert_json_field "receipt has step_index" "$RECEIPT_DIR/00_preflight.json" ".step_index" "0"

# Verify receipt has head_sha and timestamp_utc
head_val="$(jq -r '.head_sha // ""' "$RECEIPT_DIR/00_preflight.json")"
ts_val="$(jq -r '.timestamp_utc // ""' "$RECEIPT_DIR/00_preflight.json")"
if [[ -n "$head_val" && -n "$ts_val" ]]; then
  echo "PASS: receipt has head_sha and timestamp_utc"
  PASS=$((PASS + 1))
else
  echo "FAIL: receipt missing head_sha or timestamp_utc"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== PART 4: Status and reset ==="

# ── Test 6: Status mode shows chain ────────────────────────────────
echo "--- Test 6: Status mode ---"
set +e
output="$(bash plans/wf_step.sh TEST-001 --status 2>&1)"
rc=$?
set -e
assert_exit "status mode works" 0 "$rc"
if echo "$output" | grep -q '\[DONE\].*preflight'; then
  echo "PASS: status shows preflight"
  PASS=$((PASS + 1))
else
  echo "FAIL: status doesn't show preflight"
  FAIL=$((FAIL + 1))
fi

# ── Test 6b: Reset without --yes blocked ──────────────────────────
echo "--- Test 6b: Reset requires --yes ---"
set +e
bash plans/wf_step.sh TEST-001 --reset > /dev/null 2>&1
rc=$?
set -e
assert_exit "reset without --yes blocked" 2 "$rc"

# ── Test 7: Reset clears all receipts ──────────────────────────────
echo "--- Test 7: Reset mode ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
count="$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
if [[ "$count" -eq 0 ]]; then
  echo "PASS: reset cleared all receipts"
  PASS=$((PASS + 1))
else
  echo "FAIL: reset left $count receipts"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== PART 5: Input validation ==="

# ── Test 8: self_review without artifacts fails ─────────────────────
echo "--- Test 8: self_review without artifacts ---"
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
echo "test8 code" > test8.rs
git add test8.rs && git commit -q -m "test8 code change"
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
# Remove self_review artifacts
rm -rf artifacts/story/TEST-001/self_review
mkdir -p artifacts/story/TEST-001/self_review

set +e
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1
rc=$?
set -e
assert_exit "self_review without artifacts blocked" 3 "$rc"

# Restore
echo "Story: TEST-001
Decision: PASS
- Failure-Mode Review: DONE" > artifacts/story/TEST-001/self_review/review.md

# ── Test 9: resolution without required fields fails ───────────────
echo "--- Test 9: resolution without required fields ---"
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
echo "more fixes" >> feature.rs
git add feature.rs && git commit -q -m "more fixes"
bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1

# Write incomplete resolution
echo "Story: TEST-001
Blocking addressed: NO" > artifacts/story/TEST-001/review_resolution.md

set +e
bash plans/wf_step.sh TEST-001 resolution > /dev/null 2>&1
rc=$?
set -e
assert_exit "incomplete resolution blocked" 3 "$rc"

# ── Test 10: verify_full with wrong mode fails ──────────────────────
echo "--- Test 10: verify_full with wrong mode ---"
cat > artifacts/story/TEST-001/review_resolution.md <<RES2
Story: TEST-001
Blocking addressed: YES
Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
RES2
bash plans/wf_step.sh TEST-001 resolution > /dev/null 2>&1

cat > artifacts/verify/run_001/verify.meta.json <<QMETA
{
  "mode": "quick",
  "head_sha": "$(git rev-parse HEAD)",
  "exit_code": 0
}
QMETA

set +e
bash plans/wf_step.sh TEST-001 verify_full > /dev/null 2>&1
rc=$?
set -e
assert_exit "verify quick mode blocked" 3 "$rc"

# ── Test 11: verify_full with HEAD mismatch fails ───────────────────
echo "--- Test 11: verify_full HEAD mismatch ---"
cat > artifacts/verify/run_001/verify.meta.json <<HMETA
{
  "mode": "full",
  "head_sha": "0000000000000000000000000000000000000000",
  "exit_code": 0
}
HMETA

set +e
bash plans/wf_step.sh TEST-001 verify_full > /dev/null 2>&1
rc=$?
set -e
assert_exit "verify HEAD mismatch blocked" 5 "$rc"

# ── Test 12: Dry run doesn't write receipt ──────────────────────────
echo "--- Test 12: Dry run ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
set +e
bash plans/wf_step.sh TEST-001 preflight --dry-run > /dev/null 2>&1
rc=$?
set -e
assert_exit "dry run succeeds" 0 "$rc"
assert_file_absent "dry run no receipt" "$RECEIPT_DIR/00_preflight.json"

echo ""
echo "=== PART 6: Perfect cycle 1 bypass ==="

# ── Test 13: Fix step passes with 0 findings ────────────────────────
echo "--- Test 13: Perfect cycle 1 allows empty fix ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
echo "perfect feature" > feature.rs
git add feature.rs && git commit -q -m "perfect implementation"
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Story: TEST-001
Decision: PASS
- Failure-Mode Review: DONE" > artifacts/story/TEST-001/self_review/review.md
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1

rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
cat > artifacts/story/TEST-001/codex/20260219_perfect_review.md <<PERFECT
- HEAD: $(git rev-parse HEAD)
- Command Exit Code: 0
- Duration Seconds: 45

<<<REVIEW_TRANSCRIPT_BEGIN>>>
Excellent implementation. 0 findings. No issues detected.
<<<REVIEW_TRANSCRIPT_END>>>
PERFECT
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1

# Fix step should pass WITHOUT code changes (0 findings)
set +e
bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1
rc=$?
set -e
assert_exit "fix passes with perfect cycle1" 0 "$rc"

echo ""
echo "=== PART 7: Backward compatibility ==="

# ── Test 14: Old receipts with extra fields are ignored ──────────────
echo "--- Test 14: Old receipts with extra fields ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
# Write a receipt with old-style fields (prev_receipt_hash, tainted, hmac)
mkdir -p "$RECEIPT_DIR"
cat > "$RECEIPT_DIR/00_preflight.json" <<OLDFMT
{
  "story_id": "TEST-001",
  "step_name": "preflight",
  "step_index": 0,
  "head_sha": "$(git rev-parse HEAD)",
  "timestamp_utc": "2026-02-19T15:00:00Z",
  "prev_receipt_hash": "GENESIS",
  "tainted": false,
  "inputs_hash": "abc123",
  "receipt_hash": "def456",
  "signature": "hmac789"
}
OLDFMT

# Status should still work (ignores unknown fields)
set +e
output="$(bash plans/wf_step.sh TEST-001 --status 2>&1)"
rc=$?
set -e
assert_exit "status works with old-format receipt" 0 "$rc"
if echo "$output" | grep -q '\[DONE\].*preflight'; then
  echo "PASS: old-format receipt shown in status"
  PASS=$((PASS + 1))
else
  echo "FAIL: old-format receipt not shown"
  FAIL=$((FAIL + 1))
fi

echo ""
echo "=== PART 8: Reconciliation mode ==="

mkdir -p reviews/premortems
cat > reviews/premortems/TEST-001_premortem.md <<'EOF'
# TEST-001 premortem
Prior Postmortem: NONE
Reused Guardrail: NONE
EOF
cat > reviews/premortems/TEST-002_premortem.md <<'EOF'
# TEST-002 premortem
Prior Postmortem: NONE
Reused Guardrail: NONE
EOF

# ── Test 15: Invalid WF_RECON_MODE rejected ──────────────────────────
echo "--- Test 15: Invalid WF_RECON_MODE rejected ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
set +e
WF_RECON_MODE=banana bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
rc=$?
set -e
assert_exit "invalid WF_RECON_MODE rejected" 2 "$rc"

# ── Test 16: Recon mode: implement passes without code change ────────
echo "--- Test 16: Recon implement bypasses diff check ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1

# Create a PRD file with passes=true for TEST-001
mkdir -p plans
cat > plans/prd.json <<PRDEOF
{
  "items": [
    {
      "id": "TEST-001",
      "passes": true,
      "scope": { "allow": ["feature.rs"] }
    }
  ]
}
PRDEOF

set +e
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
rc=$?
set -e
assert_exit "recon preflight succeeds" 0 "$rc"

# No code change, but recon mode should bypass
set +e
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
rc=$?
set -e
assert_exit "recon implement passes without code change" 0 "$rc"

# ── Test 17: Normal mode implement still requires code change ────────
echo "--- Test 17: Normal implement still requires code change ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
set +e
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
rc=$?
set -e
assert_exit "normal implement blocked without code change" 3 "$rc"

# ── Test 18: Recon receipt contains recon_mode field ─────────────────
echo "--- Test 18: Recon receipt has recon_mode=true ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
assert_json_field "recon receipt has recon_mode=true" "$RECEIPT_DIR/00_preflight.json" ".recon_mode" "true"

# ── Test 19: Normal receipt contains recon_mode=false ────────────────
echo "--- Test 19: Normal receipt has recon_mode=false ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
assert_json_field "normal receipt has recon_mode=false" "$RECEIPT_DIR/00_preflight.json" ".recon_mode" "false"

# ── Test 20: Recon implement receipt has recon_relaxation ────────────
echo "--- Test 20: Recon implement receipt has relaxation note ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
assert_json_field "recon implement has relaxation" "$RECEIPT_DIR/01_implement.json" ".recon_relaxation" "implement_diff_check_skipped"

# ── Test 21: Recon mode blocked for passes=false story ───────────────
echo "--- Test 21: Recon blocked for passes=false ---"
bash plans/wf_step.sh TEST-002 --reset --yes > /dev/null 2>&1 || true
# Create PRD with passes=false for TEST-002
cat > plans/prd.json <<PRDEOF2
{
  "items": [
    {
      "id": "TEST-001",
      "passes": true,
      "scope": { "allow": ["feature.rs"] }
    },
    {
      "id": "TEST-002",
      "passes": false,
      "scope": { "allow": ["feature.rs"] }
    }
  ]
}
PRDEOF2

WF_RECEIPT_DIR="$TMPDIR/.wf/receipts/TEST-002" \
set +e
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-002 preflight > /dev/null 2>&1
rc=$?
set -e
assert_exit "recon blocked for passes=false story" 3 "$rc"

# ── Test 22: Recon GREEN cycle2 with 1 review artifact ───────────────
echo "--- Test 22: Recon GREEN cycle2 needs only 1 review ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1

# Build chain through cycle1 with 0-findings review
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Recon self-review" > artifacts/story/TEST-001/self_review/review.md
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1

# Clean review dirs and add 0-findings review
rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_recon_review.md <<RECONREV
- HEAD: $(git rev-parse HEAD)
0 findings. No issues detected.
RECONREV
write_cycle2_sidecar "artifacts/story/TEST-001/codex/20260220_recon_review.md"
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1

# Only 1 review artifact — GREEN recon should pass, normal would fail
set +e
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1
rc=$?
set -e
assert_exit "recon GREEN cycle2 passes with 1 review" 0 "$rc"

# ── Test 23: Normal cycle2 still needs 2 reviews ────────────────────
echo "--- Test 23: Normal cycle2 still needs 2 reviews ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
echo "test23 code" > test23.rs
git add test23.rs && git commit -q -m "test23 code"
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Self-review" > artifacts/story/TEST-001/self_review/review.md
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1

rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_c1_review.md <<C1REV
- HEAD: $(git rev-parse HEAD)
P1 - Missing error handling
C1REV
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
echo "test23 fix" >> test23.rs
git add test23.rs && git commit -q -m "test23 fix"
bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1

# Only 1 review — normal mode should fail
set +e
bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1
rc=$?
set -e
assert_exit "normal cycle2 blocked with 1 review" 3 "$rc"

# ── Test 24: Fix receipt has code_changed=true when code changed ─────
echo "--- Test 24: Fix receipt has code_changed field ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
echo "test24 code" > test24.rs
git add test24.rs && git commit -q -m "test24 code"
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Self-review" > artifacts/story/TEST-001/self_review/review.md
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1
rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_t24_review.md <<T24REV
- HEAD: $(git rev-parse HEAD)
P1 - Missing error handling
T24REV
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
echo "test24 fix" >> test24.rs
git add test24.rs && git commit -q -m "test24 fix"
bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1
assert_json_field "fix receipt has code_changed=true" "$RECEIPT_DIR/04_fix.json" ".code_changed" "true"

# ── Test 25: Fix receipt has code_changed=false for 0-findings ──────
echo "--- Test 25: Fix receipt has code_changed=false for 0-findings ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
echo "test25 perfect" > test25.rs
git add test25.rs && git commit -q -m "test25 perfect"
bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Self-review" > artifacts/story/TEST-001/self_review/review.md
bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1
rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_t25_review.md <<T25REV
- HEAD: $(git rev-parse HEAD)
0 findings. No issues detected.
T25REV
bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1
assert_json_field "fix receipt has code_changed=false" "$RECEIPT_DIR/04_fix.json" ".code_changed" "false"

echo ""
echo "=== PART 9: Recon cycle2 escalation integration (wf_step) ==="

# ── Test 26: Recon YELLOW escalation — code change triggers full cycle2 requirements ──
echo "--- Test 26: Recon YELLOW escalation blocks cycle2 ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1

# Ensure PRD has passes=true for TEST-001
cat > plans/prd.json <<PRDEOF3
{
  "items": [
    {
      "id": "TEST-001",
      "passes": true,
      "scope": { "allow": ["feature.rs"] }
    },
    {
      "id": "TEST-002",
      "passes": false,
      "scope": { "allow": ["feature.rs"] }
    }
  ]
}
PRDEOF3

# Build chain through cycle1 in recon mode
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "Recon self-review for escalation test" > artifacts/story/TEST-001/self_review/review.md
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1

# Cycle1 with findings (not 0-findings — triggers YELLOW when code changes)
rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_escalation_review.md <<ESCREV
- HEAD: $(git rev-parse HEAD)
P1 - Missing error handling in escalation test
ESCREV
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1

# Record cycle1 HEAD for verification
CYCLE1_HEAD="$(jq -r '.head_sha' "$RECEIPT_DIR/03_cycle1.json")"

# Make a code change — HEAD advances past cycle1 receipt's head_sha
echo "escalation fix code" > escalation_fix.rs
git add escalation_fix.rs && git commit -q -m "escalation fix"

# Run fix directly (fix is pre-fix step — always uses recon in supervisor)
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1

# Verify HEAD actually changed (test precondition)
CURRENT_HEAD="$(git rev-parse HEAD)"
if [[ "$CYCLE1_HEAD" == "$CURRENT_HEAD" ]]; then
  echo "FAIL: test precondition — HEAD did not advance past cycle1"
  FAIL=$((FAIL + 1))
else
  # Run cycle2 in recon mode:
  # wf_step should detect fix.code_changed=true and require full cycle2 (2 reviews).
  # We only have 1 review artifact, so cycle2 must fail with exit 3.
  set +e
  WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1
  rc=$?
  set -e
  assert_exit "wf_step recon YELLOW escalation blocks cycle2 with 1 review" 3 "$rc"
fi

# ── Test 27: Recon GREEN path — no code change, cycle2 passes with 1 review ──
echo "--- Test 27: Recon GREEN path passes cycle2 ---"
bash plans/wf_step.sh TEST-001 --reset --yes > /dev/null 2>&1

# Build chain through cycle1 with 0-findings (GREEN path — no code change needed)
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 preflight > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 implement > /dev/null 2>&1
mkdir -p artifacts/story/TEST-001/self_review
echo "GREEN path self-review" > artifacts/story/TEST-001/self_review/review.md
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 self_review > /dev/null 2>&1

rm -f artifacts/story/TEST-001/codex/*.md artifacts/story/TEST-001/opus/*.md 2>/dev/null || true
mkdir -p artifacts/story/TEST-001/codex
cat > artifacts/story/TEST-001/codex/20260220_green_review.md <<GREENREV
- HEAD: $(git rev-parse HEAD)
0 findings. No issues detected.
GREENREV
write_cycle2_sidecar "artifacts/story/TEST-001/codex/20260220_green_review.md"
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle1 > /dev/null 2>&1
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 fix > /dev/null 2>&1

# No code change — wf_step should keep abbreviated cycle2 path (min_reviews=1)
set +e
WF_RECON_MODE=1 bash plans/wf_step.sh TEST-001 cycle2 > /dev/null 2>&1
rc=$?
set -e
assert_exit "wf_step recon GREEN path passes cycle2 with 1 review" 0 "$rc"


echo ""
echo "============================================"
echo "Results: PASS=$PASS FAIL=$FAIL"
if [[ "$FAIL" -eq 0 ]]; then
  echo "ALL TESTS PASSED"
  exit 0
else
  echo "SOME TESTS FAILED"
  exit 1
fi
