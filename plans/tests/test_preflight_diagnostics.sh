#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SOURCE_PREFLIGHT="$ROOT/plans/preflight.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -f "$SOURCE_PREFLIGHT" ]] || fail "missing source preflight script: $SOURCE_PREFLIGHT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
repo="$tmp_dir/repo"
mkdir -p "$repo/plans/tests" "$repo/scripts" "$repo/specs"

cp "$SOURCE_PREFLIGHT" "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

rewrite_fixture_arrays() {
  local file="$1"
  local tmp_file="$file.tmp"
  awk '
    BEGIN {in_smoke=0; in_full=0}
    /^SMOKE_REVIEW_FIXTURE_TESTS=\(/ {
      print
      print "  \"plans/tests/test_dummy_pass.sh\""
      in_smoke=1
      next
    }
    in_smoke && /^\)/ {in_smoke=0; print; next}
    in_smoke {next}
    /^FULL_ONLY_REVIEW_FIXTURE_TESTS=\(/ {print; in_full=1; next}
    in_full && /^\)/ {in_full=0; print; next}
    in_full {next}
    {print}
  ' "$file" > "$tmp_file"
  mv "$tmp_file" "$file"
}

rewrite_fixture_arrays "$repo/plans/preflight.sh"
chmod +x "$repo/plans/preflight.sh"

cat > "$repo/plans/tests/test_dummy_pass.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
exit 0
EOF
chmod +x "$repo/plans/tests/test_dummy_pass.sh"

write_pass_script() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true
exit 0
EOF
  chmod +x "$path"
}

write_pass_script "$repo/plans/legacy_layout_guard.sh"
write_pass_script "$repo/plans/premortem_path_guard.sh"
write_pass_script "$repo/plans/readme_ci_parity_check.sh"
write_pass_script "$repo/plans/slice_completion_review_guard.sh"
write_pass_script "$repo/plans/story_review_findings_guard.sh"
write_pass_script "$repo/plans/stoic_cli_invariant_check.sh"
write_pass_script "$repo/plans/toggle_policy_check.sh"
write_pass_script "$repo/plans/prd_schema_check.sh"

cat > "$repo/scripts/check_skills_index.py" <<'EOF'
#!/usr/bin/env python3
raise SystemExit(0)
EOF
chmod +x "$repo/scripts/check_skills_index.py"

cat > "$repo/plans/prd.json" <<'EOF'
{}
EOF
cat > "$repo/specs/CONTRACT.md" <<'EOF'
# Contract
EOF

(
  cd "$repo"
  git init -q
  git config user.name "fixture"
  git config user.email "fixture@example.com"
  git config core.hooksPath /dev/null
  git add .
  git commit -qm "fixture"
)

printf '%s\n' "probe" > "$repo/plans/untracked_probe.txt"

verify_artifacts="$tmp_dir/verify_artifacts"
mkdir -p "$verify_artifacts"
run_log="$tmp_dir/preflight.log"

(
  cd "$repo"
  VERIFY_ARTIFACTS_DIR="$verify_artifacts" \
  PREFLIGHT_FIXTURE_MODE=smoke \
  PREFLIGHT_PARALLEL_JOBS=3 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=45 \
  ./plans/preflight.sh >"$run_log" 2>&1
) || fail "preflight run failed"

diag="$verify_artifacts/preflight_diagnostics.json"
[[ -f "$diag" ]] || fail "missing preflight diagnostics artifact"

jq -e '.schema_version == 1' "$diag" >/dev/null || fail "schema_version mismatch"
jq -e '.fixture_mode == "smoke"' "$diag" >/dev/null || fail "fixture_mode mismatch"
jq -e '.fixture_test_count == 1' "$diag" >/dev/null || fail "fixture_test_count mismatch"
jq -e '.cache_state == "miss"' "$diag" >/dev/null || fail "cache_state mismatch"
jq -e '.hash_strategy == "fallback_scan"' "$diag" >/dev/null || fail "hash_strategy mismatch"
jq -e '.cache_reasons | index("scoped_untracked_files_present")' "$diag" >/dev/null \
  || fail "expected scoped_untracked_files_present reason"
jq -e '.cache_reasons | index("cache_file_missing")' "$diag" >/dev/null \
  || fail "expected cache_file_missing reason"
jq -e '.parallel_jobs == 3' "$diag" >/dev/null || fail "parallel_jobs mismatch"
jq -e '.fixture_timeout_seconds == 45' "$diag" >/dev/null || fail "fixture_timeout_seconds mismatch"
jq -e '(.fixture_runtime_seconds | type) == "number"' "$diag" >/dev/null \
  || fail "fixture_runtime_seconds must be numeric"
jq -e '.cache_file == ".cache/preflight_fixtures_smoke.hash"' "$diag" >/dev/null \
  || fail "cache_file should be repo-relative"

grep -Fq \
  'preflight diagnostics: fixture_mode=smoke tests=1 cache=miss hash=fallback_scan reasons=scoped_untracked_files_present,cache_file_missing' \
  "$run_log" || fail "missing diagnostics summary line"

full_verify_artifacts="$tmp_dir/verify_artifacts_full"
mkdir -p "$full_verify_artifacts"
full_run_log="$tmp_dir/preflight_full.log"

(
  cd "$repo"
  VERIFY_ARTIFACTS_DIR="$full_verify_artifacts" \
  PREFLIGHT_FIXTURE_MODE=full \
  PREFLIGHT_PARALLEL_JOBS=3 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=45 \
  ./plans/preflight.sh >"$full_run_log" 2>&1
) || fail "preflight full-mode run failed"

full_diag="$full_verify_artifacts/preflight_diagnostics.json"
[[ -f "$full_diag" ]] || fail "missing full-mode preflight diagnostics artifact"
jq -e '.fixture_mode == "full"' "$full_diag" >/dev/null || fail "full fixture_mode mismatch"
jq -e '.fixture_test_count == 1' "$full_diag" >/dev/null || fail "full fixture_test_count mismatch"
grep -Fq \
  'preflight diagnostics: fixture_mode=full tests=1 cache=miss hash=fallback_scan reasons=scoped_untracked_files_present,cache_file_missing' \
  "$full_run_log" || fail "missing full-mode diagnostics summary line"

echo "PASS: preflight diagnostics artifact + summary"
