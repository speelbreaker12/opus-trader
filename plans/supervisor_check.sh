#!/usr/bin/env bash
set -euo pipefail

# Supervisor agent: independent Sonnet-based verification of builder work.
# Runs at 3 checkpoints in the story loop to catch semantic cheating that
# mechanical gates cannot detect.
#
# Usage: plans/supervisor_check.sh <STORY_ID> <checkpoint> [--dry-run]
#
# Checkpoints:
#   post-cycle1  — After cycle 1 review: are the findings real?
#   post-fix     — After fixes applied: does the diff actually address findings?
#   post-cycle2  — After cycle 2 review: is the review legitimate and findings resolved?
#
# Requires:
#   - claude CLI installed (uses --model claude-sonnet-4-6)
#   - Appropriate artifacts in artifacts/story/<ID>/
#
# Artifacts written to:
#   artifacts/story/<ID>/supervisor/<checkpoint>_<timestamp>.md
#
# Exit codes:
#   0 — PASS (supervisor approves)
#   1 — FAIL (supervisor rejects — builder must redo)
#   2 — usage/setup error
#   3 — supervisor inconclusive (treat as FAIL)

usage() {
  cat <<'EOF'
Usage: plans/supervisor_check.sh <STORY_ID> <checkpoint> [--dry-run]

Checkpoints:
  post-cycle1  — Verify cycle 1 findings are real (match actual code)
  post-fix     — Verify diff addresses the specific findings listed
  post-cycle2  — Verify cycle 2 is legitimate and findings resolved

Options:
  --dry-run    Print prompt but don't call Sonnet (for testing)
EOF
}

die() { echo "SUPERVISOR ERROR: $*" >&2; exit 2; }
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

STORY="${1:-}"
CHECKPOINT="${2:-}"
DRY_RUN=0
if [[ "${3:-}" == "--dry-run" ]]; then DRY_RUN=1; fi

[[ -n "$STORY" && -n "$CHECKPOINT" ]] || { usage >&2; exit 2; }
case "$CHECKPOINT" in
  post-cycle1|post-fix|post-cycle2) ;;
  *) die "unknown checkpoint: $CHECKPOINT (must be post-cycle1, post-fix, or post-cycle2)" ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$ROOT"

HEAD_SHA="$(git rev-parse HEAD)"
BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"

art_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
if [[ "$art_root" != /* ]]; then art_root="$ROOT/$art_root"; fi
story_dir="$art_root/$STORY"

out_dir="$story_dir/supervisor"
mkdir -p "$out_dir"
ts="$(date -u +%Y%m%dT%H%M%SZ)"
outfile="$out_dir/${CHECKPOINT}_${ts}.md"

# ── Gather context based on checkpoint ──────────────────────────────

prompt=""

gather_latest_review() {
  local dir="$1" pattern="$2"
  if [[ -d "$dir" ]]; then
    find "$dir" -maxdepth 1 -type f -name "$pattern" | LC_ALL=C sort -r | head -1
  fi
}

gather_cycle_reviews() {
  # Find the two most recent codex/opus reviews
  local c1="" c2=""
  local all_reviews=()
  for d in "$story_dir/codex" "$story_dir/opus"; do
    if [[ -d "$d" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" ]] && all_reviews+=("$f")
      done < <(find "$d" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort)
    fi
  done
  if [[ ${#all_reviews[@]} -ge 2 ]]; then
    c1="${all_reviews[0]}"  # oldest = cycle 1
    c2="${all_reviews[-1]}" # newest = cycle 2
  elif [[ ${#all_reviews[@]} -eq 1 ]]; then
    c1="${all_reviews[0]}"
  fi
  echo "$c1|$c2"
}

case "$CHECKPOINT" in
  post-cycle1)
    # Context: cycle 1 review + the code diff it reviewed
    cycle_info="$(gather_cycle_reviews)"
    cycle1_file="$(echo "$cycle_info" | cut -d'|' -f1)"
    [[ -n "$cycle1_file" && -f "$cycle1_file" ]] || die "no cycle 1 review found in $story_dir/codex or $story_dir/opus"

    # Get the diff the reviewer should have reviewed
    diff_context="$(git diff HEAD~3..HEAD --stat 2>/dev/null || true)"
    diff_sample="$(git diff HEAD~3..HEAD 2>/dev/null | head -300 || true)"

    # Extract transcript
    cycle1_transcript="$(sed -n '/<<<REVIEW_TRANSCRIPT_BEGIN>>>/,/<<<REVIEW_TRANSCRIPT_END>>>/p' "$cycle1_file" | head -200)"

    prompt="You are a SUPERVISOR agent verifying the quality of a code review.

STORY: $STORY
HEAD: $HEAD_SHA

## Task
A builder agent received this cycle 1 review. Your job: verify the review findings are REAL and match the actual code.

## Cycle 1 Review Transcript (first 200 lines)
\`\`\`
$cycle1_transcript
\`\`\`

## Actual Diff Stats
\`\`\`
$diff_context
\`\`\`

## Actual Diff (first 300 lines)
\`\`\`
$diff_sample
\`\`\`

## Verification Checklist
1. Do the file paths mentioned in findings exist in the actual diff?
2. Do the line numbers roughly correspond to real code locations?
3. Are the finding descriptions plausible for the code shown?
4. Is this a real review or generic filler text?

## Response Format
Answer EXACTLY in this format:
VERDICT: PASS or FAIL
REASON: one-line explanation
DETAILS:
- Finding 1: real/fabricated — brief explanation
- Finding 2: real/fabricated — brief explanation
(list each finding)"
    ;;

  post-fix)
    # Context: cycle 1 findings + the diff between cycle 1 and now
    cycle_info="$(gather_cycle_reviews)"
    cycle1_file="$(echo "$cycle_info" | cut -d'|' -f1)"
    [[ -n "$cycle1_file" && -f "$cycle1_file" ]] || die "no cycle 1 review found"

    cycle1_transcript="$(sed -n '/<<<REVIEW_TRANSCRIPT_BEGIN>>>/,/<<<REVIEW_TRANSCRIPT_END>>>/p' "$cycle1_file" | head -200)"

    # Get recent diff (the "fixes")
    fix_diff="$(git diff HEAD~1..HEAD 2>/dev/null | head -500 || true)"
    if [[ -z "$fix_diff" ]]; then
      fix_diff="$(git diff --cached 2>/dev/null | head -500 || true)"
    fi
    if [[ -z "$fix_diff" ]]; then
      fix_diff="$(git diff 2>/dev/null | head -500 || true)"
    fi

    # Check for finding disposition in resolution
    res_file="$story_dir/review_resolution.md"
    disposition=""
    if [[ -f "$res_file" ]]; then
      disposition="$(sed -n '/## Finding Disposition/,/^$/p' "$res_file" | head -30)"
    fi

    prompt="You are a SUPERVISOR agent verifying that a builder actually fixed review findings.

STORY: $STORY
HEAD: $HEAD_SHA

## Task
The builder claims to have fixed cycle 1 findings. Verify the fix diff actually addresses the findings.

## Cycle 1 Findings (first 200 lines)
\`\`\`
$cycle1_transcript
\`\`\`

## Fix Diff (first 500 lines)
\`\`\`
$fix_diff
\`\`\`

## Finding Disposition (if available)
\`\`\`
$disposition
\`\`\`

## Verification Checklist
1. For each P0/P1 finding: does the diff contain changes to the cited file and location?
2. Do the changes plausibly address the described issue (not just cosmetic/unrelated edits)?
3. Did the builder claim FIXED for findings that aren't actually addressed in the diff?
4. Are there P0/P1 findings that have no corresponding fix in the diff?

## Response Format
VERDICT: PASS or FAIL
REASON: one-line explanation
DETAILS:
- F-1 (P1, file:line): addressed/not-addressed — brief explanation
- F-2 (P1, file:line): addressed/not-addressed — brief explanation"
    ;;

  post-cycle2)
    # Context: both cycle reviews + disposition
    cycle_info="$(gather_cycle_reviews)"
    cycle1_file="$(echo "$cycle_info" | cut -d'|' -f1)"
    cycle2_file="$(echo "$cycle_info" | cut -d'|' -f2)"
    [[ -n "$cycle2_file" && -f "$cycle2_file" ]] || die "no cycle 2 review found"

    cycle1_transcript="$(sed -n '/<<<REVIEW_TRANSCRIPT_BEGIN>>>/,/<<<REVIEW_TRANSCRIPT_END>>>/p' "${cycle1_file:-/dev/null}" 2>/dev/null | head -100)"
    cycle2_transcript="$(sed -n '/<<<REVIEW_TRANSCRIPT_BEGIN>>>/,/<<<REVIEW_TRANSCRIPT_END>>>/p' "$cycle2_file" | head -200)"

    res_file="$story_dir/review_resolution.md"
    resolution=""
    if [[ -f "$res_file" ]]; then
      resolution="$(cat "$res_file")"
    fi

    prompt="You are a SUPERVISOR agent performing final verification of the review cycle.

STORY: $STORY
HEAD: $HEAD_SHA

## Task
Verify that cycle 2 is a legitimate re-review (not a rubber stamp) and that findings are genuinely resolved.

## Cycle 1 Findings (first 100 lines)
\`\`\`
$cycle1_transcript
\`\`\`

## Cycle 2 Review (first 200 lines)
\`\`\`
$cycle2_transcript
\`\`\`

## Resolution Document
\`\`\`
$resolution
\`\`\`

## Verification Checklist
1. Does cycle 2 actually engage with the code (file references, specific observations)?
2. Does cycle 2 acknowledge or verify the fixes for cycle 1 findings?
3. Is cycle 2 substantially different from cycle 1 (not copy-pasted)?
4. Does the resolution accurately reflect both cycles?
5. Are there cycle 1 P0/P1 findings missing from the disposition table?
6. Any signs of fabrication (generic text, no specifics, implausible timing)?

## Response Format
VERDICT: PASS or FAIL
REASON: one-line explanation
DETAILS:
- Engagement: real/superficial — explanation
- Cycle 1 findings resolved: yes/no/partial — explanation
- Resolution accuracy: accurate/inaccurate — explanation
- Fabrication risk: none/low/high — explanation"
    ;;
esac

# ── Execute supervisor check ────────────────────────────────────────

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "=== DRY RUN: prompt would be sent to Sonnet ==="
  echo "$prompt"
  echo "=== END DRY RUN ==="
  exit 0
fi

# Check claude CLI exists
command -v claude >/dev/null 2>&1 || die "claude CLI not found — install it or use --dry-run"

prompt_tmp="$(mktemp)"
response_tmp="$(mktemp)"
cleanup() { rm -f "$prompt_tmp" "$response_tmp"; }
trap cleanup EXIT

printf '%s' "$prompt" > "$prompt_tmp"

echo "SUPERVISOR: running $CHECKPOINT check for $STORY..." >&2

start_epoch="$(date +%s)"
set +e
claude --model claude-sonnet-4-6 --print --verbose < "$prompt_tmp" > "$response_tmp" 2>&1
rc=$?
set -e
end_epoch="$(date +%s)"
duration="$((end_epoch - start_epoch))"

if [[ $rc -ne 0 ]]; then
  echo "SUPERVISOR ERROR: claude CLI failed (exit $rc)" >&2
  cat "$response_tmp" >&2
  exit 3
fi

# Parse verdict from response
response="$(cat "$response_tmp")"
verdict="$(echo "$response" | grep -oE '^VERDICT:\s*(PASS|FAIL)' | head -1 | grep -oE '(PASS|FAIL)' || true)"
reason="$(echo "$response" | grep -oE '^REASON:.*' | head -1 | sed 's/^REASON:\s*//' || true)"

if [[ -z "$verdict" ]]; then
  echo "SUPERVISOR WARNING: could not parse VERDICT from response — treating as FAIL" >&2
  verdict="FAIL"
  reason="Supervisor response did not contain a clear VERDICT: PASS or FAIL"
fi

# Compute response hash
response_hash="$(sha256_of "$response_tmp")"
response_bytes="$(wc -c < "$response_tmp" | tr -d '[:space:]')"

# Write artifact
{
  echo "# Supervisor Check: $CHECKPOINT"
  echo ""
  echo "- Story: $STORY"
  echo "- HEAD: $HEAD_SHA"
  echo "- Branch: $BRANCH"
  echo "- Checkpoint: $CHECKPOINT"
  echo "- Timestamp (UTC): $ts"
  echo "- Model: claude-sonnet-4-6"
  echo "- Verdict: $verdict"
  echo "- Reason: $reason"
  echo "- Duration Seconds: $duration"
  echo "- Response SHA256: $response_hash"
  echo "- Response Bytes: $response_bytes"
  echo "- Artifact Provenance: supervisor-v1"
  echo "- Generator Script: plans/supervisor_check.sh"
  echo ""
  echo "## Prompt"
  echo ""
  echo '```'
  cat "$prompt_tmp"
  echo '```'
  echo ""
  echo "## Response"
  echo ""
  echo "<<<SUPERVISOR_RESPONSE_BEGIN>>>"
  echo "$response"
  echo "<<<SUPERVISOR_RESPONSE_END>>>"
} > "$outfile"

echo "SUPERVISOR: $CHECKPOINT — $verdict ($reason)" >&2
echo "SUPERVISOR: artifact saved to $outfile" >&2

if [[ "$verdict" == "PASS" ]]; then
  exit 0
else
  echo "SUPERVISOR REJECTED: $reason" >&2
  echo "Builder must address supervisor findings and re-run the checkpoint." >&2
  exit 1
fi
