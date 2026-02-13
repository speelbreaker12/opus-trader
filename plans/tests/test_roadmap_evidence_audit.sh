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

echo "PASS: roadmap evidence audit"
