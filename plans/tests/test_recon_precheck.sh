#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_precheck.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SCRIPT" ]] || fail "missing script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

cd "$tmp_dir"
git init -q
git config core.hooksPath /dev/null
git symbolic-ref HEAD refs/heads/main
git config user.email "test@example.com"
git config user.name "Test"

mkdir -p plans reviews/premortems
cp "$SCRIPT" plans/recon_precheck.sh
chmod +x plans/recon_precheck.sh

echo "seed" > seed.txt
git add -A
git commit -q -m "seed"

# Conflict fixture: S3-000 and S3-002 share AT-004.
cat > plans/prd.json <<'EOF'
{
  "items": [
    { "id": "S3-000", "primary_owner_for": ["AT-004"] },
    { "id": "S3-002", "primary_owner_for": ["AT-004"] }
  ]
}
EOF

set +e
out_missing="$(plans/recon_precheck.sh S3-000 2>&1)"
rc_missing=$?
set -e
[[ "$rc_missing" -eq 1 ]] || fail "expected missing premortem to block (exit 1), got $rc_missing"
echo "$out_missing" | grep -q "premortem file not found" || fail "missing premortem reason not reported"

cat > reviews/premortems/S3-000_premortem.md <<'EOF'
# Premortem S3-000
EOF

set +e
out_conflict="$(plans/recon_precheck.sh S3-000 2>&1)"
rc_conflict=$?
set -e
[[ "$rc_conflict" -eq 1 ]] || fail "expected ownership conflict to block (exit 1), got $rc_conflict"
echo "$out_conflict" | grep -q "AT ownership conflict" || fail "ownership conflict reason not reported"

json_skip="$(RECON_SKIP_OWNERSHIP=1 plans/recon_precheck.sh S3-000 --json)"
echo "$json_skip" | jq -e '.ready == true' >/dev/null || fail "skip mode should still report ready"
echo "$json_skip" | jq -e '.ownership_conflicts == 0' >/dev/null || fail "skip mode should zero ownership_conflicts"
echo "$json_skip" | jq -e '.ownership_conflict_details == []' >/dev/null || fail "skip mode should clear ownership_conflict_details"

cat > plans/prd.json <<'EOF'
{
  "items": [
    { "id": "S3-000", "primary_owner_for": ["AT-004"] },
    { "id": "S3-002", "primary_owner_for": ["AT-005"] }
  ]
}
EOF

set +e
out_ready="$(plans/recon_precheck.sh S3-000 2>&1)"
rc_ready=$?
set -e
[[ "$rc_ready" -eq 0 ]] || fail "expected precheck to pass, got $rc_ready"
echo "$out_ready" | grep -q "PASS: recon precheck ready" || fail "ready output missing"

json_out="$(plans/recon_precheck.sh S3-000 --json)"
echo "$json_out" | jq -e '.schema_version == "recon_precheck.v1"' >/dev/null || fail "json schema_version mismatch"
echo "$json_out" | jq -e '.ready == true' >/dev/null || fail "json ready should be true"
echo "$json_out" | jq -e '.ownership_conflicts == 0' >/dev/null || fail "json ownership_conflicts should be 0"

cat > reviews/premortems/S3-999_premortem.md <<'EOF'
# Premortem S3-999
EOF

set +e
out_missing_story="$(plans/recon_precheck.sh S3-999 2>&1)"
rc_missing_story=$?
set -e
[[ "$rc_missing_story" -eq 1 ]] || fail "expected missing story to block (exit 1), got $rc_missing_story"
echo "$out_missing_story" | grep -q "story not found in plans/prd.json" || fail "missing story reason not reported"

cat > plans/prd.json <<'EOF'
{
  "stories": {
    "L2-000": { "primary_owner_for": ["AT-900"] },
    "L2-001": { "primary_owner_for": ["AT-901"] }
  }
}
EOF

cat > reviews/premortems/L2-000_premortem.md <<'EOF'
# Premortem L2-000
EOF
set +e
out_legacy_ready="$(plans/recon_precheck.sh L2-000 2>&1)"
rc_legacy_ready=$?
set -e
[[ "$rc_legacy_ready" -eq 0 ]] || fail "expected legacy stories precheck to pass, got $rc_legacy_ready"
echo "$out_legacy_ready" | grep -q "PASS: recon precheck ready" || fail "legacy stories pass output missing"

cat > plans/prd.json <<'EOF'
{
  "stories": {
    "L2-000": { "primary_owner_for": ["AT-900"] },
    "L2-001": { "primary_owner_for": ["AT-900"] }
  }
}
EOF
set +e
out_legacy_conflict="$(plans/recon_precheck.sh L2-000 2>&1)"
rc_legacy_conflict=$?
set -e
[[ "$rc_legacy_conflict" -eq 1 ]] || fail "expected legacy conflict to block (exit 1), got $rc_legacy_conflict"
echo "$out_legacy_conflict" | grep -q "AT ownership conflict" || fail "legacy conflict reason not reported"

cat > reviews/premortems/L2-999_premortem.md <<'EOF'
# Premortem L2-999
EOF
set +e
out_legacy_missing_story="$(plans/recon_precheck.sh L2-999 2>&1)"
rc_legacy_missing_story=$?
set -e
[[ "$rc_legacy_missing_story" -eq 1 ]] || fail "expected legacy missing story to block (exit 1), got $rc_legacy_missing_story"
echo "$out_legacy_missing_story" | grep -q "story not found in plans/prd.json" || fail "legacy missing story reason not reported"

cat > plans/prd.json <<'EOF'
{"items":[
EOF

set +e
out_bad_prd="$(plans/recon_precheck.sh S3-000 2>&1)"
rc_bad_prd=$?
set -e
[[ "$rc_bad_prd" -eq 2 ]] || fail "expected malformed PRD to fail setup (exit 2), got $rc_bad_prd"
echo "$out_bad_prd" | grep -q "failed to parse ownership conflict data" || fail "malformed PRD parse error not reported"

# --- stale-docs warning test ---
# Restore valid PRD and premortem for S3-000
cat > plans/prd.json <<'EOF'
{
  "items": [
    { "id": "S3-000", "primary_owner_for": ["AT-004"] },
    { "id": "S3-002", "primary_owner_for": ["AT-005"] }
  ]
}
EOF

# Create a key process doc on main that differs from HEAD
mkdir -p plans/step_prompts/recon
echo "v1" > plans/step_prompts/recon/INDEX.md
git add -A
git commit -q -m "add process doc v1"

# Now modify it on detached HEAD while leaving main pinned to v1.
git update-ref --no-deref HEAD "$(git rev-parse HEAD)"
echo "v2" > plans/step_prompts/recon/INDEX.md
git add -A
git commit -q -m "modify process doc v2"

git symbolic-ref -q --short HEAD >/dev/null && fail "stale-doc fixture should leave HEAD detached"

set +e
out_stale="$(plans/recon_precheck.sh S3-000 2>&1)"
rc_stale=$?
set -e
[[ "$rc_stale" -eq 0 ]] || fail "expected stale-docs to still pass (exit 0), got $rc_stale"
echo "$out_stale" | grep -q "process doc(s) differ from main" || fail "stale-docs warning not emitted"

# JSON mode should include stale_docs array
json_stale="$(plans/recon_precheck.sh S3-000 --json)"
echo "$json_stale" | jq -e '.stale_docs | length > 0' >/dev/null || fail "json stale_docs should be non-empty"
echo "$json_stale" | jq -e '.stale_docs | index("plans/step_prompts/recon/INDEX.md")' >/dev/null || fail "json stale_docs should contain INDEX.md"
echo "$json_stale" | jq -e '.ready == true' >/dev/null || fail "json ready should still be true with stale docs"

echo "test_recon_precheck.sh: ok"
