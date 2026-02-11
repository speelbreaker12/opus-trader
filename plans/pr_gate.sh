#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/pr_gate.sh [--pr <number>] [--wait] [--timeout-secs <n>] [--poll-secs <n>] [--story <ID>] [--artifacts-root <path>] [--bot-comments-mode <warn|block>]

What it checks (blocking):
  - PR mergeable_state is clean (no merge conflicts/blocked state)
  - All check-runs for PR head SHA are completed and successful
  - reviewDecision is not CHANGES_REQUESTED

Bot/copilot comments:
  - Default mode is warn: new bot/copilot comments since head commit are printed as warnings only
  - Optional block mode: treat new bot/copilot comments as blocking

No PR link required:
  - If --pr omitted, auto-detects PR for current branch via `gh pr view`.

Artifacts (optional):
  - If --story is provided, writes a report under artifacts/story/<ID>/pr_gate/<ts>_pr_gate.md
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

PR=""
WAIT=0
TIMEOUT_SECS=900
POLL_SECS=15
STORY_ID=""
ART_ROOT=""
BOT_COMMENTS_MODE="${PR_GATE_BOT_COMMENT_MODE:-warn}"

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
report_path=""

if [[ -n "$STORY_ID" ]]; then
  root="${ART_ROOT:-${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}}"
  [[ "$root" == /* ]] || root="$repo_root/$root"
  outdir="$root/$STORY_ID/pr_gate"
  mkdir -p "$outdir"
  report_path="$outdir/${ts}_pr_gate.md"
fi

PR_URL=""
HEAD_SHA=""
BASE_REF=""
MERGEABLE=""
MERGEABLE_STATE=""
REVIEW_DECISION=""
CHECK_SUMMARY=""
BOT_COMMENT_SUMMARY=""
HEAD_COMMIT_TIME=""
CHECK_PENDING="0"
CHECK_FAIL="0"

write_report() {
  [[ -n "$report_path" ]] || return 0
  cat > "$report_path" <<EOF
# PR Gate Report

Timestamp (UTC): $ts
Repo: $repo
PR: $PR
URL: $PR_URL

Head SHA: $HEAD_SHA
Base: $BASE_REF
mergeable: $MERGEABLE
mergeable_state: $MERGEABLE_STATE
reviewDecision: $REVIEW_DECISION
bot_comments_mode: $BOT_COMMENTS_MODE

## Check-runs
$CHECK_SUMMARY

## New bot/copilot comments since head commit
$BOT_COMMENT_SUMMARY

EOF
}

start_epoch="$(date +%s)"

while true; do
  pr_json="$(gh api "repos/$repo/pulls/$PR")" || die "failed to fetch PR via gh api"

  PR_URL="$(jq -r '.html_url // ""' <<<"$pr_json")"
  HEAD_SHA="$(jq -r '.head.sha // ""' <<<"$pr_json")"
  BASE_REF="$(jq -r '.base.ref // ""' <<<"$pr_json")"
  MERGEABLE="$(jq -r 'if .mergeable == null then "null" elif .mergeable then "true" else "false" end' <<<"$pr_json")"
  MERGEABLE_STATE="$(jq -r '.mergeable_state // "unknown"' <<<"$pr_json")"

  [[ -n "$PR_URL" && -n "$HEAD_SHA" && -n "$BASE_REF" ]] || die "incomplete PR payload from GitHub API"

  # reviewDecision from gh pr view (GraphQL-backed).
  set +e
  REVIEW_DECISION="$(gh pr view "$PR" --json reviewDecision --jq '.reviewDecision' 2>/dev/null)"
  set -e
  [[ -n "$REVIEW_DECISION" ]] || REVIEW_DECISION="UNKNOWN"

  commit_json="$(gh api "repos/$repo/commits/$HEAD_SHA")" || die "failed to fetch head commit"
  HEAD_COMMIT_TIME="$(jq -r '.commit.committer.date // ""' <<<"$commit_json")"
  [[ -n "$HEAD_COMMIT_TIME" ]] || die "missing head commit timestamp"

  set +e
  checks_json="$(gh api "repos/$repo/commits/$HEAD_SHA/check-runs" 2>/dev/null)"
  checks_rc=$?
  set -e
  if [[ $checks_rc -ne 0 || -z "$checks_json" ]]; then
    status_json="$(gh api "repos/$repo/commits/$HEAD_SHA/status")" || die "failed to fetch commit status"
    CHECK_PENDING="$(jq '[.statuses[] | select(.state=="pending")] | length' <<<"$status_json")"
    CHECK_FAIL="$(jq '[.statuses[] | select(.state=="failure" or .state=="error")] | length' <<<"$status_json")"
    CHECK_SUMMARY="(fallback status API)
pending=$CHECK_PENDING
failing=$CHECK_FAIL"
  else
    CHECK_PENDING="$(jq '[.check_runs[] | select(.status != "completed")] | length' <<<"$checks_json")"
    CHECK_FAIL="$(jq '[.check_runs[] | select(.status=="completed") | select(.conclusion != null) | select(.conclusion!="success" and .conclusion!="neutral" and .conclusion!="skipped")] | length' <<<"$checks_json")"
    CHECK_SUMMARY="$(
      jq -r '
        (.check_runs // []) as $r
        | "pending=" + ([ $r[] | select(.status!="completed") ] | length | tostring)
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
      ' <<<"$checks_json"
    )"
  fi

  pr_comments="$(gh api "repos/$repo/pulls/$PR/comments?per_page=100")" || die "failed to fetch PR review comments"
  issue_comments="$(gh api "repos/$repo/issues/$PR/comments?per_page=100")" || die "failed to fetch PR issue comments"

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

  problems=()

  # mergeability (null means GitHub hasn't computed yet).
  if [[ "$MERGEABLE" == "null" || "$MERGEABLE_STATE" == "unknown" ]]; then
    problems+=("mergeability_not_ready")
  elif [[ "$MERGEABLE_STATE" != "clean" ]]; then
    problems+=("merge_conflict_or_blocked: mergeable_state=$MERGEABLE_STATE")
  fi

  if [[ "$CHECK_FAIL" != "0" ]]; then
    problems+=("checks_failing")
  fi
  if [[ "$CHECK_PENDING" != "0" ]]; then
    problems+=("checks_pending")
  fi

  if [[ "$REVIEW_DECISION" == "CHANGES_REQUESTED" ]]; then
    problems+=("changes_requested")
  fi

  if [[ "$bot_new_count" -gt 0 && "$BOT_COMMENTS_MODE" == "block" ]]; then
    problems+=("new_bot_comments_since_last_push")
  fi

  if [[ ${#problems[@]} -eq 0 ]]; then
    write_report
    if [[ "$bot_new_count" -gt 0 ]]; then
      echo "WARN: detected new bot/copilot comments since head commit ($bot_new_count); mode=$BOT_COMMENTS_MODE" >&2
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

  if [[ "$WAIT" != "1" ]]; then
    exit 1
  fi

  now_epoch="$(date +%s)"
  if (( now_epoch - start_epoch > TIMEOUT_SECS )); then
    echo "FAIL: timeout waiting for PR gate to pass" >&2
    exit 1
  fi

  sleep "$POLL_SECS"
done
