#!/usr/bin/env bash
set -euo pipefail

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
mkdir -p "$repo/plans/tests" "$repo/specs"

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
exit 0
EOF
chmod +x "$repo/plans/tests/test_dummy_pass.sh"

write_pass_script() {
  local path="$1"
  cat > "$path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
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
  git add .
  git commit -qm "fixture"
)

printf '%s\n' "probe" > "$repo/plans/untracked_probe.txt"

verify_artifacts="$tmp_dir/verify_artifacts"
mkdir -p "$verify_artifacts"
run_log="$tmp_dir/preflight.log"
verify_artifacts_invalid="$tmp_dir/verify_artifacts_invalid"
mkdir -p "$verify_artifacts_invalid"
invalid_run_log="$tmp_dir/preflight_invalid.log"

(
  cd "$repo"
  VERIFY_ARTIFACTS_DIR="$verify_artifacts" \
  PREFLIGHT_FIXTURE_MODE=smoke \
  PREFLIGHT_PARALLEL_JOBS=3 \
  PREFLIGHT_FIXTURE_TEST_TIMEOUT=17 \
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
jq -e '.fixture_timeout_seconds == 17' "$diag" >/dev/null || fail "fixture_timeout_seconds mismatch"
jq -e '(.fixture_runtime_seconds | type) == "number"' "$diag" >/dev/null \
  || fail "fixture_runtime_seconds must be numeric"
jq -e '.cache_file == ".cache/preflight_fixtures_smoke.hash"' "$diag" >/dev/null \
  || fail "cache_file should be repo-relative"

grep -Fq \
  'preflight diagnostics: fixture_mode=smoke tests=1 cache=miss hash=fallback_scan reasons=scoped_untracked_files_present,cache_file_missing' \
  "$run_log" || fail "missing diagnostics summary line"

invalid_rc=0
(
  cd "$repo"
  VERIFY_ARTIFACTS_DIR="$verify_artifacts_invalid" \
  PREFLIGHT_FIXTURE_MODE=none \
  PREFLIGHT_PARALLEL_JOBS=oops \
  ./plans/preflight.sh >"$invalid_run_log" 2>&1
) || invalid_rc=$?

[[ "$invalid_rc" == "2" ]] || fail "expected invalid PREFLIGHT_PARALLEL_JOBS to exit 2, got $invalid_rc"

invalid_diag="$verify_artifacts_invalid/preflight_diagnostics.json"
[[ -f "$invalid_diag" ]] || fail "missing invalid-input diagnostics artifact"
jq -e '.parallel_jobs == 0' "$invalid_diag" >/dev/null || fail "invalid parallel_jobs should normalize to 0"
grep -Fq "Invalid PREFLIGHT_PARALLEL_JOBS='oops' (expected positive integer worker count)" "$invalid_run_log" \
  || fail "missing invalid parallel-jobs failure"

echo "PASS: preflight diagnostics artifact + summary"
