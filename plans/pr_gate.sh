#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/pr_gate.sh --story <ID> [--pr <number>] [--wait] [--timeout-secs <n>] [--poll-secs <n>] [--artifacts-root <path>] [--bot-comments-mode <warn|block>] [--require-copilot-review] [--copilot-login-regex <regex>] [--copilot-wait-secs <n>] [--require-known-review-decision] [--require-aftercare-ack] [--ignore-check-run-regex <regex>]

What it checks (blocking):
  - PR mergeability is not blocked by conflicts (`mergeable=false` or blocked/dirty state)
  - All check-runs for PR head SHA are completed and successful
  - reviewDecision is not CHANGES_REQUESTED (known-decision requirement is optional)
  - Inline bot/copilot review comments are addressed by file changes after each comment's original commit
  - If bot/copilot issue comments exist, PR conversation includes: AFTERCARE_ACK: <HEAD_SHA>
    (or always, when --require-aftercare-ack / REQUIRE_AFTERCARE_ACK=1)

Bot/copilot comments:
  - Default mode is warn: new bot/copilot comments since head commit are printed as warnings only
  - Optional block mode: treat new bot/copilot comments as blocking

Copilot review (opt-in):
  - Disabled by default; enable with --require-copilot-review or REQUIRE_COPILOT_REVIEW=1
  - Signals accepted: review tied to HEAD SHA, requested Copilot reviewer, bot comment after HEAD commit time, or copilot-like check-run name
  - In --wait mode, missing signal times out after COPILOT_WAIT_SECS (default 600)

Review decision policy:
  - Default: unknown reviewDecision is warning-only
  - Optional strict mode: --require-known-review-decision or REQUIRE_KNOWN_REVIEW_DECISION=1

Check-run filtering:
  - Optional: ignore matching check-run names via --ignore-check-run-regex or PR_GATE_IGNORE_CHECK_RUN_REGEX
  - Useful when this gate runs as a GitHub check and should ignore its own in-progress run

No PR link required:
  - If --pr omitted, auto-detects PR for current branch via `gh pr view`.

Story binding (required):
  - --story is mandatory.
  - Story ID must be slash-free (`[A-Za-z0-9][A-Za-z0-9._-]*`).
  - PR head branch must match: story/<STORY_ID>[/<slug>] or story/<PRD_STORY_ID>-<slug> (legacy slug token cannot contain `-`).
  - This gate runs ./plans/pre_pr_review_gate.sh against PR HEAD and branch before pass.

Artifacts:
  - Writes a report under artifacts/story/<ID>/pr_gate/<ts>_pr_gate.md
USAGE
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

need() {
  command -v "$1" >/dev/null 2>&1 || die "missing required tool: $1"
}

need gh
need git
need jq

gh_api_array() {
  local endpoint="$1"
  local jq_filter="${2:-.[]}"
  local out=""
  set +e
  out="$(
    gh api --paginate "$endpoint" --jq "$jq_filter" 2>/dev/null | jq -s '.'
  )"
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] || return $rc
  printf '%s\n' "$out"
}

gh_api_check_runs() {
  local endpoint="$1"
  local out=""
  set +e
  out="$(
    gh api --paginate "$endpoint" --jq '.check_runs[]?' 2>/dev/null | jq -s '{check_runs: .}'
  )"
  local rc=$?
  set -e
  [[ $rc -eq 0 ]] || return $rc
  printf '%s\n' "$out"
}

validate_story_id() {
  local value="$1"
  if ! [[ "$value" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    die "invalid --story value: $value"
  fi
}

extract_story_from_head_ref() {
  local head_ref="$1"
  if [[ "$head_ref" =~ ^story/([A-Za-z0-9][A-Za-z0-9._-]*)(/[A-Za-z0-9._-]+)?$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$head_ref" =~ ^story/([A-Za-z0-9][A-Za-z0-9._-]*)-[A-Za-z0-9._]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

escape_regex() {
  printf '%s\n' "$1" | sed -e 's/[][(){}.^$*+?|\\]/\\&/g'
}

head_ref_matches_story() {
  local head_ref="$1"
  local story_id="$2"
  local escaped_story
  escaped_story="$(escape_regex "$story_id")"

  if [[ "$head_ref" =~ ^story/${escaped_story}(/([A-Za-z0-9._-]+))?$ ]]; then
    return 0
  fi
  if [[ "$head_ref" =~ ^story/${escaped_story}-[A-Za-z0-9._]+$ ]]; then
    return 0
  fi
  return 1
}

ensure_commit() {
  local sha="$1"
  if git cat-file -e "${sha}^{commit}" >/dev/null 2>&1; then
    return 0
  fi
  git fetch --quiet origin "$sha" >/dev/null 2>&1 || true
  git cat-file -e "${sha}^{commit}" >/dev/null 2>&1
}

PR=""
WAIT=0
TIMEOUT_SECS=900
POLL_SECS=15
STORY_ID=""
ART_ROOT=""
BOT_COMMENTS_MODE="${PR_GATE_BOT_COMMENT_MODE:-warn}"
REQUIRE_COPILOT_REVIEW="${REQUIRE_COPILOT_REVIEW:-0}"
COPILOT_LOGIN_REGEX="${COPILOT_LOGIN_REGEX:-copilot}"
COPILOT_WAIT_SECS="${COPILOT_WAIT_SECS:-600}"
REQUIRE_KNOWN_REVIEW_DECISION="${REQUIRE_KNOWN_REVIEW_DECISION:-0}"
REQUIRE_AFTERCARE_ACK="${REQUIRE_AFTERCARE_ACK:-0}"
IGNORE_CHECK_RUN_REGEX="${PR_GATE_IGNORE_CHECK_RUN_REGEX:-}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      PR="${2:?missing number}"
      shift 2
      ;;
    --wait)
      WAIT=1
      shift
      ;;
    --timeout-secs)
      TIMEOUT_SECS="${2:?missing n}"
      shift 2
      ;;
    --poll-secs)
      POLL_SECS="${2:?missing n}"
      shift 2
      ;;
    --story)
      STORY_ID="${2:?missing id}"
      shift 2
      ;;
    --artifacts-root)
      ART_ROOT="${2:?missing path}"
      shift 2
      ;;
    --bot-comments-mode)
      BOT_COMMENTS_MODE="${2:?missing mode}"
      shift 2
      ;;
    --require-copilot-review)
      REQUIRE_COPILOT_REVIEW=1
      shift
      ;;
    --copilot-login-regex)
      COPILOT_LOGIN_REGEX="${2:?missing regex}"
      shift 2
      ;;
    --copilot-wait-secs)
      COPILOT_WAIT_SECS="${2:?missing n}"
      shift 2
      ;;
    --require-known-review-decision)
      REQUIRE_KNOWN_REVIEW_DECISION=1
      shift
      ;;
    --require-aftercare-ack)
      REQUIRE_AFTERCARE_ACK=1
      shift
      ;;
    --ignore-check-run-regex)
      IGNORE_CHECK_RUN_REGEX="${2:?missing regex}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

case "$BOT_COMMENTS_MODE" in
  warn|block) ;;
  *) die "invalid --bot-comments-mode: $BOT_COMMENTS_MODE (expected warn|block)" ;;
esac
case "$REQUIRE_COPILOT_REVIEW" in
  0|1) ;;
  *) die "invalid REQUIRE_COPILOT_REVIEW: $REQUIRE_COPILOT_REVIEW (expected 0|1)" ;;
esac
case "$REQUIRE_KNOWN_REVIEW_DECISION" in
  0|1) ;;
  *) die "invalid REQUIRE_KNOWN_REVIEW_DECISION: $REQUIRE_KNOWN_REVIEW_DECISION (expected 0|1)" ;;
esac
case "$REQUIRE_AFTERCARE_ACK" in
  0|1) ;;
  *) die "invalid REQUIRE_AFTERCARE_ACK: $REQUIRE_AFTERCARE_ACK (expected 0|1)" ;;
esac
[[ "$COPILOT_WAIT_SECS" =~ ^[0-9]+$ ]] || die "invalid COPILOT_WAIT_SECS: $COPILOT_WAIT_SECS (expected integer seconds)"
if [[ -n "$IGNORE_CHECK_RUN_REGEX" ]]; then
  jq -n --arg re "$IGNORE_CHECK_RUN_REGEX" '"" | test($re)' >/dev/null 2>&1 || die "invalid --ignore-check-run-regex: $IGNORE_CHECK_RUN_REGEX"
fi

[[ -n "$STORY_ID" ]] || die "--story is required"
validate_story_id "$STORY_ID"

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$repo_root"

origin="$(git config --get remote.origin.url || true)"
[[ -n "$origin" ]] || die "missing remote.origin.url"

repo="${origin#git@github.com:}"
repo="${repo#https://github.com/}"
repo="${repo%.git}"
[[ "$repo" == */* ]] || die "failed to parse repo from origin: $origin"

# Auto-detect PR if not provided.
if [[ -z "$PR" ]]; then
  set +e
  PR="$(gh pr view --json number --jq '.number' 2>/dev/null)"
  rc=$?
  set -e
  [[ $rc -eq 0 && -n "$PR" ]] || die "no PR found for current branch (use --pr or create PR first)"
fi

ts="$(date -u +%Y%m%dT%H%M%SZ)"
root="${ART_ROOT:-${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}}"
[[ "$root" == /* ]] || root="$repo_root/$root"
outdir="$root/$STORY_ID/pr_gate"
mkdir -p "$outdir"
report_path="$outdir/${ts}_pr_gate.md"

PR_URL=""
HEAD_SHA=""
HEAD_REF=""
BASE_REF=""
MERGEABLE=""
MERGEABLE_STATE=""
REVIEW_DECISION=""
CHECK_SUMMARY=""
BOT_COMMENT_SUMMARY=""
INLINE_BOT_ENFORCEMENT_SUMMARY=""
AFTERCARE_ACK_SUMMARY=""
COPILOT_REVIEW_SUMMARY=""
PRE_PR_REVIEW_SUMMARY=""
HEAD_COMMIT_TIME=""
CHECK_PENDING="0"
CHECK_FAIL="0"
PRE_PR_CACHE_HEAD=""
PRE_PR_CACHE_REF=""
PRE_PR_CACHE_RC=""
PRE_PR_CACHE_OUTPUT=""
PRE_PR_CACHE_SUMMARY=""
MERGEABLE_BLOCKED_IGNORED=0
IGNORED_PENDING_CHECKS=0

write_report() {
  [[ -n "$report_path" ]] || return 0
  cat > "$report_path" <<EOF
# PR Gate Report

Timestamp (UTC): $ts
Repo: $repo
PR: $PR
Story ID: $STORY_ID
URL: $PR_URL

Head SHA: $HEAD_SHA
Head Ref: $HEAD_REF
Base: $BASE_REF
mergeable: $MERGEABLE
mergeable_state: $MERGEABLE_STATE
reviewDecision: $REVIEW_DECISION
bot_comments_mode: $BOT_COMMENTS_MODE
require_known_review_decision: $REQUIRE_KNOWN_REVIEW_DECISION
require_aftercare_ack: $REQUIRE_AFTERCARE_ACK
ignore_check_run_regex: ${IGNORE_CHECK_RUN_REGEX:-<none>}

## Check-runs
$CHECK_SUMMARY

## New bot/copilot comments since head commit
$BOT_COMMENT_SUMMARY

## Inline bot review comments enforcement
$INLINE_BOT_ENFORCEMENT_SUMMARY

## Issue bot comments ack enforcement
$AFTERCARE_ACK_SUMMARY

## Copilot review enforcement
$COPILOT_REVIEW_SUMMARY

## Pre-PR Review Gate
$PRE_PR_REVIEW_SUMMARY

EOF
}

start_epoch="$(date +%s)"

while true; do
  pr_json="$(gh api "repos/$repo/pulls/$PR")" || die "failed to fetch PR via gh api"

  PR_URL="$(jq -r '.html_url // ""' <<<"$pr_json")"
  HEAD_SHA="$(jq -r '.head.sha // ""' <<<"$pr_json")"
  HEAD_REF="$(jq -r '.head.ref // ""' <<<"$pr_json")"
  BASE_REF="$(jq -r '.base.ref // ""' <<<"$pr_json")"
  MERGEABLE="$(jq -r 'if .mergeable == null then "null" elif .mergeable then "true" else "false" end' <<<"$pr_json")"
  MERGEABLE_STATE="$(jq -r '.mergeable_state // "unknown"' <<<"$pr_json")"

  [[ -n "$PR_URL" && -n "$HEAD_SHA" && -n "$HEAD_REF" && -n "$BASE_REF" ]] || die "incomplete PR payload from GitHub API"

  # reviewDecision from gh pr view (GraphQL-backed).
  set +e
  REVIEW_DECISION="$(gh pr view "$PR" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)"
  set -e
  [[ -n "$REVIEW_DECISION" ]] || REVIEW_DECISION="UNKNOWN"

  commit_json="$(gh api "repos/$repo/commits/$HEAD_SHA")" || die "failed to fetch head commit"
  HEAD_COMMIT_TIME="$(jq -r '.commit.committer.date // ""' <<<"$commit_json")"
  [[ -n "$HEAD_COMMIT_TIME" ]] || die "missing head commit timestamp"

  set +e
  checks_json="$(gh_api_check_runs "repos/$repo/commits/$HEAD_SHA/check-runs?per_page=100")"
  checks_rc=$?
  set -e
  IGNORED_PENDING_CHECKS=0
  if [[ $checks_rc -ne 0 || -z "$checks_json" ]]; then
    status_json="$(gh api "repos/$repo/commits/$HEAD_SHA/status")" || die "failed to fetch commit status"
    CHECK_PENDING="$(jq '[.statuses[] | select(.state=="pending")] | length' <<<"$status_json")"
    CHECK_FAIL="$(jq '[.statuses[] | select(.state=="failure" or .state=="error")] | length' <<<"$status_json")"
    status_state="$(jq -r '.state // ""' <<<"$status_json")"
    if [[ "$status_state" == "pending" ]]; then
      CHECK_PENDING="$((CHECK_PENDING + 1))"
    fi
    if [[ "$status_state" == "failure" || "$status_state" == "error" ]]; then
      CHECK_FAIL="$((CHECK_FAIL + 1))"
    fi
    CHECK_SUMMARY="(fallback status API)
state=${status_state:-<missing>}
pending=$CHECK_PENDING
failing=$CHECK_FAIL"
  else
    if [[ -n "$IGNORE_CHECK_RUN_REGEX" ]]; then
      IGNORED_PENDING_CHECKS="$(
        jq --arg re "$IGNORE_CHECK_RUN_REGEX" '
          [
            (.check_runs // [])
            | sort_by((.name // ""), (.completed_at // .started_at // ""), (.id // 0))
            | group_by(.name // "")
            | map(last)[]
            | select(((.name // "") | test($re)) and (.status != "completed"))
          ] | length
        ' <<<"$checks_json"
      )"
    fi

    if [[ -n "$IGNORE_CHECK_RUN_REGEX" ]]; then
      checks_latest_json="$(
        jq --arg re "$IGNORE_CHECK_RUN_REGEX" '{
          check_runs: (
            (.check_runs // [])
            | map(select((((.name // "") | test($re)) | not)))
            | sort_by((.name // ""), (.completed_at // .started_at // ""), (.id // 0))
            | group_by(.name // "")
            | map(last)
          )
        }' <<<"$checks_json"
      )"
    else
      checks_latest_json="$(
        jq '{
          check_runs: (
            (.check_runs // [])
            | sort_by((.name // ""), (.completed_at // .started_at // ""), (.id // 0))
            | group_by(.name // "")
            | map(last)
          )
        }' <<<"$checks_json"
      )"
    fi
    CHECK_PENDING="$(jq '[.check_runs[] | select(.status != "completed")] | length' <<<"$checks_latest_json")"
    CHECK_FAIL="$(jq '[.check_runs[] | select(.status=="completed") | select(.conclusion != null) | select(.conclusion!="success" and .conclusion!="neutral" and .conclusion!="skipped")] | length' <<<"$checks_latest_json")"
    CHECK_SUMMARY="$(
      jq -r '
        (.check_runs // []) as $r
        | "total_unique_check_names=" + ([ $r[] ] | length | tostring)
        + "\npending=" + ([ $r[] | select(.status!="completed") ] | length | tostring)
        + "\nfailing=" + ([ $r[] | select(.status=="completed") | select(.conclusion!=null) | select(.conclusion!="success" and .conclusion!="neutral" and .conclusion!="skipped") ] | length | tostring)
        + "\n"
        + (
            [ $r[]
              | select(.status=="completed")
              | select(.conclusion!=null)
              | select(.conclusion!="success" and .conclusion!="neutral" and .conclusion!="skipped")
              | "- " + (.name // "unknown") + " (" + (.conclusion // "unknown") + "): " + (.html_url // "")
            ] | join("\n")
          )
      ' <<<"$checks_latest_json"
    )"
  fi

  pr_comments="$(gh_api_array "repos/$repo/pulls/$PR/comments?per_page=100")" || die "failed to fetch PR review comments"
  issue_comments="$(gh_api_array "repos/$repo/issues/$PR/comments?per_page=100")" || die "failed to fetch PR issue comments"
  copilot_seen=0
  copilot_reason="not_required"

  branch_story_id="$(extract_story_from_head_ref "$HEAD_REF" || true)"
  if [[ -n "$branch_story_id" ]]; then
    branch_story_match=1
    if head_ref_matches_story "$HEAD_REF" "$STORY_ID"; then
      branch_story_id="$STORY_ID"
    fi
  else
    branch_story_match=0
  fi

  if [[ "$HEAD_SHA" == "$PRE_PR_CACHE_HEAD" && "$HEAD_REF" == "$PRE_PR_CACHE_REF" && "$PRE_PR_CACHE_RC" == "0" ]]; then
    pre_pr_rc="$PRE_PR_CACHE_RC"
    pre_pr_output="$PRE_PR_CACHE_OUTPUT"
    PRE_PR_REVIEW_SUMMARY="$PRE_PR_CACHE_SUMMARY"
  else
    pre_pr_cmd=(
      "$repo_root/plans/pre_pr_review_gate.sh"
      "$STORY_ID"
      --head "$HEAD_SHA"
      --branch "$HEAD_REF"
      --artifacts-root "$root"
    )
    set +e
    pre_pr_output="$("${pre_pr_cmd[@]}" 2>&1)"
    pre_pr_rc=$?
    set -e
    if [[ "$pre_pr_rc" -eq 0 ]]; then
      PRE_PR_REVIEW_SUMMARY="pass"
    else
      PRE_PR_REVIEW_SUMMARY="fail (rc=$pre_pr_rc)\n$pre_pr_output"
    fi
    if [[ "$pre_pr_rc" -eq 0 ]]; then
      PRE_PR_CACHE_HEAD="$HEAD_SHA"
      PRE_PR_CACHE_REF="$HEAD_REF"
      PRE_PR_CACHE_RC="$pre_pr_rc"
      PRE_PR_CACHE_OUTPUT="$pre_pr_output"
      PRE_PR_CACHE_SUMMARY="$PRE_PR_REVIEW_SUMMARY"
    else
      PRE_PR_CACHE_HEAD=""
      PRE_PR_CACHE_REF=""
      PRE_PR_CACHE_RC=""
      PRE_PR_CACHE_OUTPUT=""
      PRE_PR_CACHE_SUMMARY=""
    fi
  fi

  if [[ "$REQUIRE_COPILOT_REVIEW" == "1" ]]; then
    reviews_json="$(gh_api_array "repos/$repo/pulls/$PR/reviews?per_page=100")" || die "failed to fetch PR reviews"
    copilot_reason="not_observed"

    if jq -e --arg sha "$HEAD_SHA" --arg re "$COPILOT_LOGIN_REGEX" '
      any(.[]?; (((.user.login // "") | ascii_downcase) | test($re)) and ((.commit_id // "") == $sha))
    ' <<<"$reviews_json" >/dev/null; then
      copilot_seen=1
      copilot_reason="pr_review_for_head"
    fi

    if [[ "$copilot_seen" -eq 0 ]]; then
      if jq -e --arg re "$COPILOT_LOGIN_REGEX" '
        any((.requested_reviewers // [])[]?; (((.login // "") | ascii_downcase) | test($re)))
      ' <<<"$pr_json" >/dev/null; then
        copilot_seen=1
        copilot_reason="requested_reviewer"
      fi
    fi

    if [[ "$copilot_seen" -eq 0 ]]; then
      if jq -e --arg t "$HEAD_COMMIT_TIME" --arg re "$COPILOT_LOGIN_REGEX" '
        any(.[]?; ((.created_at // "") > $t) and (((.user.login // "") | ascii_downcase) | test($re)))
      ' <<<"$pr_comments" >/dev/null || jq -e --arg t "$HEAD_COMMIT_TIME" --arg re "$COPILOT_LOGIN_REGEX" '
        any(.[]?; ((.created_at // "") > $t) and (((.user.login // "") | ascii_downcase) | test($re)))
      ' <<<"$issue_comments" >/dev/null; then
        copilot_seen=1
        copilot_reason="comment_after_head"
      fi
    fi

    if [[ "$copilot_seen" -eq 0 && $checks_rc -eq 0 && -n "$checks_json" ]]; then
      if jq -e --arg re "$COPILOT_LOGIN_REGEX" '
        any(.check_runs[]?; (((.name // "") | ascii_downcase) | test($re)))
      ' <<<"$checks_json" >/dev/null; then
        copilot_seen=1
        copilot_reason="copilot_check_present"
      fi
    fi
  fi

  BOT_COMMENT_SUMMARY="$(
    jq -r --arg t "$HEAD_COMMIT_TIME" '
      def is_bot($u):
        ($u.type == "Bot") or (((($u.login // "") | ascii_downcase) | contains("copilot")));
      def newer($c): (($c.created_at // "") > $t);
      def fmt($c):
        "- [" + ($c.user.login // "unknown") + "] " + ($c.html_url // "")
        + "\n  " + ((($c.body // "") | gsub("\r";"") | split("\n")[0]) | .[0:200]);
      [ .[] | select(newer(.)) | select(is_bot(.user)) | fmt(.) ] | join("\n")
    ' <<<"$pr_comments"
  )"

  BOT_COMMENT_SUMMARY2="$(
    jq -r --arg t "$HEAD_COMMIT_TIME" '
      def is_bot($u):
        ($u.type == "Bot") or (((($u.login // "") | ascii_downcase) | contains("copilot")));
      def newer($c): (($c.created_at // "") > $t);
      def fmt($c):
        "- [" + ($c.user.login // "unknown") + "] " + ($c.html_url // "")
        + "\n  " + ((($c.body // "") | gsub("\r";"") | split("\n")[0]) | .[0:200]);
      [ .[] | select(newer(.)) | select(is_bot(.user)) | fmt(.) ] | join("\n")
    ' <<<"$issue_comments"
  )"

  if [[ -n "$BOT_COMMENT_SUMMARY2" ]]; then
    if [[ -n "$BOT_COMMENT_SUMMARY" ]]; then
      BOT_COMMENT_SUMMARY="$BOT_COMMENT_SUMMARY"$'\n'"$BOT_COMMENT_SUMMARY2"
    else
      BOT_COMMENT_SUMMARY="$BOT_COMMENT_SUMMARY2"
    fi
  fi

  bot_new_count=0
  if [[ -n "$BOT_COMMENT_SUMMARY" ]]; then
    bot_new_count="$(printf "%s\n" "$BOT_COMMENT_SUMMARY" | grep -c '^\- \[' || true)"
  else
    BOT_COMMENT_SUMMARY="none"
  fi

  inline_unfixed_count=0
  inline_unfixed_lines=""
  while IFS=$'\t' read -r comment_url comment_path original_commit_id; do
    if [[ -z "$comment_url" && -z "$comment_path" && -z "$original_commit_id" ]]; then
      continue
    fi

    reason=""
    if [[ -z "$comment_path" || -z "$original_commit_id" ]]; then
      reason="missing_path_or_original_commit_id"
    elif ! ensure_commit "$original_commit_id"; then
      reason="original_commit_missing_locally:$original_commit_id"
    elif ! ensure_commit "$HEAD_SHA"; then
      reason="head_commit_missing_locally:$HEAD_SHA"
    elif [[ -z "$(git diff --name-only "$original_commit_id..$HEAD_SHA" -- "$comment_path" 2>/dev/null || true)" ]]; then
      reason="path_not_changed_since_comment_base"
    fi

    if [[ -n "$reason" ]]; then
      inline_unfixed_count=$((inline_unfixed_count + 1))
      inline_unfixed_lines="$inline_unfixed_lines- $comment_url ($comment_path): $reason"$'\n'
    fi
  done < <(
    jq -r '
      def is_bot($u):
        ($u.type == "Bot") or (((($u.login // "") | ascii_downcase) | contains("copilot")));
      [ .[] | select(is_bot(.user)) | [(.html_url // ""), (.path // ""), (.original_commit_id // "")] | @tsv ] | .[]
    ' <<<"$pr_comments"
  )
  if [[ "$inline_unfixed_count" -gt 0 ]]; then
    INLINE_BOT_ENFORCEMENT_SUMMARY="unaddressed_inline_bot_comments=$inline_unfixed_count
$inline_unfixed_lines"
  else
    INLINE_BOT_ENFORCEMENT_SUMMARY="all_inline_bot_comments_have_file_diffs_or_none"
  fi

  bot_issue_count="$(jq -r '
    def is_bot($u):
      ($u.type == "Bot") or (((($u.login // "") | ascii_downcase) | contains("copilot")));
    [ .[] | select(is_bot(.user)) ] | length
  ' <<<"$issue_comments")"
  ack_token="AFTERCARE_ACK: $HEAD_SHA"
  ack_match_count="$(jq -r --arg token "$ack_token" '
    [ .[] | select(((.body // "") | contains($token))) | select((.user.type // "") != "Bot") ] | length
  ' <<<"$issue_comments")"
  issue_bot_urls="$(jq -r '
    def is_bot($u):
      ($u.type == "Bot") or (((($u.login // "") | ascii_downcase) | contains("copilot")));
    [ .[] | select(is_bot(.user)) | "- " + (.html_url // "") ] | join("\n")
  ' <<<"$issue_comments")"
  ack_required=0
  ack_required_reason="not_required"
  if [[ "$REQUIRE_AFTERCARE_ACK" == "1" ]]; then
    ack_required=1
    ack_required_reason="strict_mode"
  elif [[ "$bot_issue_count" -gt 0 ]]; then
    ack_required=1
    ack_required_reason="bot_issue_comments_present"
  fi
  if [[ "$ack_required" -eq 1 ]]; then
    AFTERCARE_ACK_SUMMARY="required=yes
reason=$ack_required_reason
ack_token=$ack_token
ack_found=$ack_match_count
bot_issue_comments=$bot_issue_count
bot_issue_urls:
${issue_bot_urls:-none}"
  else
    AFTERCARE_ACK_SUMMARY="required=no (no bot issue comments and strict mode disabled)"
  fi

  if [[ "$REQUIRE_COPILOT_REVIEW" == "1" ]]; then
    COPILOT_REVIEW_SUMMARY="required=yes
login_regex=$COPILOT_LOGIN_REGEX
seen=$copilot_seen
reason=$copilot_reason
wait_timeout_secs=$COPILOT_WAIT_SECS"
  else
    COPILOT_REVIEW_SUMMARY="required=no (opt-in disabled)"
  fi

  problems=()

  # mergeability (null means GitHub hasn't computed yet).
  MERGEABLE_BLOCKED_IGNORED=0
  if [[ "$MERGEABLE" == "null" || "$MERGEABLE_STATE" == "unknown" ]]; then
    problems+=("mergeability_not_ready")
  elif [[ "$MERGEABLE" == "false" ]]; then
    problems+=("merge_conflict_or_blocked: mergeable_state=$MERGEABLE_STATE")
  elif [[ "$MERGEABLE_STATE" == "dirty" ]]; then
    problems+=("merge_conflict_or_blocked: mergeable_state=$MERGEABLE_STATE")
  elif [[ "$MERGEABLE_STATE" == "blocked" ]]; then
    # In CI, this script runs as required check `pr-gate-enforced`; when that check
    # is pending, GitHub can report mergeable_state=blocked, creating self-deadlock.
    if [[ -n "$IGNORE_CHECK_RUN_REGEX" && "$IGNORED_PENDING_CHECKS" != "0" ]]; then
      MERGEABLE_BLOCKED_IGNORED=1
    else
      problems+=("merge_conflict_or_blocked: mergeable_state=$MERGEABLE_STATE")
    fi
  fi

  if [[ "$CHECK_FAIL" != "0" ]]; then
    problems+=("checks_failing")
  fi
  if [[ "$CHECK_PENDING" != "0" ]]; then
    problems+=("checks_pending")
  fi

  review_decision_unknown=0
  if [[ -z "$REVIEW_DECISION" || "$REVIEW_DECISION" == "UNKNOWN" || "$REVIEW_DECISION" == "null" ]]; then
    review_decision_unknown=1
    if [[ "$REQUIRE_KNOWN_REVIEW_DECISION" == "1" ]]; then
      problems+=("review_decision_unknown")
    fi
  elif [[ "$REVIEW_DECISION" == "CHANGES_REQUESTED" ]]; then
    problems+=("changes_requested")
  fi

  if [[ "$inline_unfixed_count" -gt 0 ]]; then
    problems+=("inline_bot_comments_unaddressed")
  fi

  if [[ "$ack_required" -eq 1 && "$ack_match_count" -eq 0 ]]; then
    problems+=("missing_aftercare_ack_for_head")
  fi

  if [[ "$bot_new_count" -gt 0 && "$BOT_COMMENTS_MODE" == "block" ]]; then
    problems+=("new_bot_comments_since_last_push")
  fi

  if [[ "$REQUIRE_COPILOT_REVIEW" == "1" && "$copilot_seen" -eq 0 ]]; then
    problems+=("copilot_review_pending")
  fi

  if [[ "$branch_story_match" -ne 1 ]]; then
    problems+=("invalid_story_branch_name:$HEAD_REF")
  elif [[ "$branch_story_id" != "$STORY_ID" ]]; then
    problems+=("story_branch_mismatch:expected=$STORY_ID actual=$branch_story_id")
  fi

  if [[ "$pre_pr_rc" -ne 0 ]]; then
    problems+=("pre_pr_review_gate_failed")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    write_report
    if [[ "$bot_new_count" -gt 0 ]]; then
      echo "WARN: detected new bot/copilot comments since head commit ($bot_new_count); mode=$BOT_COMMENTS_MODE" >&2
    fi
    if [[ "$MERGEABLE_BLOCKED_IGNORED" -eq 1 ]]; then
      echo "WARN: mergeable_state=blocked ignored because ignored pending checks=$IGNORED_PENDING_CHECKS (self-check deadlock avoidance)" >&2
    fi
    if [[ "$review_decision_unknown" -eq 1 && "$REQUIRE_KNOWN_REVIEW_DECISION" != "1" ]]; then
      echo "WARN: reviewDecision is unknown but non-blocking in default mode" >&2
    fi
    echo "OK: PR gate passed"
    echo "  $PR_URL"
    [[ -n "$report_path" ]] && echo "  report: $report_path"
    exit 0
  fi

  write_report
  echo "FAIL: PR gate failed: ${problems[*]}" >&2
  echo "  $PR_URL" >&2
  [[ -n "$report_path" ]] && echo "  report: $report_path" >&2
  if [[ "$bot_new_count" -gt 0 && "$BOT_COMMENTS_MODE" == "warn" ]]; then
    echo "WARN: new bot/copilot comments since head commit are present ($bot_new_count) but non-blocking in warn mode" >&2
  fi
  if [[ "$review_decision_unknown" -eq 1 && "$REQUIRE_KNOWN_REVIEW_DECISION" != "1" ]]; then
    echo "WARN: reviewDecision is unknown but non-blocking in default mode" >&2
  fi

  if [[ "$WAIT" != "1" ]]; then
    exit 1
  fi

  now_epoch="$(date +%s)"
  if [[ "$REQUIRE_COPILOT_REVIEW" == "1" && "$copilot_seen" -eq 0 ]]; then
    if (( now_epoch - start_epoch > COPILOT_WAIT_SECS )); then
      echo "FAIL: Copilot review not observed within ${COPILOT_WAIT_SECS}s for HEAD=$HEAD_SHA" >&2
      echo "Tip: set REQUIRE_COPILOT_REVIEW=0 (or omit --require-copilot-review) to bypass, or adjust COPILOT_LOGIN_REGEX/COPILOT_WAIT_SECS." >&2
      exit 1
    fi
  fi
  if (( now_epoch - start_epoch > TIMEOUT_SECS )); then
    echo "FAIL: timeout waiting for PR gate to pass" >&2
    exit 1
  fi

  sleep "$POLL_SECS"
done
