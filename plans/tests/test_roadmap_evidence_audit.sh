#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOOL="$ROOT/tools/roadmap_evidence_audit.py"

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

[[ -f "$TOOL" ]] || fail "missing tool: $TOOL"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

allowlist="$tmp_dir/allowlist.json"
cat > "$allowlist" <<'EOF_ALLOWLIST'
{
  "entries": []
}
EOF_ALLOWLIST

# Case 1: CI strict passes with exact requirement + ANY_OF fallback satisfied.
checklist_pass="$tmp_dir/checklist_pass.md"
cat > "$checklist_pass" <<'EOF_CHECKLIST_PASS'
# Checklist
<!-- REQUIRED_EVIDENCE: evidence/phase0/sample_a.txt -->
<!-- REQUIRED_EVIDENCE_ANY_OF: evidence/phase0/opt_a.txt | evidence/phase0/opt_b.txt -->
EOF_CHECKLIST_PASS

prd_pass="$tmp_dir/prd_pass.json"
cat > "$prd_pass" <<'EOF_PRD_PASS'
{
  "items": [
    {
      "id": "S-PASS",
      "evidence": [
        "evidence/phase0/sample_a.txt",
        "evidence/phase0/opt_b.txt"
      ]
    }
  ]
}
EOF_PRD_PASS

expect_rc 0 python3 "$TOOL" \
  --prd "$prd_pass" \
  --inputs "$checklist_pass" \
  --global-manual-allowlist "$allowlist" \
  --ci \
  --strict

# Case 2: CI strict fails on unresolved STORY_OWNED gaps.
checklist_gap="$tmp_dir/checklist_gap.md"
cat > "$checklist_gap" <<'EOF_CHECKLIST_GAP'
# Checklist
<!-- REQUIRED_EVIDENCE: evidence/phase0/missing_required.txt -->
EOF_CHECKLIST_GAP

prd_gap="$tmp_dir/prd_gap.json"
cat > "$prd_gap" <<'EOF_PRD_GAP'
{
  "items": [
    {
      "id": "S-GAP",
      "evidence": []
    }
  ]
}
EOF_PRD_GAP

expect_rc 4 python3 "$TOOL" \
  --prd "$prd_gap" \
  --inputs "$checklist_gap" \
  --global-manual-allowlist "$allowlist" \
  --ci \
  --strict

# Case 3: CI mode fails when marker intent is absent in a scanned file.
checklist_nomarker="$tmp_dir/checklist_nomarker.md"
cat > "$checklist_nomarker" <<'EOF_CHECKLIST_NOMARKER'
# Checklist without marker intent
EOF_CHECKLIST_NOMARKER

expect_rc 2 python3 "$TOOL" \
  --prd "$prd_pass" \
  --inputs "$checklist_nomarker" \
  --global-manual-allowlist "$allowlist" \
  --ci

# Case 4: Duplicate normalized path declarations are schema violations.
checklist_duplicate="$tmp_dir/checklist_duplicate.md"
cat > "$checklist_duplicate" <<'EOF_CHECKLIST_DUP'
<!-- REQUIRED_EVIDENCE: evidence/phase0/dup.txt -->
<!-- REQUIRED_EVIDENCE: evidence/phase0/dup.txt -->
EOF_CHECKLIST_DUP

expect_rc 7 python3 "$TOOL" \
  --prd "$prd_pass" \
  --inputs "$checklist_duplicate" \
  --global-manual-allowlist "$allowlist" \
  --ci

# Case 5: ANY_OF duplicate options are schema violations.
checklist_anyof_dup="$tmp_dir/checklist_anyof_dup.md"
cat > "$checklist_anyof_dup" <<'EOF_CHECKLIST_ANYOF_DUP'
<!-- REQUIRED_EVIDENCE_ANY_OF: evidence/phase0/a.txt | evidence/phase0/a.txt -->
EOF_CHECKLIST_ANYOF_DUP

expect_rc 7 python3 "$TOOL" \
  --prd "$prd_pass" \
  --inputs "$checklist_anyof_dup" \
  --global-manual-allowlist "$allowlist" \
  --ci

# Case 6: CI allowlist path existence is anchored to repo root, not caller CWD.
checklist_repo_root="$tmp_dir/checklist_repo_root.md"
cat > "$checklist_repo_root" <<'EOF_CHECKLIST_REPO_ROOT'
<!-- REQUIRED_EVIDENCE: evidence/phase0/README.md -->
EOF_CHECKLIST_REPO_ROOT

prd_repo_root="$tmp_dir/prd_repo_root.json"
cat > "$prd_repo_root" <<'EOF_PRD_REPO_ROOT'
{
  "items": [
    {
      "id": "S-ROOT",
      "evidence": [
        "evidence/phase0/README.md"
      ]
    }
  ]
}
EOF_PRD_REPO_ROOT

allowlist_repo_root="$tmp_dir/allowlist_repo_root.json"
cat > "$allowlist_repo_root" <<'EOF_ALLOWLIST_REPO_ROOT'
{
  "entries": [
    {
      "evidence_path": "evidence/phase0/README.md",
      "justification": "manual evidence index",
      "owning_story_id": "GLOBAL-PHASE0"
    }
  ]
}
EOF_ALLOWLIST_REPO_ROOT

set +e
(
  cd "$ROOT/tools"
  python3 "$TOOL" \
    --prd "$prd_repo_root" \
    --inputs "$checklist_repo_root" \
    --global-manual-allowlist "$allowlist_repo_root" \
    --ci \
    --strict
) >"$tmp_dir/out.txt" 2>"$tmp_dir/err.txt"
case6_rc=$?
set -e
if [[ "$case6_rc" -ne 0 ]]; then
  echo "stdout:" >&2
  cat "$tmp_dir/out.txt" >&2 || true
  echo "stderr:" >&2
  cat "$tmp_dir/err.txt" >&2 || true
  fail "case6 expected rc=0 from non-root cwd"
fi

echo "PASS: roadmap evidence audit"
