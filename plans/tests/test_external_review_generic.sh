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

setup_mock_env() {
  local name="$1"
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
printf '%s\n' "${PARALLEL_REVIEW_REVIEW_SCRIPT:-}" >> "$mock_root/parallel_review_script.log"

story_dir="$mock_root/artifacts/story/$run_id"
if [[ -n "${STORY_ARTIFACTS_ROOT:-}" ]]; then
  story_dir="$STORY_ARTIFACTS_ROOT/$run_id"
elif [[ "$PWD" != "$mock_root" ]]; then
  story_dir="$PWD/artifacts/story/$run_id"
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
  printf '{"number":190,"baseRefName":"%s","headRefOid":"%s"}\n' \
    "${MOCK_GH_BASE_REF:-main}" "${MOCK_GH_HEAD_OID:-abc123def456}"
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
  printf '%s\n' "${MOCK_WORKTREE_HEAD:-${MOCK_GH_HEAD_OID:-abc123def456}}"
  exit 0
fi

if [[ "${args[0]:-}" == "fetch" ]]; then
  exit 0
fi

if [[ "${args[0]:-}" == "worktree" && "${args[1]:-}" == "add" ]]; then
  worktree_path="${args[3]:?missing worktree path}"
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

escape_ere_literal() {
  local value="$1"
  python3 - "$value" <<'PY'
import re
import sys

print(re.escape(sys.argv[1]))
PY
}

assert_file_matches() {
  local file="$1"
  local pattern="$2"
  grep -Eq -- "$pattern" "$file" || fail "expected pattern '$pattern' in $file"
}

find_single_run_id() {
  local story_base="$1"
  local count
  count="$(find "$story_base" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  [[ "$count" == "1" ]] || fail "expected exactly one run dir under $story_base, found $count"
  find "$story_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \;
}

test_commit_mode_success() {
  setup_mock_env "commit_success"
  run_wrapper all_ok --commit HEAD >/dev/null || fail "commit mode should exit 0"

  local run_id
  run_id="$(find_single_run_id "$mock_root/artifacts/story")"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local status_json="$story_dir/external_review_generic/dispatch_status.json"
  local summary_md="$story_dir/external_review_generic/summary.md"

  [[ -d "$story_dir" ]] || fail "missing story dir for commit mode"
  [[ -f "$status_json" ]] || fail "missing dispatch status json"
  [[ -f "$summary_md" ]] || fail "missing summary md"
  [[ "$run_id" =~ ^external_review_generic_20260305T220000Z_commit_HEAD_[A-Za-z0-9_-]+$ ]] || fail "run id must be unique and shell-safe: $run_id"

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
  run_wrapper all_ok PR190 >/dev/null || fail "PR mode should exit 0"

  local run_id
  run_id="$(find_single_run_id "$mock_root/artifacts/story")"
  local story_dir="$mock_root/artifacts/story/$run_id"
  local status_json="$story_dir/external_review_generic/dispatch_status.json"
  local summary_md="$story_dir/external_review_generic/summary.md"

  assert_file_contains "$mock_root/gh.log" "pr view 190 --json number,baseRefName,headRefOid"
  assert_file_matches "$mock_root/git.log" 'fetch origin main pull/190/head:refs/tmp/external-review/pr-190-[A-Za-z0-9_-]+'
  assert_file_matches "$mock_root/git.log" "worktree add --detach $mock_root/.tmp/external-review/pr-190-[A-Za-z0-9_-]+ refs/tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_matches "$mock_root/git.log" "worktree remove --force $mock_root/.tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_matches "$mock_root/git.log" 'update-ref -d refs/tmp/external-review/pr-190-[A-Za-z0-9_-]+'
  assert_file_contains "$mock_root/parallel_args.log" "--base"
  assert_file_contains "$mock_root/parallel_args.log" "origin/main"
  assert_file_matches "$mock_root/parallel_pwd.log" "$mock_root/.tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_contains "$mock_root/parallel_review_script.log" "$mock_root/plans/review_logged.sh"
  assert_file_contains "$summary_md" "PR #190"
  assert_json_field "$status_json" 'data["resolved_head_oid"] == "abc123def456"'
  pass "PR mode resolves metadata, uses a detached temp worktree, and reviews against the resolved base"
}

test_reviewer_failure_preserves_summary() {
  setup_mock_env "reviewer_failure"
  set +e
  run_wrapper one_fail --commit HEAD >/dev/null
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "reviewer failure should exit non-zero"

  local run_id
  run_id="$(find_single_run_id "$mock_root/artifacts/story")"
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

  local run_id
  run_id="$(find_single_run_id "$mock_root/artifacts/story")"
  local summary_md="$mock_root/artifacts/story/$run_id/external_review_generic/summary.md"

  [[ -f "$summary_md" ]] || fail "summary should still be written on inconsistency"
  assert_file_contains "$summary_md" "gemini | FAIL | exit=0"
  assert_file_contains "$summary_md" "missing canonical artifact"
  pass "zero-exit reviewer without canonical artifact is treated as inconsistent"
}

test_pr_mode_head_oid_mismatch_fails_closed() {
  setup_mock_env "pr_head_mismatch"
  set +e
  mismatch_output="$(
    MOCK_GH_HEAD_OID="abc123def456" \
    MOCK_WORKTREE_HEAD="deadbeefcaf0" \
    run_wrapper all_ok PR190 2>&1
  )"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "PR mode head mismatch should exit non-zero"

  echo "$mismatch_output" | grep -Fq "resolved PR head OID mismatch" || fail "missing OID mismatch diagnostic"
  assert_file_matches "$mock_root/git.log" "worktree remove --force $(escape_ere_literal "$mock_root")/.tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_matches "$mock_root/git.log" 'update-ref -d refs/tmp/external-review/pr-190-[A-Za-z0-9_-]+'

  if [[ -d "$mock_root/artifacts/story" ]] && [[ -n "$(find "$mock_root/artifacts/story" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]]; then
    fail "OID mismatch should fail before creating review artifacts"
  fi
  pass "PR mode fails closed when fetched HEAD does not match resolved PR OID"
}

test_python2_fallback_rejected() {
  setup_mock_env "python2_only"
  cat > "$mock_bin/python3" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  cat > "$mock_bin/python" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "-c" ]]; then
  exit 1
fi
echo "unexpected python args: $*" >&2
exit 1
EOF
  chmod +x "$mock_bin/python3" "$mock_bin/python"
  set +e
  output="$(
    PATH="$mock_bin:/usr/bin:/bin" \
    run_wrapper all_ok --commit HEAD 2>&1
  )"
  rc=$?
  set -e
  [[ $rc -ne 0 ]] || fail "python2-style fallback should fail"
  echo "$output" | grep -Fq "python3.6+ is required" || fail "missing python version diagnostic"
  pass "python fallback requires Python 3.6+"
}

test_run_id_collision_avoided() {
  setup_mock_env "run_id_collision"
  run_wrapper all_ok --commit HEAD >/dev/null || fail "first commit run should exit 0"
  run_wrapper all_ok --commit HEAD >/dev/null || fail "second commit run should exit 0"

  local story_base="$mock_root/artifacts/story"
  local count
  count="$(find "$story_base" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
  [[ "$count" == "2" ]] || fail "expected two unique run dirs after same-second reruns, found $count"

  local first_run_id
  local second_run_id
  first_run_id="$(find "$story_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | sed -n '1p')"
  second_run_id="$(find "$story_base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | LC_ALL=C sort | sed -n '2p')"
  [[ -n "$first_run_id" && -n "$second_run_id" ]] || fail "expected two run ids"
  [[ "$first_run_id" != "$second_run_id" ]] || fail "same-second reruns must not reuse RUN_ID"
  [[ "$first_run_id" =~ ^external_review_generic_20260305T220000Z_commit_HEAD_[A-Za-z0-9_-]+$ ]] || fail "unexpected first run id format: $first_run_id"
  [[ "$second_run_id" =~ ^external_review_generic_20260305T220000Z_commit_HEAD_[A-Za-z0-9_-]+$ ]] || fail "unexpected second run id format: $second_run_id"
  pass "same-second reruns allocate distinct RUN_ID values"
}

test_commit_mode_success
test_files_mode_success
test_uncommitted_mode_success
test_pr_mode_resolution
test_reviewer_failure_preserves_summary
test_missing_success_artifact_is_inconsistent
test_pr_mode_head_oid_mismatch_fails_closed
test_python2_fallback_rejected
test_run_id_collision_avoided

echo "PASS: external_review_generic regression fixtures"
