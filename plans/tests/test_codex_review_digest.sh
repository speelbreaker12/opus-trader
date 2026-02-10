#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DIGEST="$ROOT/plans/codex_review_digest.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  set +e
  output="$("$@" 2>&1)"
  local rc=$?
  set -e

  if [[ $rc -eq 0 ]]; then
    fail "$label expected non-zero exit"
  fi
  if ! printf '%s\n' "$output" | grep -Fq "$pattern"; then
    fail "$label missing expected error '$pattern'"
  fi
}

[[ -x "$DIGEST" ]] || fail "missing executable digest script: $DIGEST"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# Case 1: parse severities and final message from raw review.
raw1="$tmp_dir/20260209T000000Z_review.md"
cat > "$raw1" <<'EOF'
# Codex review

- Story: S1-012
- Timestamp (UTC): 20260209T000000Z
- Branch: slice1/S1-012-review-gate-passflip-v2
- HEAD: deadbeef

---

- [P1] Finding one
Supporting details.

Final recommendation line.
EOF

out1="$tmp_dir/20260209T000000Z_digest.md"
"$DIGEST" "$raw1" --out "$out1" >/dev/null
grep -Fq -- "- Story: S1-012" "$out1" || fail "case1 missing story metadata"
grep -Fq -- "- [P1] Finding one" "$out1" || fail "case1 missing severity line"
grep -Fq -- "Final recommendation line." "$out1" || fail "case1 missing final message"

# Case 2: no severity lines should render '- none'.
raw2="$tmp_dir/20260209T000001Z_review.md"
cat > "$raw2" <<'EOF'
# Codex review

- Story: S1-013
- Timestamp (UTC): 20260209T000001Z
- HEAD: cafe1234

---

No severity tags here.

Terminal summary.
EOF

out2="$tmp_dir/20260209T000001Z_digest.md"
"$DIGEST" "$raw2" --out "$out2" >/dev/null
grep -Fq -- "## Severity Findings (P0/P1/P2)" "$out2" || fail "case2 missing severity heading"
grep -Fq -- "- none" "$out2" || fail "case2 missing none marker"
grep -Fq -- "Terminal summary." "$out2" || fail "case2 missing final message"

# Case 3: default output naming from *_review.md -> *_digest.md.
raw3="$tmp_dir/sample_review.md"
cat > "$raw3" <<'EOF'
# Codex review

- Story: S1-014
- HEAD: f00dbabe
EOF
"$DIGEST" "$raw3" >/dev/null
[[ -f "$tmp_dir/sample_digest.md" ]] || fail "case3 missing default digest output"

# Case 4: missing file fails closed.
expect_fail "missing input file" "raw review file not found" \
  "$DIGEST" "$tmp_dir/does-not-exist_review.md"

echo "PASS: codex review digest fixtures"
