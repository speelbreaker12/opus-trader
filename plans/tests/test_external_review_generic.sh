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
  mock_root="$tmp_dir/$name/root"
  mock_bin="$tmp_dir/$name/bin"
  mock_worktree_add_mode=""
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
    write_artifact sonnet 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact kimi 0 2 0 crates/soldier_core/src/execution/dispatch_map.rs:30
    write_artifact gemini 1 0 0 crates/soldier_core/src/execution/dispatch_map.rs:40
    echo "[done] codex  exit=0  (1s)"
    echo "[done] sonnet  exit=0  (1s)"
    echo "[done] kimi  exit=0  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    ;;
  one_fail)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact sonnet 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact gemini 1 0 0 crates/soldier_core/src/execution/dispatch_map.rs:40
    mkdir -p "$story_dir/review_logs"
    printf 'kimi transport failure\n' > "$story_dir/review_logs/kimi.log"
    echo "[done] codex  exit=0  (1s)"
    echo "[done] sonnet  exit=0  (1s)"
    echo "[FAIL] kimi  exit=7  (1s)"
    echo "[done] gemini  exit=0  (1s)"
    exit 1
    ;;
  missing_artifact)
    write_artifact codex 0 1 0 crates/soldier_core/src/execution/dispatch_map.rs:10
    write_artifact sonnet 0 0 1 crates/soldier_core/src/execution/dispatch_map.rs:20
    write_artifact kimi 0 2 0 crates/soldier_core/src/execution/dispatch_map.rs:30
    mkdir -p "$story_dir/gemini"
    echo "[done] codex  exit=0  (1s)"
    echo "[done] sonnet  exit=0  (1s)"
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

setup_actual_parallel_repo() {
  local name="$1"
  local repo="$tmp_dir/$name/repo"
  mkdir -p "$repo/plans" "$repo/python/proof_graph"
  git init -q "$repo"
  git -C "$repo" config core.hooksPath /dev/null

  cp "$ROOT/plans/parallel_review.sh" "$repo/plans/parallel_review.sh"
  chmod +x "$repo/plans/parallel_review.sh"

  cat > "$repo/plans/review_logged.sh" <<'MOCK_REVIEW'
#!/usr/bin/env bash
set -euo pipefail

story="${1:?missing story id}"
shift

tool=""
prompt="generic"
proof_graph=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool) tool="${2:?missing tool}"; shift 2 ;;
    --prompt) prompt="${2:?missing prompt}"; shift 2 ;;
    --proof-graph) proof_graph=true; shift ;;
    --base|--commit|--files|--title|--timeout-seconds|--out-root) shift 2 ;;
    --uncommitted) shift ;;
    --) shift; break ;;
    *) shift ;;
  esac
done

out_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"
out_dir="$out_root/$story/$tool"
mkdir -p "$out_dir"

printf '# %s %s review\n' "$tool" "$prompt" > "$out_dir/$tool.$prompt.md"
printf 'FINDINGS_SUMMARY: P0=0 P1=0 P2=0\n'

if [[ "$proof_graph" == "true" ]]; then
  cat > "$out_dir/proof_graph.json" <<EOF
{"schema_version":"proof_graph.v1","story_id":"$story","tool":"$tool"}
EOF
fi

if [[ "${MOCK_REVIEW_FAIL_TOOL:-}" == "$tool" ]]; then
  echo "$tool transport failure" >&2
  exit 7
fi
MOCK_REVIEW

  cat > "$repo/plans/aggregate_proofs.sh" <<'MOCK_AGG'
#!/usr/bin/env bash
set -euo pipefail

story="${1:?missing story id}"
story_root="${STORY_ARTIFACTS_ROOT:?missing STORY_ARTIFACTS_ROOT}"
printf '%s\n' "$story_root" > "${MOCK_AGG_LOG:?missing aggregate log}"
printf '%s\n' "$story" >> "${MOCK_AGG_LOG:?missing aggregate log}"
[[ -f "$story_root/$story/proof_graph.json" ]] || {
  echo "missing base proof graph at $story_root/$story/proof_graph.json" >&2
  exit 9
}
exit 0
MOCK_AGG

  cat > "$repo/python/proof_graph/init.py" <<'MOCK_INIT'
#!/usr/bin/env python3
import json
import os
import sys

story_id = sys.argv[1]
output_dir = None
for i, arg in enumerate(sys.argv):
    if arg == "--output-dir":
        output_dir = sys.argv[i + 1]
        break
if output_dir is None:
    raise SystemExit("missing --output-dir")
os.makedirs(output_dir, exist_ok=True)
with open(os.path.join(output_dir, "proof_graph.json"), "w", encoding="utf-8") as handle:
    json.dump({"schema_version": "proof_graph.v1", "story_id": story_id}, handle)
MOCK_INIT

  chmod +x "$repo/plans/review_logged.sh" "$repo/plans/aggregate_proofs.sh" "$repo/python/proof_graph/init.py"
  printf '%s\n' "$repo"
}

test_python_candidate_must_be_python3_6_or_newer() {
  setup_mock_env "python_version_guard"

  cat > "$mock_bin/python3" <<'MOCK_PYTHON3'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-c" ]]; then
  exit 1
fi
exit 99
MOCK_PYTHON3

  cat > "$mock_bin/python" <<'MOCK_PYTHON'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-c" ]]; then
  exit 1
fi
exit 99
MOCK_PYTHON
  chmod +x "$mock_bin/python3" "$mock_bin/python"

  local output_file="$tmp_dir/python_guard.out"
  set +e
  PATH="$mock_bin:$PATH" \
  EXTERNAL_REVIEW_ROOT="$mock_root" \
  /bin/bash "$SCRIPT" --help >"$output_file" 2>&1
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "python candidate older than 3.6 should be rejected"
  assert_file_contains "$output_file" "python3.6+ is required"
  pass "find_python rejects python candidates that cannot satisfy Python 3.6+"
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
  assert_file_contains "$mock_root/parallel_args.log" "codex,sonnet,kimi,gemini"
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

test_help_text_warns_on_authority_and_scope() {
  local help_out="$tmp_dir/external_review_generic.help"
  "$SCRIPT" --help >"$help_out"

  assert_file_contains "$help_out" "Review the current tracked working-tree diff only."
  assert_file_contains "$help_out" "Untracked files are NOT auto-discovered in this mode."
  assert_file_contains "$help_out" "Convenience wrapper only. Not a workflow gate and not pass-authoritative."
  pass "help text warns that no-arg mode is tracked-only and not a workflow gate"
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
  assert_file_contains "$mock_root/parallel_args.log" "--review-script"
  assert_file_contains "$mock_root/parallel_args.log" "$mock_root/plans/review_logged.sh"
  assert_file_matches "$mock_root/parallel_pwd.log" "$mock_root/.tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_contains "$mock_root/parallel_review_script.log" "$mock_root/plans/review_logged.sh"
  assert_file_contains "$summary_md" "PR #190"
  assert_json_field "$status_json" 'data["resolved_head_oid"] == "abc123def456"'
  pass "PR mode resolves metadata, uses a detached temp worktree, and reviews against the resolved base"
}

test_pr_mode_uses_unique_temp_refs_per_run() {
  setup_mock_env "pr_unique_temp_names"
  run_wrapper all_ok PR190 >/dev/null || fail "first PR run should exit 0"
  run_wrapper all_ok PR190 >/dev/null || fail "second PR run should exit 0"

  local fetch_count add_count fetch_first fetch_second add_first add_second
  fetch_count="$(grep -F "fetch origin main pull/190/head:refs/tmp/external-review/" "$mock_root/git.log" | wc -l | tr -d ' ')"
  add_count="$(grep -F "worktree add --detach" "$mock_root/git.log" | wc -l | tr -d ' ')"
  fetch_first="$(grep -F "fetch origin main pull/190/head:refs/tmp/external-review/" "$mock_root/git.log" | sed -n '1p')"
  fetch_second="$(grep -F "fetch origin main pull/190/head:refs/tmp/external-review/" "$mock_root/git.log" | sed -n '2p')"
  add_first="$(grep -F "worktree add --detach" "$mock_root/git.log" | sed -n '1p')"
  add_second="$(grep -F "worktree add --detach" "$mock_root/git.log" | sed -n '2p')"

  [[ "$fetch_count" == "2" ]] || fail "expected two fetches for repeated PR runs"
  [[ "$add_count" == "2" ]] || fail "expected two worktree adds for repeated PR runs"
  [[ "$fetch_first" != "$fetch_second" ]] || fail "temp refs must be unique per run"
  [[ "$add_first" != "$add_second" ]] || fail "temp worktrees must be unique per run"
  pass "PR mode allocates unique temp refs and worktrees per run"
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

test_parallel_script_override_keeps_legacy_cli_contract() {
  setup_mock_env "parallel_override"

  cat > "$mock_root/custom_parallel.sh" <<'MOCK_OVERRIDE'
#!/usr/bin/env bash
set -euo pipefail

run_id="${1:?missing run id}"
shift

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tools|--prompt|--commit|--base|--files)
      shift 2
      ;;
    --uncommitted)
      shift
      ;;
    *)
      echo "unexpected arg: $1" >&2
      exit 99
      ;;
  esac
done

printf '%s\n' "${PARALLEL_REVIEW_REVIEW_SCRIPT:-}" > "${EXTERNAL_REVIEW_ROOT:?}/override_review_script.log"
story_dir="${STORY_ARTIFACTS_ROOT:?}/$run_id"
mkdir -p "$story_dir/codex" "$story_dir/sonnet" "$story_dir/kimi" "$story_dir/gemini"
for tool in codex sonnet kimi gemini; do
  cat > "$story_dir/$tool/$tool.generic.md" <<EOF
# $tool generic review
FINDINGS_SUMMARY: P0=0 P1=0 P2=0
EOF
  echo "[done] $tool  exit=0  (1s)"
done
MOCK_OVERRIDE

  chmod +x "$mock_root/custom_parallel.sh"

  EXTERNAL_REVIEW_PARALLEL_SCRIPT="$mock_root/custom_parallel.sh" \
    run_wrapper all_ok --commit HEAD >/dev/null || fail "parallel override should keep working without --review-script CLI support"

  assert_file_contains "$mock_root/override_review_script.log" "$mock_root/plans/review_logged.sh"
  if grep -Fq -- "--review-script" "$mock_root/parallel_args.log" 2>/dev/null; then
    fail "legacy parallel override should not receive --review-script"
  fi
  pass "parallel override uses environment-based review script routing without breaking legacy arg parsing"
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
  assert_file_matches "$mock_root/git.log" "worktree remove --force $mock_root/.tmp/external-review/pr-190-[A-Za-z0-9_-]+"
  assert_file_matches "$mock_root/git.log" 'update-ref -d refs/tmp/external-review/pr-190-[A-Za-z0-9_-]+'

  if [[ -d "$mock_root/artifacts/story" ]] && find "$mock_root/artifacts/story" -mindepth 1 -maxdepth 1 -type d | grep -q .; then
    fail "OID mismatch should fail before creating review artifacts"
  fi
  pass "PR mode fails closed when fetched HEAD does not match resolved PR OID"
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

test_parallel_review_failure_honors_story_artifacts_root() {
  local repo
  repo="$(setup_actual_parallel_repo "parallel_story_root_failure")"
  local custom_root="$repo/custom_story_root"

  set +e
  output="$(
    cd "$repo" && \
      PARALLEL_REVIEW_REVIEW_SCRIPT="$repo/plans/review_logged.sh" \
      STORY_ARTIFACTS_ROOT="$custom_root" \
      MOCK_REVIEW_FAIL_TOOL="kimi" \
      bash plans/parallel_review.sh S9-200 --tools codex,kimi --uncommitted --prompt generic 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -ne 0 ]] || fail "parallel_review reviewer failure should exit non-zero"
  [[ -f "$custom_root/S9-200/review_logs/kimi.log" ]] || fail "review logs should be copied under STORY_ARTIFACTS_ROOT"
  [[ ! -f "$repo/artifacts/story/S9-200/review_logs/kimi.log" ]] || fail "review logs should not fall back to repo artifacts root when STORY_ARTIFACTS_ROOT is set"
  echo "$output" | grep -Fq "$custom_root/S9-200/review_logs/" || fail "failure output should point at STORY_ARTIFACTS_ROOT review_logs path"
  pass "parallel_review failure logs honor STORY_ARTIFACTS_ROOT"
}

test_parallel_review_proof_graph_honors_story_artifacts_root() {
  local repo
  repo="$(setup_actual_parallel_repo "parallel_story_root_proof_graph")"
  local custom_root="$repo/custom_story_root"
  local agg_log="$repo/aggregate.log"

  set +e
  output="$(
    cd "$repo" && \
      PARALLEL_REVIEW_REVIEW_SCRIPT="$repo/plans/review_logged.sh" \
      STORY_ARTIFACTS_ROOT="$custom_root" \
      MOCK_AGG_LOG="$agg_log" \
      bash plans/parallel_review.sh S9-201 --tools sonnet --files "plans/review_logged.sh" --prompt enriched --proof-graph 2>&1
  )"
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "parallel_review proof-graph run should succeed, got rc=$rc output=$output"
  [[ -f "$custom_root/S9-201/proof_graph.json" ]] || fail "base proof graph should be initialized under STORY_ARTIFACTS_ROOT"
  [[ ! -f "$repo/artifacts/story/S9-201/proof_graph.json" ]] || fail "base proof graph should not be initialized under default artifacts root when STORY_ARTIFACTS_ROOT is set"
  [[ -f "$agg_log" ]] || fail "mock aggregate script should run"
  assert_file_contains "$agg_log" "$custom_root"
  assert_file_contains "$agg_log" "S9-201"
  pass "parallel_review proof-graph paths honor STORY_ARTIFACTS_ROOT"
}

test_parallel_review_artifact_summary_uses_story_artifacts_root() {
  local fixture_dir="$tmp_dir/parallel_review_artifact_root"
  local repo="$fixture_dir/repo"
  local output_file="$fixture_dir/parallel_review.out"
  mkdir -p "$repo/plans" "$repo/.tmp/run" "$repo/canonical/story"
  git init -q "$repo"
  git -C "$repo" config core.hooksPath /dev/null

  cp "$ROOT/plans/parallel_review.sh" "$repo/plans/parallel_review.sh"
  chmod +x "$repo/plans/parallel_review.sh"

  cat > "$repo/plans/review_logged.sh" <<'MOCK_REVIEW'
#!/usr/bin/env bash
set -euo pipefail

story="${1:?missing story id}"
shift

tool=""
prompt="enriched"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      tool="${2:?missing tool}"
      shift 2
      ;;
    --prompt)
      prompt="${2:?missing prompt}"
      shift 2
      ;;
    --base|--commit|--files|--timeout-seconds|--out-root|--title)
      shift 2
      ;;
    --uncommitted|--proof-graph)
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$tool" ]] || exit 2

story_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"
if [[ "$story_root" != /* ]]; then
  story_root="$PWD/$story_root"
fi

outdir="$story_root/$story/$tool"
mkdir -p "$outdir"
cat > "$outdir/$tool.$prompt.md" <<EOF
# $tool review
FINDINGS_SUMMARY: P0=0 P1=1 P2=0
EOF
MOCK_REVIEW

  chmod +x "$repo/plans/review_logged.sh"

  set +e
  (
    cd "$repo/.tmp/run"
    # Unset git hook env vars so fixture-repo git commands resolve correctly.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
    STORY_ARTIFACTS_ROOT="$repo/canonical/story" \
      bash "$repo/plans/parallel_review.sh" S9-ART --base main --tools codex,sonnet --prompt generic --review-script "$repo/plans/review_logged.sh"
  ) >"$output_file" 2>&1
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "parallel_review should succeed with canonical artifact root override"
  [[ -f "$repo/canonical/story/S9-ART/codex/codex.generic.md" ]] || fail "missing codex artifact in canonical root"
  [[ -f "$repo/canonical/story/S9-ART/sonnet/sonnet.generic.md" ]] || fail "missing sonnet artifact in canonical root"
  assert_file_contains "$output_file" "canonical/story/S9-ART/codex/codex.generic.md"
  assert_file_contains "$output_file" "canonical/story/S9-ART/sonnet/sonnet.generic.md"
  if grep -Fq "not found — review may have failed" "$output_file"; then
    fail "artifact summary should not report canonical artifacts as missing"
  fi
  pass "parallel_review artifact summary follows STORY_ARTIFACTS_ROOT"
}

test_parallel_review_proof_aggregation_uses_story_artifacts_root() {
  local fixture_dir="$tmp_dir/parallel_review_proof_root"
  local repo="$fixture_dir/repo"
  local output_file="$fixture_dir/parallel_review_proof.out"
  local aggregate_log="$fixture_dir/aggregate_root.log"
  mkdir -p "$repo/plans" "$repo/.tmp/run" "$repo/canonical/story/S9-PG"
  git init -q "$repo"
  git -C "$repo" config core.hooksPath /dev/null

  cp "$ROOT/plans/parallel_review.sh" "$repo/plans/parallel_review.sh"
  chmod +x "$repo/plans/parallel_review.sh"

  cat > "$repo/plans/review_logged.sh" <<'MOCK_REVIEW'
#!/usr/bin/env bash
set -euo pipefail

story="${1:?missing story id}"
shift

tool=""
prompt="enriched"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      tool="${2:?missing tool}"
      shift 2
      ;;
    --prompt)
      prompt="${2:?missing prompt}"
      shift 2
      ;;
    --base|--commit|--files|--timeout-seconds|--out-root|--title)
      shift 2
      ;;
    --uncommitted|--proof-graph)
      shift
      ;;
    --)
      shift
      break
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$tool" ]] || exit 2

story_root="${STORY_ARTIFACTS_ROOT:?}"
outdir="$story_root/$story/$tool"
mkdir -p "$outdir"
cat > "$outdir/$tool.$prompt.md" <<EOF
# $tool review
FINDINGS_SUMMARY: P0=0 P1=0 P2=0
EOF
MOCK_REVIEW

cat > "$repo/plans/aggregate_proofs.sh" <<'MOCK_AGG'
#!/usr/bin/env bash
set -euo pipefail

story="${1:?missing story id}"
printf '%s\n' "${STORY_ARTIFACTS_ROOT:-}" > "${MOCK_AGGREGATE_LOG:?}"
[[ "${STORY_ARTIFACTS_ROOT:-}" == "${MOCK_EXPECTED_AGGREGATE_ROOT:?}" ]] || {
  echo "wrong aggregate root: ${STORY_ARTIFACTS_ROOT:-}" >&2
  exit 33
}
touch "${STORY_ARTIFACTS_ROOT}/$story/aggregate.ok"
MOCK_AGG

  chmod +x "$repo/plans/review_logged.sh" "$repo/plans/aggregate_proofs.sh"

  cat > "$repo/canonical/story/S9-PG/proof_graph.json" <<'EOF'
{"schema_version":2}
EOF

  set +e
  (
    cd "$repo/.tmp/run"
    # Unset git hook env vars so fixture-repo git commands resolve correctly.
    unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY
    STORY_ARTIFACTS_ROOT="$repo/canonical/story" \
    MOCK_AGGREGATE_LOG="$aggregate_log" \
    MOCK_EXPECTED_AGGREGATE_ROOT="$repo/canonical/story" \
      bash "$repo/plans/parallel_review.sh" S9-PG --base main --tools codex --prompt generic --review-script "$repo/plans/review_logged.sh" --proof-graph
  ) >"$output_file" 2>&1
  rc=$?
  set -e

  [[ $rc -eq 0 ]] || fail "parallel_review should propagate custom artifact root into aggregate_proofs.sh"
  assert_file_contains "$aggregate_log" "$repo/canonical/story"
  [[ -f "$repo/canonical/story/S9-PG/aggregate.ok" ]] || fail "aggregate_proofs should run against the custom story-artifacts root"
  pass "parallel_review propagates STORY_ARTIFACTS_ROOT into proof aggregation"
}

test_commit_mode_success
test_files_mode_success
test_uncommitted_mode_success
test_python_candidate_must_be_python3_6_or_newer
test_help_text_warns_on_authority_and_scope
test_pr_mode_resolution
test_pr_mode_uses_unique_temp_refs_per_run
test_pr_mode_worktree_add_failure_does_not_remove_uncreated_checkout
test_parallel_script_override_keeps_legacy_cli_contract
test_reviewer_failure_preserves_summary
test_missing_success_artifact_is_inconsistent
test_pr_mode_head_oid_mismatch_fails_closed
test_run_id_collision_avoided
test_parallel_review_failure_honors_story_artifacts_root
test_parallel_review_proof_graph_honors_story_artifacts_root
test_parallel_review_artifact_summary_uses_story_artifacts_root
test_parallel_review_proof_aggregation_uses_story_artifacts_root

echo "PASS: external_review_generic regression fixtures"
