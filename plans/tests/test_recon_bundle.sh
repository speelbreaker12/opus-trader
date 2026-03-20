#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/recon_bundle.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

expect_fail() {
  local label="$1"
  local pattern="$2"
  shift 2

  local output=""
  local rc=0
  set +e
  output="$("$@" 2>&1)"
  rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || fail "$label expected non-zero exit"
  printf '%s\n' "$output" | grep -Fq "$pattern" || fail "$label missing pattern '$pattern'"
}

copy_script_into_fixture() {
  local fixture_root="$1"
  mkdir -p "$fixture_root/plans"
  cp "$SCRIPT" "$fixture_root/plans/recon_bundle.sh"
  chmod +x "$fixture_root/plans/recon_bundle.sh"
}

build_fixture_repo() {
  local fixture_root="$1"

  mkdir -p "$fixture_root/reviews/reconciliations/S14"
  mkdir -p "$fixture_root/.wf/receipts/S14-001"
  mkdir -p "$fixture_root/.wf/recon_scope_lock"
  mkdir -p "$fixture_root/artifacts/story/S14-001"
  mkdir -p "$fixture_root/artifacts/verify/20260226_120000"

  cat > "$fixture_root/reviews/reconciliations/S14/S14-001_reconciliation.md" <<'EOF'
# S14-001 reconciliation
status: partial
EOF
  cat > "$fixture_root/reviews/reconciliations/S14/S14-001_reconciliation.json" <<'EOF'
{"schema_version":"review_receipt.v1","story_id":"S14-001"}
EOF
  cat > "$fixture_root/.wf/receipts/S14-001/00_preflight.json" <<'EOF'
{"story_id":"S14-001","step_name":"preflight"}
EOF
  cat > "$fixture_root/.wf/recon_scope_lock/S14-001.scope_lock.json" <<'EOF'
{"story_id":"S14-001","scope":"locked"}
EOF
  cat > "$fixture_root/artifacts/story/S14-001/proof_graph.json" <<'EOF'
{"schema_version":"proof_graph.v1","story_id":"S14-001"}
EOF
  cat > "$fixture_root/artifacts/verify/20260226_120000/verify.meta.json" <<'EOF'
{"schema_version":1,"run_id":"20260226_120000","mode":"full"}
EOF

  (
    cd "$fixture_root"
    git init -q
    git config core.hooksPath /dev/null
    git config user.name "Recon Bundle Test"
    git config user.email "recon-bundle-test@example.com"
    git add .
    git commit -qm "fixture"
  )
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture_repo="$tmp_dir/fixture_repo"
build_fixture_repo "$fixture_repo"
copy_script_into_fixture "$fixture_repo"

bundle_root="$tmp_dir/bundles"
bundle_id="S14_bundle_test"
bundle_dir="$bundle_root/$bundle_id"
manifest="$bundle_dir/bundle.manifest.json"

(
  cd "$fixture_repo"
  ./plans/recon_bundle.sh export \
    --slice S14 \
    --verify-run 20260226_120000 \
    --bundle-id "$bundle_id" \
    --out-root "$bundle_root"
)

[[ -d "$bundle_dir" ]] || fail "bundle directory not created: $bundle_dir"
[[ -f "$manifest" ]] || fail "manifest missing: $manifest"

jq -e '.schema_version == "recon_bundle.v1"' "$manifest" >/dev/null \
  || fail "manifest schema_version mismatch"
jq -e '.bundle_id == "S14_bundle_test"' "$manifest" >/dev/null \
  || fail "manifest bundle_id mismatch"
jq -e '.slice_id == "S14"' "$manifest" >/dev/null \
  || fail "manifest slice_id mismatch"
jq -e '.verify_run_id == "20260226_120000"' "$manifest" >/dev/null \
  || fail "manifest verify_run_id mismatch"
jq -e '.files | length > 0' "$manifest" >/dev/null \
  || fail "manifest files[] should not be empty"

manifest_paths="$(jq -r '.files[].path' "$manifest")"
sorted_paths="$(printf '%s\n' "$manifest_paths" | LC_ALL=C sort)"
[[ "$manifest_paths" == "$sorted_paths" ]] || fail "manifest files[] must be sorted by path"

while IFS= read -r rel_path; do
  [[ -n "$rel_path" ]] || continue
  [[ -f "$bundle_dir/payload/$rel_path" ]] || fail "payload file missing: $rel_path"
done <<< "$manifest_paths"

(
  cd "$fixture_repo"
  ./plans/recon_bundle.sh import --bundle "$bundle_dir" --dry-run
)

orig_recon_content="$(cat "$fixture_repo/reviews/reconciliations/S14/S14-001_reconciliation.md")"
echo "local drift" > "$fixture_repo/reviews/reconciliations/S14/S14-001_reconciliation.md"
(
  cd "$fixture_repo"
  ./plans/recon_bundle.sh import --bundle "$bundle_dir"
)
[[ "$(cat "$fixture_repo/reviews/reconciliations/S14/S14-001_reconciliation.md")" == "$orig_recon_content" ]] \
  || fail "import should restore payload content"

(
  cd "$fixture_repo"
  echo "head drift" > head_drift.txt
  git add head_drift.txt
  git commit -qm "head drift"
)
expect_fail "head mismatch blocks import" \
  "source_head_sha mismatch" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$bundle_dir' --dry-run"

(
  cd "$fixture_repo"
  ./plans/recon_bundle.sh import --bundle "$bundle_dir" --allow-head-mismatch --dry-run
)

tamper_dir="$tmp_dir/tamper_bundle"
cp -R "$bundle_dir" "$tamper_dir"
echo "tampered payload" > "$tamper_dir/payload/reviews/reconciliations/S14/S14-001_reconciliation.md"
expect_fail "checksum mismatch blocks import" \
  "checksum mismatch" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$tamper_dir' --allow-head-mismatch --dry-run"

missing_payload_dir="$tmp_dir/missing_payload_bundle"
cp -R "$bundle_dir" "$missing_payload_dir"
rm -f "$missing_payload_dir/payload/.wf/recon_scope_lock/S14-001.scope_lock.json"
expect_fail "missing payload blocks import" \
  "missing payload file" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$missing_payload_dir' --allow-head-mismatch --dry-run"

unsafe_dir="$tmp_dir/unsafe_bundle"
cp -R "$bundle_dir" "$unsafe_dir"
tmp_manifest="$unsafe_dir/bundle.manifest.json.tmp"
jq '.files[0].path = "../escape.txt"' "$unsafe_dir/bundle.manifest.json" > "$tmp_manifest"
mv "$tmp_manifest" "$unsafe_dir/bundle.manifest.json"
expect_fail "unsafe path blocks import" \
  "unsafe manifest path" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$unsafe_dir' --allow-head-mismatch --dry-run"

injection_probe="$tmp_dir/injection_probe"
rm -f "$injection_probe"
expect_fail "verify-run injection is rejected" \
  "invalid --verify-run" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh export --slice S14 --verify-run '.; touch $injection_probe; #' --bundle-id inj-verify-run --out-root '$tmp_dir/inj_out'"
[[ ! -f "$injection_probe" ]] || fail "verify-run injection probe should not execute"

expect_fail "bundle-id rejects unsafe characters" \
  "invalid --bundle-id" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh export --slice S14 --bundle-id 'bad id;rm' --out-root '$tmp_dir/bad_bundle_out'"

symlink_bundle="$tmp_dir/symlink_bundle"
mkdir -p "$symlink_bundle/payload"
outside_payload="$tmp_dir/outside_payload"
mkdir -p "$outside_payload/reconciliations/S14"
printf 'outside payload\n' > "$outside_payload/reconciliations/S14/pwn.txt"
ln -s "$outside_payload" "$symlink_bundle/payload/reviews"

symlink_sha="$(shasum -a 256 "$outside_payload/reconciliations/S14/pwn.txt" | awk '{print $1}')"
symlink_size="$(wc -c < "$outside_payload/reconciliations/S14/pwn.txt" | tr -d '[:space:]')"
fixture_head="$(git -C "$fixture_repo" rev-parse HEAD)"
jq -n \
  --arg schema_version "recon_bundle.v1" \
  --arg bundle_id "symlink-probe" \
  --arg slice_id "S14" \
  --arg source_head_sha "$fixture_head" \
  --arg created_at_utc "2026-02-26T00:00:00Z" \
  --arg path "reviews/reconciliations/S14/pwn.txt" \
  --arg sha256 "$symlink_sha" \
  --argjson size_bytes "$symlink_size" \
  '{
    schema_version: $schema_version,
    bundle_id: $bundle_id,
    slice_id: $slice_id,
    source_head_sha: $source_head_sha,
    created_at_utc: $created_at_utc,
    files: [
      {
        path: $path,
        sha256: $sha256,
        size_bytes: $size_bytes
      }
    ]
  }' > "$symlink_bundle/bundle.manifest.json"

expect_fail "symlinked payload path blocks import" \
  "payload path contains symlink component" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$symlink_bundle' --allow-head-mismatch --dry-run"

dest_symlink_target="$tmp_dir/destination_symlink_target"
mkdir -p "$dest_symlink_target"
rm -rf "$fixture_repo/reviews"
ln -s "$dest_symlink_target" "$fixture_repo/reviews"
expect_fail "destination symlink blocks non-dry-run import" \
  "destination path contains symlink component" \
  bash -lc "cd '$fixture_repo' && ./plans/recon_bundle.sh import --bundle '$bundle_dir' --allow-head-mismatch"

missing_scope_repo="$tmp_dir/missing_scope_repo"
build_fixture_repo "$missing_scope_repo"
copy_script_into_fixture "$missing_scope_repo"
rm -rf "$missing_scope_repo/.wf/recon_scope_lock"
expect_fail "missing required scope blocks export" \
  "missing required export scope" \
  bash -lc "cd '$missing_scope_repo' && ./plans/recon_bundle.sh export --slice S14 --bundle-id missing-scope --out-root '$tmp_dir/missing_scope_out'"

echo "PASS: recon_bundle export/import fail-closed coverage"
