#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_scoreboard.py"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SCRIPT" ]] || fail "missing script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

story_id="S0-000"
receipt_root="$tmp_dir/receipts"
story_receipts="$receipt_root/$story_id"
mkdir -p "$story_receipts"

head_sha="$(git -C "$ROOT" rev-parse HEAD)"
alt_head="$(git -C "$ROOT" rev-parse HEAD~1 2>/dev/null || echo "$head_sha")"

cat > "$story_receipts/00_preflight.json" <<EOF
{"story_id":"$story_id","step_name":"preflight","head_sha":"$head_sha"}
EOF

cat > "$story_receipts/01_implement.json" <<EOF
{"story_id":"S0-000","step_name":"implement","head_sha":"$alt_head"}
EOF

cat > "$story_receipts/02_self_review.json" <<'EOF'
{"story_id":"S0-000","step_name":"self_review","head_sha":
EOF

md_out="$tmp_dir/SCOREBOARD.md"
json_out="$tmp_dir/SCOREBOARD.json"
json_out_alt_head="$tmp_dir/SCOREBOARD.alt_head.json"
artifacts_root="$tmp_dir/story_artifacts"
mkdir -p "$artifacts_root/$story_id/cycle1"
cat > "$artifacts_root/$story_id/cycle1/evidence_ledger.md" <<'EOF'
# Evidence Ledger
PATH: GREEN
EOF

(
  cd "$ROOT"
  WF_RECEIPT_DIR="$receipt_root" STORY_ARTIFACTS_ROOT="$artifacts_root" python3 plans/recon_scoreboard.py \
    --slice 0 \
    --stories "$story_id" \
    --out-md "$md_out" \
    --out-json "$json_out" \
    >/dev/null
)

[[ -f "$md_out" ]] || fail "markdown output not written"
[[ -f "$json_out" ]] || fail "json output not written"

grep -Fq "| Story | passes | PATH | preflight | implement | self_review | cycle1 | fix | cycle2 | resolution | verify_full | pass | HEAD |" "$md_out" \
  || fail "markdown table header missing"

grep -Fq "| $story_id |" "$md_out" || fail "story row missing from markdown"
grep -Fq "✓" "$md_out" || fail "expected DONE glyph not found"
grep -Fq "!" "$md_out" || fail "expected STALE glyph not found"
grep -Fq "| $story_id | true | GREEN |" "$md_out" || fail "expected markdown PATH signal not found"

grep -Fq '"story_id": "S0-000"' "$json_out" || fail "story id missing from json"
grep -Fq '"implement": "STALE"' "$json_out" || fail "stale status missing from json"
grep -Fq '"self_review": "MISSING"' "$json_out" || fail "malformed receipt should map to MISSING"
grep -Fq '"pass": "MISSING"' "$json_out" || fail "pass should be missing when prerequisites are missing"
grep -Fq '"step_receipt_head_sha"' "$json_out" || fail "step receipt head debug map missing"
grep -Fq '"preflight": "'"$head_sha"'"' "$json_out" || fail "preflight head missing from debug map"
grep -Fq '"implement": "'"$alt_head"'"' "$json_out" || fail "implement head missing from debug map"

# JSON-first PATH source: once ledger JSON exists, scoreboard should prefer it.
cat > "$artifacts_root/$story_id/evidence_ledger.json" <<'EOF'
{"schema_version":"evidence_ledger.v1","path":"YELLOW"}
EOF

(
  cd "$ROOT"
  WF_RECEIPT_DIR="$receipt_root" STORY_ARTIFACTS_ROOT="$artifacts_root" python3 plans/recon_scoreboard.py \
    --slice 0 \
    --stories "$story_id" \
    --out-md "$md_out" \
    --out-json "$json_out" \
    >/dev/null
)

grep -Fq "| $story_id | true | YELLOW |" "$md_out" || fail "expected JSON-ledger PATH override not found"
grep -Fq '"path_source": "'"$artifacts_root/$story_id/evidence_ledger.json"'"' "$json_out" \
  || fail "expected json path source missing"

# --head should allow scoring against a specific commit-ish.
(
  cd "$ROOT"
  WF_RECEIPT_DIR="$receipt_root" STORY_ARTIFACTS_ROOT="$artifacts_root" python3 plans/recon_scoreboard.py \
    --slice 0 \
    --stories "$story_id" \
    --head "$alt_head" \
    --out-json "$json_out_alt_head" \
    >/dev/null
)
grep -Fq '"head_commit": "'"$alt_head"'"' "$json_out_alt_head" || fail "score head was not applied"
grep -Fq '"preflight": "STALE"' "$json_out_alt_head" || fail "expected preflight to be stale under --head override"
grep -Fq '"implement": "DONE"' "$json_out_alt_head" || fail "expected implement to be done under --head override"

# pass should be derived as DONE when preflight..verify_full are DONE.
story_full="S0-001"
story_full_receipts="$receipt_root/$story_full"
mkdir -p "$story_full_receipts"
steps=(preflight implement self_review cycle1 fix cycle2 resolution verify_full)
for i in "${!steps[@]}"; do
  step="${steps[$i]}"
  file="$story_full_receipts/$(printf '%02d_%s.json' "$i" "$step")"
  cat > "$file" <<EOF
{"story_id":"$story_full","step_name":"$step","head_sha":"$head_sha"}
EOF
done

md_full="$tmp_dir/SCOREBOARD_full.md"
json_full="$tmp_dir/SCOREBOARD_full.json"
artifacts_root_empty="$tmp_dir/story_artifacts_empty"
mkdir -p "$artifacts_root_empty"
(
  cd "$ROOT"
  WF_RECEIPT_DIR="$receipt_root" STORY_ARTIFACTS_ROOT="$artifacts_root_empty" python3 plans/recon_scoreboard.py \
    --slice 0 \
    --stories "$story_full" \
    --out-md "$md_full" \
    --out-json "$json_full" \
    >/dev/null
)
grep -Fq "| $story_full | true | UNKNOWN | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |" "$md_full" \
  || fail "pass should be derived as DONE when preflight..verify_full are DONE"
grep -Fq '"pass": "DONE"' "$json_full" || fail "json pass should be DONE for complete prerequisite chain"

set +e
(
  cd "$ROOT"
  python3 plans/recon_scoreboard.py --slice 0 --stories S0-999 --strict >/dev/null 2>"$tmp_dir/strict.err"
)
strict_rc=$?
set -e
[[ "$strict_rc" -eq 1 ]] || fail "--strict should fail closed when no stories are selected"
grep -Fq "WARN: no stories found for slice 0" "$tmp_dir/strict.err" \
  || fail "missing strict-mode warning for empty story selection"

probe_id="recon_scoreboard_probe_$$"
unsafe_slice="../../../../tmp/$probe_id"
expected_outside_dir="$(
  python3 - <<PY
from pathlib import Path
root = Path(r"$ROOT")
print((root / "reviews" / "reconciliations" / r"$unsafe_slice").resolve())
PY
)"
set +e
(
  cd "$ROOT"
  plans/recon_scoreboard.sh "$unsafe_slice" >/dev/null 2>"$tmp_dir/wrapper.err"
)
wrapper_rc=$?
set -e
[[ "$wrapper_rc" -ne 0 ]] || fail "wrapper should reject unsafe slice ids"
grep -Fq "invalid slice id" "$tmp_dir/wrapper.err" || fail "wrapper did not report invalid slice id"
[[ ! -d "$expected_outside_dir" ]] || fail "wrapper created out-of-repo directory: $expected_outside_dir"

echo "test_recon_scoreboard.sh: ok"
