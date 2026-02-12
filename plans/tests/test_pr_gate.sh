#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
GATE="$ROOT/plans/pr_gate.sh"

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

[[ -x "$GATE" ]] || fail "missing executable gate: $GATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fake_bin="$tmp_dir/fake_bin"
repo_dir="$tmp_dir/repo"
mkdir -p "$fake_bin" "$repo_dir/plans"

cp "$GATE" "$repo_dir/plans/pr_gate.sh"
chmod +x "$repo_dir/plans/pr_gate.sh"

cat > "$fake_bin/gh" <<'EOF_GH'
#!/usr/bin/env bash
set -euo pipefail

mode="${GH_MODE:-clean}"
head_sha="${GH_HEAD_SHA:-abc123}"
orig_sha="${GH_ORIG_SHA:-orig123}"
cmd="${1:-}"
sub="${2:-}"

if [[ "$cmd" == "pr" && "$sub" == "view" ]]; then
  if [[ "${3:-}" == "--json" && "${4:-}" == "number" ]]; then
    echo "17"
    exit 0
  fi

  case "$mode" in
    changes_requested) echo "CHANGES_REQUESTED" ;;
    review_unknown) echo "" ;;
    *) echo "APPROVED" ;;
  esac
  exit 0
fi

if [[ "$cmd" != "api" ]]; then
  echo "unsupported gh invocation: $*" >&2
  exit 2
fi

shift
jq_filter=""
endpoint=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --paginate)
      shift
      ;;
    --jq)
      jq_filter="${2:-}"
      shift 2
      ;;
    -H|--header)
      shift 2
      ;;
    *)
      if [[ -z "$endpoint" ]]; then
        endpoint="$1"
      fi
      shift
      ;;
  esac
done

[[ -n "$endpoint" ]] || { echo "missing gh api endpoint" >&2; exit 2; }

payload=""
case "$endpoint" in
  repos/acme/demo/pulls/17)
    if [[ "$mode" == "dirty_merge" ]]; then
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":false,"mergeable_state":"dirty","requested_reviewers":[]}
EOF_JSON
)"
    elif [[ "$mode" == "self_pending_check_blocked" ]]; then
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"blocked","requested_reviewers":[]}
EOF_JSON
)"
    elif [[ "$mode" == "blocked_no_self" ]]; then
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"blocked","requested_reviewers":[]}
EOF_JSON
)"
    elif [[ "$mode" == "copilot_requested_reviewer" ]]; then
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"clean","requested_reviewers":[{"login":"copilot-pull-request-reviewer[bot]","type":"Bot"}]}
EOF_JSON
)"
    elif [[ "$mode" == "unstable_merge" ]]; then
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"unstable","requested_reviewers":[]}
EOF_JSON
)"
    else
      payload="$(cat <<EOF_JSON
{"html_url":"https://github.com/acme/demo/pull/17","head":{"sha":"$head_sha"},"base":{"ref":"main"},"mergeable":true,"mergeable_state":"clean","requested_reviewers":[]}
EOF_JSON
)"
    fi
    ;;
  repos/acme/demo/pulls/17/reviews?per_page=100)
    case "$mode" in
      copilot_review_for_head)
        payload="$(cat <<EOF_JSON
[{"id":901,"commit_id":"$head_sha","state":"COMMENTED","user":{"login":"copilot-swe-agent","type":"Bot"}}]
EOF_JSON
)"
        ;;
      *)
        payload='[]'
        ;;
    esac
    ;;
  repos/acme/demo/commits/*/check-runs*)
    case "$mode" in
      pending_checks)
        payload="$(cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"in_progress","conclusion":null,"html_url":"https://example.invalid/check/1"}]}
EOF_JSON
)"
        ;;
      failing_checks)
        payload="$(cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"completed","conclusion":"failure","html_url":"https://example.invalid/check/1"}]}
EOF_JSON
)"
        ;;
      duplicate_checks)
        payload="$(cat <<'EOF_JSON'
{"check_runs":[{"id":1,"name":"verify","status":"completed","conclusion":"failure","completed_at":"2026-02-11T00:01:00Z","html_url":"https://example.invalid/check/1"},{"id":2,"name":"verify","status":"completed","conclusion":"success","completed_at":"2026-02-11T00:02:00Z","html_url":"https://example.invalid/check/2"}]}
EOF_JSON
)"
        ;;
      self_pending_check|self_pending_check_blocked)
        payload="$(cat <<'EOF_JSON'
{"check_runs":[{"id":1,"name":"verify","status":"completed","conclusion":"success","completed_at":"2026-02-11T00:02:00Z","html_url":"https://example.invalid/check/1"},{"id":2,"name":"pr-gate-enforced","status":"in_progress","conclusion":null,"started_at":"2026-02-11T00:03:00Z","html_url":"https://example.invalid/check/2"}]}
EOF_JSON
)"
        ;;
      fallback_pending|fallback_failure)
        exit 1
        ;;
      *)
        payload="$(cat <<'EOF_JSON'
{"check_runs":[{"name":"verify","status":"completed","conclusion":"success","html_url":"https://example.invalid/check/1"}]}
EOF_JSON
)"
        ;;
    esac
    ;;
  repos/acme/demo/commits/*/status)
    case "$mode" in
      fallback_pending)
        payload="$(cat <<'EOF_JSON'
{"state":"pending","statuses":[]}
EOF_JSON
)"
        ;;
      fallback_failure)
        payload="$(cat <<'EOF_JSON'
{"state":"failure","statuses":[]}
EOF_JSON
)"
        ;;
      *)
        payload="$(cat <<'EOF_JSON'
{"state":"success","statuses":[{"state":"success"}]}
EOF_JSON
)"
        ;;
    esac
    ;;
  repos/acme/demo/commits/*)
    payload="$(cat <<'EOF_JSON'
{"commit":{"committer":{"date":"2026-02-11T00:00:00Z"}}}
EOF_JSON
)"
    ;;
  repos/acme/demo/pulls/17/comments?per_page=100)
    case "$mode" in
      inline_unaddressed)
        payload="$(cat <<EOF_JSON
[{"created_at":"2026-02-11T00:05:00Z","html_url":"https://example.invalid/pr-comment/1","body":"Automated finding","path":"docs/unchanged.txt","original_commit_id":"$orig_sha","user":{"login":"copilot-swe-agent","type":"Bot"}}]
EOF_JSON
)"
        ;;
      inline_addressed|bot_comment)
        payload="$(cat <<EOF_JSON
[{"created_at":"2026-02-11T00:05:00Z","html_url":"https://example.invalid/pr-comment/2","body":"Automated finding","path":"README.md","original_commit_id":"$orig_sha","user":{"login":"copilot-swe-agent","type":"Bot"}}]
EOF_JSON
)"
        ;;
      *)
        payload='[]'
        ;;
    esac
    ;;
  repos/acme/demo/issues/17/comments?per_page=100)
    case "$mode" in
      issue_bot_no_ack)
        payload="$(cat <<'EOF_JSON'
[{"created_at":"2026-02-11T00:06:00Z","html_url":"https://example.invalid/issue-comment/1","body":"Bot finding","user":{"login":"copilot-review-bot","type":"Bot"}}]
EOF_JSON
)"
        ;;
      issue_bot_with_ack)
        payload="$(cat <<EOF_JSON
[{"created_at":"2026-02-11T00:06:00Z","html_url":"https://example.invalid/issue-comment/1","body":"Bot finding","user":{"login":"copilot-review-bot","type":"Bot"}},{"created_at":"2026-02-11T00:07:00Z","html_url":"https://example.invalid/issue-comment/2","body":"AFTERCARE_ACK: $head_sha","user":{"login":"maintainer","type":"User"}}]
EOF_JSON
)"
        ;;
      clean_with_ack)
        payload="$(cat <<EOF_JSON
[{"created_at":"2026-02-11T00:07:00Z","html_url":"https://example.invalid/issue-comment/2","body":"AFTERCARE_ACK: $head_sha","user":{"login":"maintainer","type":"User"}}]
EOF_JSON
)"
        ;;
      *)
        payload='[]'
        ;;
    esac
    ;;
  *)
    echo "unsupported gh api endpoint: $endpoint" >&2
    exit 2
    ;;
esac

if [[ -n "$jq_filter" ]]; then
  jq -c "$jq_filter" <<<"$payload"
else
  printf '%s\n' "$payload"
fi
EOF_GH
chmod +x "$fake_bin/gh"

git -C "$repo_dir" init -q
git -C "$repo_dir" config user.email "ci@example.com"
git -C "$repo_dir" config user.name "CI"
mkdir -p "$repo_dir/docs"
echo "fixture" > "$repo_dir/README.md"
echo "keep-me" > "$repo_dir/docs/unchanged.txt"
git -C "$repo_dir" add README.md docs/unchanged.txt
git -C "$repo_dir" commit -q -m "base fixture repo"
orig_sha="$(git -C "$repo_dir" rev-parse HEAD)"
echo "fixture-v2" > "$repo_dir/README.md"
git -C "$repo_dir" add README.md
git -C "$repo_dir" commit -q -m "head fixture repo"
head_sha="$(git -C "$repo_dir" rev-parse HEAD)"
git -C "$repo_dir" remote add origin "https://github.com/acme/demo.git"

# Case 1: auto-detected PR passes; new bot comments are warnings in default mode.
set +e
out_case1="$(
  cd "$repo_dir" && GH_MODE=inline_addressed GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --story S1 --artifacts-root "$tmp_dir/artifacts" 2>&1
)"
rc_case1=$?
set -e
[[ $rc_case1 -eq 0 ]] || fail "expected case1 to pass"
printf '%s\n' "$out_case1" | grep -Fq "OK: PR gate passed" || fail "case1 missing pass output"
printf '%s\n' "$out_case1" | grep -Fq "WARN: detected new bot/copilot comments since head commit" || fail "case1 missing warn-mode bot comment warning"

report_count="$(find "$tmp_dir/artifacts/S1/pr_gate" -type f -name '*_pr_gate.md' | wc -l | tr -d '[:space:]')"
[[ "$report_count" -eq 1 ]] || fail "expected one report artifact for case1"

# Case 2: merge conflicts/blocked state fail closed.
expect_fail "mergeable state dirty" "merge_conflict_or_blocked: mergeable_state=dirty" \
  bash -lc "cd '$repo_dir' && GH_MODE=dirty_merge GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 3: unstable mergeable_state does not block when mergeable=true.
set +e
out_case3="$(
  cd "$repo_dir" && GH_MODE=unstable_merge GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 2>&1
)"
rc_case3=$?
set -e
[[ $rc_case3 -eq 0 ]] || fail "expected case3 to pass"
printf '%s\n' "$out_case3" | grep -Fq "OK: PR gate passed" || fail "case3 missing pass output"

# Case 4: duplicate check-run history resolves by latest run per check name.
set +e
out_case4="$(
  cd "$repo_dir" && GH_MODE=duplicate_checks GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 2>&1
)"
rc_case4=$?
set -e
[[ $rc_case4 -eq 0 ]] || fail "expected case4 to pass"
printf '%s\n' "$out_case4" | grep -Fq "OK: PR gate passed" || fail "case4 missing pass output"

# Case 5: pending checks fail.
expect_fail "checks pending" "checks_pending" \
  bash -lc "cd '$repo_dir' && GH_MODE=pending_checks GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 6: fallback commit status API must fail when top-level state is pending.
expect_fail "fallback pending state" "checks_pending" \
  bash -lc "cd '$repo_dir' && GH_MODE=fallback_pending GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 7: fallback commit status API must fail when top-level state is failure.
expect_fail "fallback failure state" "checks_failing" \
  bash -lc "cd '$repo_dir' && GH_MODE=fallback_failure GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 8: unknown review decision is warning-only in default mode.
set +e
out_case8="$(
  cd "$repo_dir" && GH_MODE=review_unknown GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 2>&1
)"
rc_case8=$?
set -e
[[ $rc_case8 -eq 0 ]] || fail "expected case8 to pass"
printf '%s\n' "$out_case8" | grep -Fq "reviewDecision is unknown but non-blocking in default mode" || fail "case8 missing unknown-review warning"

# Case 9: unknown review decision can be made blocking in strict mode.
expect_fail "unknown review decision strict mode" "review_decision_unknown" \
  bash -lc "cd '$repo_dir' && GH_MODE=review_unknown GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --require-known-review-decision"

# Case 10: story id path traversal must be rejected.
expect_fail "invalid story id" "invalid --story value: ../escape" \
  bash -lc "cd '$repo_dir' && GH_MODE=clean GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --story '../escape'"

# Case 11: inline bot review comments must be backed by file diffs.
expect_fail "inline bot comment unaddressed" "inline_bot_comments_unaddressed" \
  bash -lc "cd '$repo_dir' && GH_MODE=inline_unaddressed GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 12: issue bot comments require head-specific AFTERCARE_ACK.
expect_fail "missing aftercare ack" "missing_aftercare_ack_for_head" \
  bash -lc "cd '$repo_dir' && GH_MODE=issue_bot_no_ack GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

# Case 13: issue bot comments + valid ACK token pass.
set +e
out_case11="$(
  cd "$repo_dir" && GH_MODE=issue_bot_with_ack GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 2>&1
)"
rc_case11=$?
set -e
[[ $rc_case11 -eq 0 ]] || fail "expected case11 to pass"
printf '%s\n' "$out_case11" | grep -Fq "OK: PR gate passed" || fail "case11 missing pass output"

# Case 14: strict ACK mode blocks when no head-specific ACK exists.
expect_fail "strict ack missing" "missing_aftercare_ack_for_head" \
  bash -lc "cd '$repo_dir' && GH_MODE=clean GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --require-aftercare-ack"

# Case 15: strict ACK mode passes when HEAD-specific ACK exists without bot issue comments.
set +e
out_case15="$(
  cd "$repo_dir" && GH_MODE=clean_with_ack GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 --require-aftercare-ack 2>&1
)"
rc_case15=$?
set -e
[[ $rc_case15 -eq 0 ]] || fail "expected case15 to pass"
printf '%s\n' "$out_case15" | grep -Fq "OK: PR gate passed" || fail "case15 missing pass output"

# Case 16: self check-run pending can be ignored by name to avoid CI deadlocks.
set +e
out_case16="$(
  cd "$repo_dir" && GH_MODE=self_pending_check GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 --ignore-check-run-regex '^pr-gate-enforced$' 2>&1
)"
rc_case16=$?
set -e
[[ $rc_case16 -eq 0 ]] || fail "expected case16 to pass"
printf '%s\n' "$out_case16" | grep -Fq "OK: PR gate passed" || fail "case16 missing pass output"

# Case 17: mergeable_state=blocked + self pending check can still pass when self-check is ignored.
set +e
out_case17="$(
  cd "$repo_dir" && GH_MODE=self_pending_check_blocked GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 --ignore-check-run-regex '^pr-gate-enforced$' 2>&1
)"
rc_case17=$?
set -e
[[ $rc_case17 -eq 0 ]] || fail "expected case17 to pass"
printf '%s\n' "$out_case17" | grep -Fq "OK: PR gate passed" || fail "case17 missing pass output"
printf '%s\n' "$out_case17" | grep -Fq "mergeable_state=blocked ignored" || fail "case17 missing blocked-ignore warning"

# Case 18: mergeable_state=blocked must fail when no ignored pending check exists.
expect_fail "blocked mergeable state without ignored pending check" "merge_conflict_or_blocked: mergeable_state=blocked" \
  bash -lc "cd '$repo_dir' && GH_MODE=blocked_no_self GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --ignore-check-run-regex '^pr-gate-enforced$'"

# Case 19: warn-mode bot findings can be elevated to blocking mode.
expect_fail "bot comment blocking mode" "new_bot_comments_since_last_push" \
  bash -lc "cd '$repo_dir' && GH_MODE=inline_addressed GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --bot-comments-mode block"

# Case 20: opt-in Copilot requirement blocks when no Copilot signal is present.
expect_fail "copilot required pending" "copilot_review_pending" \
  bash -lc "cd '$repo_dir' && GH_MODE=clean GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17 --require-copilot-review"

# Case 21: opt-in Copilot requirement passes when PR review is tied to HEAD SHA.
set +e
out_case13="$(
  cd "$repo_dir" && GH_MODE=copilot_review_for_head GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 --require-copilot-review 2>&1
)"
rc_case13=$?
set -e
[[ $rc_case13 -eq 0 ]] || fail "expected case13 to pass"
printf '%s\n' "$out_case13" | grep -Fq "OK: PR gate passed" || fail "case13 missing pass output"

# Case 22: opt-in Copilot requirement passes when Copilot is a requested reviewer.
set +e
out_case21="$(
  cd "$repo_dir" && GH_MODE=copilot_requested_reviewer GH_HEAD_SHA="$head_sha" GH_ORIG_SHA="$orig_sha" PATH="$fake_bin:$PATH" ./plans/pr_gate.sh --pr 17 --require-copilot-review 2>&1
)"
rc_case21=$?
set -e
[[ $rc_case21 -eq 0 ]] || fail "expected case21 to pass"
printf '%s\n' "$out_case21" | grep -Fq "OK: PR gate passed" || fail "case21 missing pass output"

# Case 23: explicit changes requested is always blocking.
expect_fail "changes requested blocking" "changes_requested" \
  bash -lc "cd '$repo_dir' && GH_MODE=changes_requested GH_HEAD_SHA='$head_sha' GH_ORIG_SHA='$orig_sha' PATH='$fake_bin:$PATH' ./plans/pr_gate.sh --pr 17"

echo "PASS: pr_gate fixtures"
