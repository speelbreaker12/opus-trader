#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
WF_STEP_SRC="$ROOT/plans/wf_step.sh"
REVIEW_LOGGED_SRC="$ROOT/plans/review_logged.sh"
HASH_UTILS_SRC="$ROOT/plans/lib/hash_utils.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  fail "no sha256 tool available"
}

write_sidecar() {
  local artifact="$1"
  local phase="$2"
  local basis="$3"
  local tool="$4"
  local story="$5"
  local head_sha="$6"
  local now_utc
  local md_sha
  now_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  md_sha="$(sha256_file "$artifact")"
  cat > "${artifact%.md}.sidecar.json" <<JSON
{
  "schema_version": "review_artifact_sidecar.v1",
  "head_commit": "$head_sha",
  "created_at": "$now_utc",
  "markdown_sha256": "$md_sha",
  "markdown_path": "$artifact",
  "story_id": "$story",
  "review_type": "external",
  "review_basis": "$basis",
  "tool": "$tool",
  "phase_equivalent": "$phase",
  "citations_count": 1,
  "pre_existing_citations_count": 1,
  "basis_line_present": true,
  "finding_counts": {
    "P0": 0,
    "P1": 0,
    "P2": 0,
    "INFO": 0
  }
}
JSON
}

[[ -x "$WF_STEP_SRC" ]] || fail "missing executable wf_step: $WF_STEP_SRC"
[[ -f "$REVIEW_LOGGED_SRC" ]] || fail "missing review_logged source: $REVIEW_LOGGED_SRC"
[[ -f "$HASH_UTILS_SRC" ]] || fail "missing hash utils source: $HASH_UTILS_SRC"
command -v jq >/dev/null 2>&1 || fail "jq is required"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

repo="$tmp_dir/repo"
mkdir -p "$repo/plans" "$repo/plans/lib" "$repo/.wf/receipts/S9-000" "$repo/artifacts/story/S9-000/codex" "$repo/artifacts/story/S9-000/sonnet"

(
  cd "$tmp_dir"
  git init -q repo
)
git -C "$repo" config user.email "test@example.com"
git -C "$repo" config user.name "Test"
git -C "$repo" config core.hooksPath /dev/null

cp "$WF_STEP_SRC" "$repo/plans/wf_step.sh"
cp "$REVIEW_LOGGED_SRC" "$repo/plans/review_logged.sh"
cp "$HASH_UTILS_SRC" "$repo/plans/lib/hash_utils.sh"
chmod +x "$repo/plans/wf_step.sh"

cat > "$repo/plans/verify_citations.sh" <<'VC'
#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
if [[ " $* " == *" --json "* ]]; then
  echo '{"status":"PASS"}'
fi
exit 0
VC
chmod +x "$repo/plans/verify_citations.sh"

cat > "$repo/plans/prd.json" <<'PRD'
{
  "items": [
    {
      "id": "S9-000",
      "slice": 9,
      "passes": true,
      "scope": {
        "touches": ["crates/soldier_core/src/lib.rs"]
      }
    }
  ]
}
PRD

echo "seed" > "$repo/seed.txt"
(
  cd "$repo"
  git add -A
  git commit -q -m "seed"
)

story="S9-000"
head_sha="$(git -C "$repo" rev-parse HEAD)"

# Run preflight once to materialize scope lock deterministically.
(
  cd "$repo"
  bash plans/wf_step.sh "$story" preflight >/dev/null
)

# Seed step 1 and step 2 receipts (cycle1 prerequisites).
cat > "$repo/.wf/receipts/$story/01_implement.json" <<JSON
{"story_id":"$story","step_name":"implement","step_index":1,"head_sha":"$head_sha","timestamp_utc":"2026-03-01T00:00:01Z"}
JSON
cat > "$repo/.wf/receipts/$story/02_self_review.json" <<JSON
{"story_id":"$story","step_name":"self_review","step_index":2,"head_sha":"$head_sha","timestamp_utc":"2026-03-01T00:00:02Z"}
JSON

# Evidence-ledger fallback target for cycle1 readiness.
cat > "$repo/artifacts/story/$story/evidence_ledger.md" <<'LEDGER'
# Evidence Ledger
PATH: YELLOW
LEDGER

cycle1_artifact="$repo/artifacts/story/$story/codex/20260301_c1_review.md"
cat > "$cycle1_artifact" <<'C1'
Review basis: STORY_SCOPE
Phase equivalent: R3
artifact_provenance: "logger-v2"
FINDINGS_SUMMARY: P0=0 P1=0 P2=0
C1

set +e
cycle1_fail_out="$(cd "$repo" && bash plans/wf_step.sh "$story" cycle1 2>&1)"
cycle1_fail_rc=$?
set -e
[[ "$cycle1_fail_rc" -eq 3 ]] || fail "cycle1 should fail without provenance sidecar (exit 3), got $cycle1_fail_rc"
printf '%s\n' "$cycle1_fail_out" | grep -Fq "provenance sidecar missing" || fail "cycle1 missing provenance failure message"

write_sidecar "$cycle1_artifact" "R3" "STORY_SCOPE" "codex" "$story" "$head_sha"
(
  cd "$repo"
  bash plans/wf_step.sh "$story" cycle1 >/dev/null
)
[[ -f "$repo/.wf/receipts/$story/03_cycle1.json" ]] || fail "cycle1 receipt should be written after provenance-valid artifact"

# Seed fix receipt so cycle2 can run.
cat > "$repo/.wf/receipts/$story/04_fix.json" <<JSON
{"story_id":"$story","step_name":"fix","step_index":4,"head_sha":"$head_sha","timestamp_utc":"2026-03-01T00:00:03Z","code_changed":true}
JSON

cycle2_artifact="$repo/artifacts/story/$story/sonnet/20260301_c2_review.md"
cat > "$cycle2_artifact" <<'C2'
Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)
Phase equivalent: R7d
artifact_provenance: "logger-v2"
FINDINGS_SUMMARY: P0=0 P1=0 P2=0
C2

set +e
cycle2_fail_out="$(cd "$repo" && bash plans/wf_step.sh "$story" cycle2 2>&1)"
cycle2_fail_rc=$?
set -e
[[ "$cycle2_fail_rc" -eq 3 ]] || fail "cycle2 should fail when only one provenance-valid artifact exists"
printf '%s\n' "$cycle2_fail_out" | grep -Fq "provenance-valid review artifacts" || fail "cycle2 missing provenance-count failure message"

write_sidecar "$cycle2_artifact" "R7d" "FIX_DIFF_AT_REGRESSION" "sonnet" "$story" "$head_sha"
(
  cd "$repo"
  bash plans/wf_step.sh "$story" cycle2 >/dev/null
)
[[ -f "$repo/.wf/receipts/$story/05_cycle2.json" ]] || fail "cycle2 receipt should be written with provenance-valid C1+C2 artifacts"

# Dual-combo mode must require R7d/R7-only review count; C1 (R3) artifacts do not count.
rm -f "$repo/.wf/receipts/$story/05_cycle2.json"
mkdir -p "$repo/artifacts/story/$story/external/cycle2/$story"
cat > "$repo/artifacts/story/$story/external/cycle2/$story/R7_EXTERNAL_MANIFEST.json" <<'MANIFEST'
{
  "cycle2_path": {
    "mode": "dual_combo"
  }
}
MANIFEST

set +e
dual_combo_fail_out="$(cd "$repo" && bash plans/wf_step.sh "$story" cycle2 2>&1)"
dual_combo_fail_rc=$?
set -e
[[ "$dual_combo_fail_rc" -eq 3 ]] || fail "dual_combo cycle2 should fail with only one R7d/R7 artifact, got $dual_combo_fail_rc"
printf '%s\n' "$dual_combo_fail_out" | grep -Fq "provenance-valid R7d (legacy R7 tolerated) review artifacts" || fail "dual_combo cycle2 missing R7d-count failure message"

second_cycle2_artifact="$repo/artifacts/story/$story/codex/20260301_c2_review.md"
cat > "$second_cycle2_artifact" <<'C2B'
Review basis: FIX_DIFF + AT_REGRESSION (Cycle 2)
Phase equivalent: R7d
artifact_provenance: "logger-v2"
FINDINGS_SUMMARY: P0=0 P1=0 P2=0
C2B
write_sidecar "$second_cycle2_artifact" "R7d" "FIX_DIFF_AT_REGRESSION" "codex" "$story" "$head_sha"

(
  cd "$repo"
  bash plans/wf_step.sh "$story" cycle2 >/dev/null
)
[[ -f "$repo/.wf/receipts/$story/05_cycle2.json" ]] || fail "dual_combo cycle2 receipt should be written after two R7d/R7 artifacts"

echo "test_wf_step_review_provenance.sh: ok"
