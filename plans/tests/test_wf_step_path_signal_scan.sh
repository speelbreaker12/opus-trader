#!/usr/bin/env bash
set -euo pipefail

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

mkdir -p "$repo/plans" "$repo/plans/lib" "$repo/.wf/receipts/S1-001" "$repo/artifacts/story/S1-001/cycle1"
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

head_sha="$(git -C "$repo" rev-parse HEAD)"
steps=(preflight implement self_review cycle1)
for i in "${!steps[@]}"; do
  step="${steps[$i]}"
  receipt="$repo/.wf/receipts/S1-001/$(printf '%02d_%s.json' "$i" "$step")"
  cat > "$receipt" <<EOF
{"story_id":"S1-001","step_name":"$step","head_sha":"$head_sha"}
EOF
done

cat > "$repo/artifacts/story/S1-001/cycle1/evidence_ledger.md" <<'EOF'
# Evidence Ledger
PATH: GREEN
EOF

set +e
fix_output="$(
  cd "$repo" && bash plans/wf_step.sh S1-001 fix 2>&1
)"
fix_rc=$?
set -e

[[ "$fix_rc" -eq 0 ]] || fail "fix step should accept PATH: GREEN on non-first ledger line"
echo "$fix_output" | grep -Fq "cycle1 had 0 findings" || fail "fix step did not detect GREEN path signal"
jq -e '.code_changed == false' "$repo/.wf/receipts/S1-001/04_fix.json" >/dev/null \
  || fail "fix receipt should record code_changed=false for GREEN path"

echo "test_wf_step_path_signal_scan.sh: ok"
