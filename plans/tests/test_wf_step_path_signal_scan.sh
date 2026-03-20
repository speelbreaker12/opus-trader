#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF_STEP_SRC="$ROOT/plans/wf_step.sh"
HASH_UTILS_SRC="$ROOT/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$WF_STEP_SRC" ]] || fail "missing executable script: $WF_STEP_SRC"
[[ -f "$HASH_UTILS_SRC" ]] || fail "missing hash utils helper: $HASH_UTILS_SRC"
command -v jq >/dev/null 2>&1 || fail "jq is required for this test"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
git -C "$tmp_dir" init -q repo
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "WF Step Test"
git -C "$repo" config core.hooksPath /dev/null

mkdir -p "$repo/plans" "$repo/plans/lib"
cp "$WF_STEP_SRC" "$repo/plans/wf_step.sh"
cp "$HASH_UTILS_SRC" "$repo/plans/lib/hash_utils.sh"
chmod +x "$repo/plans/wf_step.sh"

cat > "$repo/base.txt" <<'EOF'
fixture
EOF

(
  cd "$repo"
  git add -A
  git commit -qm "fixture"
)

seed_receipts() {
  local story_id="$1"
  local head_sha="$2"
  local steps=(preflight implement self_review cycle1)
  local i
  local step
  local receipt

  mkdir -p "$repo/.wf/receipts/$story_id"
  for i in "${!steps[@]}"; do
    step="${steps[$i]}"
    receipt="$repo/.wf/receipts/$story_id/$(printf '%02d_%s.json' "$i" "$step")"
    cat > "$receipt" <<EOF
{"story_id":"$story_id","step_name":"$step","head_sha":"$head_sha"}
EOF
  done
}

head_sha="$(git -C "$repo" rev-parse HEAD)"
seed_receipts "S1-001" "$head_sha"
mkdir -p "$repo/artifacts/story/S1-001"
cat > "$repo/artifacts/story/S1-001/evidence_ledger.json" <<'EOF'
{
  "story_id": "S1-001",
  "path": "GREEN"
}
EOF

set +e
fix_output="$(
  cd "$repo" && bash plans/wf_step.sh S1-001 fix 2>&1
)"
fix_rc=$?
set -e

[[ "$fix_rc" -eq 0 ]] || fail "fix step should accept canonical JSON PATH: GREEN"
echo "$fix_output" | grep -Fq "cycle1 had 0 findings" || fail "fix step did not detect GREEN path signal"
jq -e '.code_changed == false' "$repo/.wf/receipts/S1-001/04_fix.json" >/dev/null \
  || fail "fix receipt should record code_changed=false for GREEN path"

seed_receipts "S1-002" "$head_sha"
mkdir -p "$repo/artifacts/story/S1-002/cycle1"
cat > "$repo/artifacts/story/S1-002/cycle1/evidence_ledger.md" <<'EOF'
# Legacy cycle1 ledger
PATH: GREEN
EOF

set +e
legacy_fix_output="$(
  cd "$repo" && bash plans/wf_step.sh S1-002 fix 2>&1
)"
legacy_fix_rc=$?
set -e

[[ "$legacy_fix_rc" -eq 0 ]] || fail "fix step should accept legacy markdown PATH: GREEN"
echo "$legacy_fix_output" | grep -Fq "using legacy markdown PATH signal" || fail "missing deterministic legacy markdown diagnostic"
echo "$legacy_fix_output" | grep -Fq "cycle1 had 0 findings" || fail "legacy markdown GREEN path should bypass code-change requirement"
jq -e '.code_changed == false' "$repo/.wf/receipts/S1-002/04_fix.json" >/dev/null \
  || fail "legacy markdown GREEN path should record code_changed=false"

# Strict mode requires canonical JSON path and rejects legacy-only ledgers.
seed_receipts "S1-003" "$head_sha"
mkdir -p "$repo/artifacts/story/S1-003/cycle1"
cat > "$repo/artifacts/story/S1-003/cycle1/evidence_ledger.md" <<'EOF'
# Legacy cycle1 ledger
PATH: GREEN
EOF

set +e
strict_missing_output="$(
  cd "$repo" && WF_CYCLE1_PATH_STRICT=1 bash plans/wf_step.sh S1-003 fix 2>&1
)"
strict_missing_rc=$?
set -e
[[ "$strict_missing_rc" -ne 0 ]] || fail "strict mode should fail when canonical JSON PATH ledger is missing"
echo "$strict_missing_output" | grep -Fq "canonical cycle1 PATH ledger required" \
  || fail "strict mode missing canonical-ledger diagnostic"

# Strict mode also rejects malformed canonical PATH signals.
seed_receipts "S1-004" "$head_sha"
mkdir -p "$repo/artifacts/story/S1-004"
cat > "$repo/artifacts/story/S1-004/evidence_ledger.json" <<'EOF'
{
  "story_id": "S1-004",
  "path": "MAYBE"
}
EOF

set +e
strict_invalid_output="$(
  cd "$repo" && WF_CYCLE1_PATH_STRICT=1 bash plans/wf_step.sh S1-004 fix 2>&1
)"
strict_invalid_rc=$?
set -e
[[ "$strict_invalid_rc" -ne 0 ]] || fail "strict mode should fail on malformed canonical PATH signal"
echo "$strict_invalid_output" | grep -Fq "canonical cycle1 PATH signal invalid" \
  || fail "strict mode invalid-PATH diagnostic missing"

echo "test_wf_step_path_signal_scan.sh: ok"
