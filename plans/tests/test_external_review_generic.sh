#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/external_review_generic.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mock_root=""
mock_bin=""
mock_worktree_add_mode=""

setup_mock_env() {
  local name="$1"
  mock_worktree_add_mode="ok"
  mock_root="$tmp_dir/$name/root"
  mock_bin="$tmp_dir/$name/bin"
  mkdir -p "$mock_root/plans" "$mock_root/artifacts/story" "$mock_bin"

  cat > "$mock_root/plans/parallel_review.sh" <<'MOCK_PARALLEL'
#!/usr/bin/env bash
set -euo pipefail

mock_root="${EXTERNAL_REVIEW_ROOT:?}"
scenario="${MOCK_PARALLEL_SCENARIO:-all_ok}"
run_id="${1:?missing run id}"
shift

printf '%s\n' "$PWD" >> "$mock_root/parallel_pwd.log"
printf '%s\n' "$run_id" "$@" > "$mock_root/parallel_args.log"
printf '%s\n' "${PARALLEL_REVIEW_REVIEW_SCRIPT:-}" > "$mock_root/parallel_review_script.log"

if [[ "$scenario" == "pr_artifacts_in_worktree" ]]; then
  story_dir="$PWD/artifacts/story/$run_id"
else
  story_dir="$mock_root/artifacts/story/$run_id"
fi
mkdir -p "$story_dir"

write_artifact() {
  local tool="$1"
  local p0="$2"
  local p1="$3"
  local p2="$4"
  local citation="$5"
  local outdir="$story_dir/$tool"
  mkdir -p "$outdir"
  cat > "$outdir/$tool.generic.md" <<EOF
# $tool generic review
- [P1] ${tool} blocking finding
$citation
FINDINGS_SUMMARY: P0=$p0 P1=$p1 P2=$p2
EOF
}

case "$scenario" in
  all_ok)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact opus 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact kimi 0 2 0 crates/soldier_core/src/execution/dispatch_map.rs:30
    write_artifact gemini 1 0 0 crates/soldier_core/src/execution/dispatch_map.rs:40
    echo "[done] codex  exit=0  (1s)"
    echo "[done] opus  exit=0  (1s)"
    echo "[done] kimi  exit=0  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    ;;
  one_fail)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact opus 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact gemini 1 0 0 crates/soldier_core/src/execution/dispatch_map.rs:40
    mkdir -p "$story_dir/review_logs"
    printf 'kimi transport failure\n' > "$story_dir/review_logs/kimi.log"
    echo "[done] codex  exit=0  (1s)"
    echo "[done] opus  exit=0  (1s)"
    echo "[FAIL] kimi  exit=7  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    exit 1
    ;;
  missing_artifact)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact opus 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact kimi 0 2 0 crates/soldier_core/src/execution/dispatch_map.rs:30
    mkdir -p "$story_dir/gemini"
    echo "[done] codex  exit=0  (1s)"
    echo "[done] opus  exit=0  (1s)"
    echo "[done] kimi  exit=0  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    ;;
  pr_artifacts_in_worktree)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact opus 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact kimi 0 2 0 crates/soldier_core/src/execution/dispatch_map.rs:30
    write_artifact gemini 1 0 0 crates/soldier_core/src/execution/dispatch_map.rs:40
    echo "[done] codex  exit=0  (1s)"
    echo "[done] opus  exit=0  (1s)"
    echo "[done] kimi  exit=0  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    ;;
  *)
    echo "unknown scenario: $scenario" >&2
    exit 99
    ;;
esac

exit 0
MOCK_PARALLEL

  cat > "$mock_bin/gh" <<'MOCK_GH'
#!/usr/bin/env bash
set -euo pipefail
mock_root="${EXTERNAL_REVIEW_ROOT:?}"
printf '%s\n' "$*" >> "$mock_root/gh.log"
if [[ "${1:-}" == "pr" && "${2:-}" == "view" ]]; then
  cat <<'EOF'
{"number":190,"baseRefName":"main","headRefOid":"abc123def456"}
EOF
  exit 0
fi
echo "unexpected gh args: $*" >&2
exit 1
MOCK_GH

  cat > "$mock_bin/git" <<'MOCK_GIT'
#!/usr/bin/env bash
set -euo pipefail
mock_root="${EXTERNAL_REVIEW_ROOT:?}"
printf '%s\n' "$*" >> "$mock_root/git.log"

args=("$@")
if [[ "${args[0]:-}" == "-C" ]]; then
  args=("${args[@]:2}")
fi

if [[ "${args[0]:-}" == "rev-parse" && "${args[1]:-}" == "--show-toplevel" ]]; then
  printf '%s\n' "$mock_root"
  exit 0
fi

if [[ "${args[0]:-}" == "rev-parse" && "${args[1]:-}" == "HEAD" ]]; then
  printf '%s\n' "${MOCK_GIT_HEAD_OID:-abc123def456}"
  exit 0
fi

if [[ "${args[0]:-}" == "rev-parse" && $# -ge 1 ]]; then
  printf '%s\n' "${MOCK_GIT_HEAD_OID:-abc123def456}"
  exit 0
fi

if [[ "${args[0]:-}" == "fetch" ]]; then
  exit 0
fi

if [[ "${args[0]:-}" == "worktree" && "${args[1]:-}" == "add" ]]; then
  worktree_path="${args[3]:?missing worktree path}"
  case "${MOCK_GIT_WORKTREE_ADD_MODE:-ok}" in
    fail)
      echo "mock worktree add failure" >&2
      exit 1
      ;;
    ok)
      ;;
    *)
      echo "unknown MOCK_GIT_WORKTREE_ADD_MODE: ${MOCK_GIT_WORKTREE_ADD_MODE:-}" >&2
      exit 88
      ;;
  esac
  mkdir -p "$worktree_path"
  exit 0
fi

if [[ "${args[0]:-}" == "worktree" && "${args[1]:-}" == "remove" ]]; then
  exit 0
fi

if [[ "${args[0]:-}" == "update-ref" && "${args[1]:-}" == "-d" ]]; then
  exit 0
fi

echo "unexpected git args: ${args[*]}" >&2
exit 1
MOCK_GIT

  chmod +x "$mock_root/plans/parallel_review.sh" "$mock_bin/gh" "$mock_bin/git"
}

run_wrapper() {
  local scenario="$1"
  shift
  local output_file="$tmp_dir/run.out"
  local had_errexit=0
  case "$-" in
    *e*) had_errexit=1 ;;
  esac
  : > "$output_file"
  set +e
  PATH="$mock_bin:$PATH" \
  EXTERNAL_REVIEW_ROOT="$mock_root" \
  EXTERNAL_REVIEW_NOW_UTC="20260305T220000Z" \
  MOCK_PARALLEL_SCENARIO="$scenario" \
  MOCK_GIT_WORKTREE_ADD_MODE="${mock_worktree_add_mode:-ok}" \
  "$SCRIPT" "$@" >"$output_file" 2>&1
  rc=$?
  if [[ "$had_errexit" -eq 1 ]]; then
    set -e
  else
    set +e
  fi
  cat "$output_file"
  return "$rc"
}

assert_json_field() {
  local file="$1"
  local expr="$2"
  python3 - "$file" "$expr" <<'PY'
import json
import sys

path = sys.argv[1]
expr = sys.argv[2]
with open(path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

safe_builtins = {"all": all, "any": any, "len": len}
result = eval(expr, {"__builtins__": safe_builtins}, {"data": data})
if not result:
    raise SystemExit(1)
PY
}

assert_file_contains() {
  local file="$1"
  local pattern="$2"
  grep -Fq -- "$pattern" "$file" || fail "expected '$pattern' in $file"
}

assert_file_lacks() {
  local file="$1"
  local pattern="$2"
  if grep -Fq -- "$pattern" "$file"; then
    fail "did not expect '$pattern' in $file"
  fi
}

test_commit_mode_success() {
  setup_mock_env "commit_success"
  run_wrapper all_ok --commit HEAD >/dev/null || fail "commit mode should exit 0"

  local run_id="external_review_generic_20260305T220000Z_commit_HEAD"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local status_json="$story_dir/external_review_generic/dispatch_status.json"
  local summary_md="$story_dir/external_review_generic/summary.md"

  [[ -d "$story_dir" ]] || fail "missing story dir for commit mode"
  [[ -f "$status_json" ]] || fail "missing dispatch status json"
  [[ -f "$summary_md" ]] || fail "missing summary md"
  [[ "$run_id" =~ ^[A-Za-z0-9_-]+$ ]] || fail "run id must be shell-safe: $run_id"

  assert_file_contains "$mock_root/parallel_args.log" "--commit"
  assert_file_contains "$mock_root/parallel_args.log" "HEAD"
  assert_json_field "$status_json" 'data["parallel_review_exit"] == 0'
  assert_json_field "$status_json" 'len(data["tools"]) == 4'
  assert_json_field "$status_json" 'all(item["exit_code"] == 0 for item in data["tools"])'
  assert_file_contains "$summary_md" "Target reviewed"
  assert_file_contains "$summary_md" "commit HEAD"
  assert_file_contains "$summary_md" "codex | OK | exit=0"
  assert_file_contains "$summary_md" "gemini | P0=1 P1=0 P2=0"
  pass "commit mode normalizes target, captures exit codes, and writes summary"
}

test_files_mode_success() {
  setup_mock_env "files_success"
  run_wrapper all_ok --files "plans/review_logged.sh plans/parallel_review.sh" >/dev/null || fail "files mode should exit 0"

  local story_base="$mock_root/artifacts/story"
  local run_id
  run_id="$(find "$story_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;)"
  [[ "$run_id" =~ ^[A-Za-z0-9_-]+$ ]] || fail "files mode run id must be shell-safe: $run_id"

  assert_file_contains "$mock_root/parallel_args.log" "--files"
  assert_file_contains "$mock_root/parallel_args.log" "plans/review_logged.sh plans/parallel_review.sh"
  pass "files mode passes explicit file list and safe run id"
}

test_uncommitted_mode_success() {
  setup_mock_env "uncommitted_success"
  run_wrapper all_ok >/dev/null || fail "uncommitted mode should exit 0"

  assert_file_contains "$mock_root/parallel_args.log" "--uncommitted"
  pass "no-arg mode reviews tracked uncommitted diff"
}

test_pr_mode_resolution() {
  setup_mock_env "pr_success"
  mock_worktree_add_mode="ok"
  run_wrapper all_ok PR190 >/dev/null || fail "PR mode should exit 0"

  local run_id="external_review_generic_20260305T220000Z_pr_190"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local summary_md="$story_dir/external_review_generic/summary.md"

  assert_file_contains "$mock_root/gh.log" "pr view 190 --json number,baseRefName,headRefOid"
  assert_file_contains "$mock_root/git.log" "fetch origin main pull/190/head:refs/tmp/external-review/pr-190-"
  assert_file_contains "$mock_root/git.log" "worktree add --detach $mock_root/.tmp/external-review/pr-190-"
  assert_file_contains "$mock_root/git.log" "worktree remove --force $mock_root/.tmp/external-review/pr-190-"
  assert_file_contains "$mock_root/git.log" "update-ref -d refs/tmp/external-review/pr-190-"
  assert_file_contains "$mock_root/parallel_args.log" "--base"
  assert_file_contains "$mock_root/parallel_args.log" "origin/main"
  assert_file_contains "$mock_root/parallel_pwd.log" "$mock_root/.tmp/external-review/pr-190-"
  assert_file_contains "$mock_root/parallel_review_script.log" "$mock_root/plans/review_logged.sh"
  assert_file_contains "$summary_md" "PR #190"
  pass "PR mode resolves metadata, uses a detached temp worktree, and reviews against the resolved base"
}

test_pr_mode_worktree_add_failure_does_not_remove_uncreated_checkout() {
  setup_mock_env "pr_worktree_add_failure"
  mock_worktree_add_mode="fail"

  set +e
  run_wrapper all_ok PR190 >/dev/null
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "PR mode should fail when detached worktree creation fails"
  assert_file_contains "$mock_root/git.log" "worktree add --detach"
  if grep -Fq "worktree remove --force" "$mock_root/git.log"; then
    fail "cleanup must not remove a worktree this process did not create"
  fi
  assert_file_contains "$mock_root/git.log" "update-ref -d refs/tmp/external-review/"
  pass "failed PR worktree creation does not remove an uncreated checkout"
}

test_pr_mode_copies_artifacts_from_temp_worktree() {
  setup_mock_env "pr_worktree_artifacts"
  run_wrapper pr_artifacts_in_worktree PR190 >/dev/null || fail "PR-mode worktree artifacts should be harvested into canonical storage"

  local run_id="external_review_generic_20260305T220000Z_pr_190"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local summary_md="$story_dir/external_review_generic/summary.md"

  [[ -f "$story_dir/codex/codex.generic.md" ]] || fail "expected codex artifact to be copied into canonical story dir"
  [[ -f "$story_dir/gemini/gemini.generic.md" ]] || fail "expected gemini artifact to be copied into canonical story dir"
  assert_file_contains "$summary_md" "codex | OK | exit=0"
  assert_file_lacks "$summary_md" "missing canonical artifact"
  pass "PR mode harvests reviewer artifacts from the detached review worktree before summarizing"
}

test_pr_mode_uses_unique_temp_refs_and_worktrees() {
  setup_mock_env "pr_unique_temp"
  run_wrapper all_ok PR190 >/dev/null || fail "first PR-mode run should exit 0"
  run_wrapper all_ok PR190 >/dev/null || fail "second PR-mode run should exit 0"

  local fetch_lines worktree_lines
  fetch_lines="$(grep 'fetch origin main pull/190/head:' "$mock_root/git.log" || true)"
  worktree_lines="$(grep 'worktree add --detach ' "$mock_root/git.log" || true)"

  local ref1 ref2 wt1 wt2
  ref1="$(printf '%s\n' "$fetch_lines" | sed -n '1s/.*pull\/190\/head:\(refs\/tmp\/external-review\/[^[:space:]]*\).*/\1/p')"
  ref2="$(printf '%s\n' "$fetch_lines" | sed -n '2s/.*pull\/190\/head:\(refs\/tmp\/external-review\/[^[:space:]]*\).*/\1/p')"
  wt1="$(printf '%s\n' "$worktree_lines" | sed -n '1s/.*worktree add --detach \([^[:space:]]*\.tmp\/external-review\/[^[:space:]]*\) .*/\1/p')"
  wt2="$(printf '%s\n' "$worktree_lines" | sed -n '2s/.*worktree add --detach \([^[:space:]]*\.tmp\/external-review\/[^[:space:]]*\) .*/\1/p')"

  [[ -n "$ref1" && -n "$ref2" ]] || fail "expected two fetched temp refs"
  [[ -n "$wt1" && -n "$wt2" ]] || fail "expected two temp worktree paths"
  [[ "$ref1" != "$ref2" ]] || fail "temp PR refs must be unique per run"
  [[ "$wt1" != "$wt2" ]] || fail "temp worktree paths must be unique per run"
  pass "PR mode isolates concurrent runs with unique temp refs and worktrees"
}

test_pr_mode_rejects_head_oid_mismatch() {
  setup_mock_env "pr_head_oid_mismatch"
  local output_file="$tmp_dir/pr_head_oid_mismatch.out"
  set +e
  PATH="$mock_bin:$PATH" \
  EXTERNAL_REVIEW_ROOT="$mock_root" \
  EXTERNAL_REVIEW_NOW_UTC="20260305T220000Z" \
  MOCK_PARALLEL_SCENARIO="all_ok" \
  MOCK_GIT_HEAD_OID="deadbeef" \
  "$SCRIPT" PR190 >"$output_file" 2>&1
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "PR mode should reject fetched head OID mismatches"
  grep -Fq "fetched PR head OID does not match GitHub metadata" "$output_file" || fail "missing head OID mismatch diagnostic"
  pass "PR mode verifies fetched PR head against GitHub metadata"
}

test_python3_requirement_is_explicit() {
  setup_mock_env "python_version_gate"
  cat > "$mock_bin/python" <<'MOCK_PY'
#!/usr/bin/env bash
set -euo pipefail
exit 1
MOCK_PY
  chmod +x "$mock_bin/python"

  local output_file="$tmp_dir/python_version_gate.out"
  set +e
  PATH="$mock_bin" \
  EXTERNAL_REVIEW_ROOT="$mock_root" \
  EXTERNAL_REVIEW_NOW_UTC="20260305T220000Z" \
  MOCK_PARALLEL_SCENARIO="all_ok" \
  /bin/bash "$SCRIPT" --commit HEAD >"$output_file" 2>&1
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "wrapper should fail when only a non-Python-3 'python' is available"
  grep -Fq "python3 (or python 3) is required" "$output_file" || fail "missing explicit Python 3 requirement diagnostic"
  pass "wrapper rejects Python 2 style fallbacks with a clear diagnostic"
}

test_reviewer_failure_preserves_summary() {
  setup_mock_env "reviewer_failure"
  set +e
  run_wrapper one_fail --commit HEAD >/dev/null
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "reviewer failure should exit non-zero"

  local run_id="external_review_generic_20260305T220000Z_commit_HEAD"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local status_json="$story_dir/external_review_generic/dispatch_status.json"
  local summary_md="$story_dir/external_review_generic/summary.md"

  [[ -f "$summary_md" ]] || fail "summary should exist even when a reviewer fails"
  assert_json_field "$status_json" 'any(item["tool"] == "kimi" and item["exit_code"] == 7 for item in data["tools"])'
  assert_file_contains "$summary_md" "kimi | FAIL | exit=7"
  assert_file_contains "$summary_md" "kimi | unavailable"
  assert_file_contains "$summary_md" "review_logs/kimi.log"
  pass "failed reviewer still produces authoritative status and partial summary"
}

test_missing_success_artifact_is_inconsistent() {
  setup_mock_env "missing_artifact"
  set +e
  run_wrapper missing_artifact --commit HEAD >/dev/null
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "missing artifact on successful exit should fail wrapper"

  local run_id="external_review_generic_20260305T220000Z_commit_HEAD"
  local summary_md="$mock_root/artifacts/story/$run_id/external_review_generic/summary.md"

  [[ -f "$summary_md" ]] || fail "summary should still be written on inconsistency"
  assert_file_contains "$summary_md" "gemini | FAIL | exit=0"
  assert_file_contains "$summary_md" "missing canonical artifact"
  pass "zero-exit reviewer without canonical artifact is treated as inconsistent"
}

test_commit_mode_success
test_files_mode_success
test_uncommitted_mode_success
test_pr_mode_resolution
test_pr_mode_worktree_add_failure_does_not_remove_uncreated_checkout
test_pr_mode_copies_artifacts_from_temp_worktree
test_pr_mode_uses_unique_temp_refs_and_worktrees
test_pr_mode_rejects_head_oid_mismatch
test_python3_requirement_is_explicit
test_reviewer_failure_preserves_summary
test_missing_success_artifact_is_inconsistent

echo "PASS: external_review_generic regression fixtures"
