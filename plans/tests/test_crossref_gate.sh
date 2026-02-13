#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/crossref_gate.sh"

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

[[ -x "$GATE" ]] || fail "crossref gate not executable: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

contract_ok="$tmp_dir/contract_ok.md"
cat > "$contract_ok" <<'EOF_CONTRACT_OK'
# CONTRACT fixture
Profile: CSP
AT-001 trailing description

Profile: GOP
AT-002
EOF_CONTRACT_OK

prd_ok="$tmp_dir/prd_ok.json"
cat > "$prd_ok" <<'EOF_PRD_OK'
{
  "items": [
    {
      "id": "S-CROSSREF-OK",
      "contract_refs": ["AT-001"],
      "evidence": ["evidence/phase0/sample.txt"]
    }
  ]
}
EOF_PRD_OK

allowlist="$tmp_dir/allowlist.json"
cat > "$allowlist" <<'EOF_ALLOWLIST'
{
  "entries": []
}
EOF_ALLOWLIST

checklist_ok="$tmp_dir/checklist_ok.md"
cat > "$checklist_ok" <<'EOF_CHECKLIST_OK'
<!-- REQUIRED_EVIDENCE: evidence/phase0/sample.txt -->
EOF_CHECKLIST_OK

artifacts_ok="$tmp_dir/artifacts_ok"
expect_rc 0 "$GATE" \
  --contract "$contract_ok" \
  --prd "$prd_ok" \
  --inputs "$checklist_ok" \
  --allowlist "$allowlist" \
  --artifacts-dir "$artifacts_ok" \
  --ci \
  --strict

crossref_dir="$artifacts_ok/crossref"
[[ -f "$crossref_dir/contract_at_profile_map.json" ]] || fail "missing contract profile map artifact"
[[ -f "$crossref_dir/report_at_profile_map.json" ]] || fail "missing report profile map artifact"
[[ -f "$crossref_dir/at_profile_parity.json" ]] || fail "missing parity artifact"
[[ -f "$crossref_dir/roadmap_evidence_audit.json" ]] || fail "missing roadmap audit artifact"
[[ -f "$crossref_dir/crossref_invariants.json" ]] || fail "missing invariants artifact"
python3 - "$crossref_dir/crossref_invariants.json" <<'PYJSON'
import json
import sys
json.load(open(sys.argv[1]))
PYJSON

# Fails closed when marker intent is missing in CI mode.
checklist_bad="$tmp_dir/checklist_bad.md"
cat > "$checklist_bad" <<'EOF_CHECKLIST_BAD'
# no required evidence marker
EOF_CHECKLIST_BAD

expect_rc 2 "$GATE" \
  --contract "$contract_ok" \
  --prd "$prd_ok" \
  --inputs "$checklist_bad" \
  --allowlist "$allowlist" \
  --artifacts-dir "$tmp_dir/artifacts_bad" \
  --ci

echo "PASS: crossref gate"
