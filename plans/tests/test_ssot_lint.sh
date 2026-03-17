#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/ssot_lint.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local out=""
  set +e
  out="$("$@" 2>&1)"
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$out" | grep -Fq "$pattern" || fail "$label missing expected error '$pattern'"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
mkdir -p \
  "$fixture/docs" \
  "$fixture/plans" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_evidence_missing" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_path_traversal" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_story_mismatch" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_test_missing" \
  "$fixture/plans/tests/fixtures/doc_sync/valid" \
  "$fixture/specs"

cp "$SCRIPT" "$fixture/plans/ssot_lint.sh"
chmod +x "$fixture/plans/ssot_lint.sh"

cat > "$fixture/specs/CONTRACT.md" <<'EOF'
# CONTRACT
EOF

cat > "$fixture/specs/IMPLEMENTATION_PLAN.md" <<'EOF'
# IMPLEMENTATION PLAN
EOF

cat > "$fixture/specs/POLICY.md" <<'EOF'
# POLICY
EOF

cat > "$fixture/specs/WORKFLOW_CONTRACT.md" <<'EOF'
# WORKFLOW CONTRACT
EOF

cat > "$fixture/specs/SOURCE_OF_TRUTH.md" <<'EOF'
# SOURCE OF TRUTH
EOF

cat > "$fixture/IMPLEMENTATION_PLAN.md" <<'EOF'
CANONICAL SOURCE OF TRUTH: specs/IMPLEMENTATION_PLAN.md
See specs/IMPLEMENTATION_PLAN.md.
EOF

cat > "$fixture/POLICY.md" <<'EOF'
CANONICAL SOURCE OF TRUTH: specs/POLICY.md
See specs/POLICY.md.
EOF

for path in \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_evidence_missing/IMPLEMENTATION_PLAN.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_path_traversal/IMPLEMENTATION_PLAN.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_story_mismatch/IMPLEMENTATION_PLAN.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_test_missing/IMPLEMENTATION_PLAN.md" \
  "$fixture/plans/tests/fixtures/doc_sync/valid/IMPLEMENTATION_PLAN.md"
do
  cat > "$path" <<'EOF'
# fixture impl plan
EOF
done

for path in \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_evidence_missing/POLICY.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_path_traversal/POLICY.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_story_mismatch/POLICY.md" \
  "$fixture/plans/tests/fixtures/doc_sync/invalid_test_missing/POLICY.md" \
  "$fixture/plans/tests/fixtures/doc_sync/valid/POLICY.md"
do
  cat > "$path" <<'EOF'
# fixture policy
EOF
done

bash "$fixture/plans/ssot_lint.sh" >/dev/null

cat > "$fixture/docs/IMPLEMENTATION_PLAN.md" <<'EOF'
# extra duplicate
EOF

expect_fail \
  "real duplicate still fails" \
  "Duplicate IMPLEMENTATION_PLAN.md copies found" \
  bash "$fixture/plans/ssot_lint.sh"

echo "PASS: ssot lint"
