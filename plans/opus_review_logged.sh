#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  plans/opus_review_logged.sh STORY_ID [--commit REF | --base REF | --uncommitted] [--title TITLE] [--out-root PATH] [-- <extra claude args>]

Fallback reviewer when codex CLI is unavailable. Uses Claude Opus 4.6 via
`claude --model claude-opus-4-6`.

Defaults:
  --commit HEAD
  --title "<STORY_ID>: Opus review"
  --out-root "${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"

Artifacts:
  - Raw review: artifacts/story/<ID>/opus/<STAMP>_review.md

Examples:
  plans/opus_review_logged.sh S1-004 --commit HEAD --title "S1-004: Opus review"
  plans/opus_review_logged.sh S1-004 --base run/slice1-clean --title "S1-004: review vs integration"
EOF
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

story="${1:-}"
if [[ -z "$story" || "$story" == "-h" || "$story" == "--help" ]]; then
  usage
  exit 2
fi
shift

mode="commit"
commit="HEAD"
base=""
title=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --commit)
      mode="commit"
      commit="${2:?missing ref}"
      shift 2
      ;;
    --base)
      mode="base"
      base="${2:?missing ref}"
      shift 2
      ;;
    --uncommitted)
      mode="uncommitted"
      shift 1
      ;;
    --title)
      title="${2:?missing title}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    --)
      shift
      extra=("$@")
      break
      ;;
    *)
      extra+=("$1")
      shift 1
      ;;
  esac
done

if [[ -z "$title" ]]; then
  title="$story: Opus review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$root"

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/opus"
else
  outdir="$root/$out_root/$story/opus"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
stamp="${ts}_$$_${RANDOM}"
outfile="$outdir/${stamp}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

# Build the diff context for the review prompt
diff_context=""
case "$mode" in
  commit)
    resolved="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
    if [[ -n "$resolved" ]]; then
      diff_context="$(git diff "${resolved}^..${resolved}" 2>/dev/null || true)"
    fi
    ;;
  base)
    diff_context="$(git diff "${base}...HEAD" 2>/dev/null || true)"
    ;;
  uncommitted)
    diff_context="$(git diff HEAD 2>/dev/null || true)"
    ;;
esac

# Build the review prompt
review_prompt="You are a senior code reviewer for story $story on branch $branch (HEAD: $head_sha).

Review the following diff and provide findings ordered by severity (P0-Critical, P1-High, P2-Medium, P3-Low).

Focus on:
- Correctness bugs and logic errors
- Safety violations (unwrap in production, silent error drops, fail-open paths)
- Missing or inadequate tests
- Contract violations (specs/CONTRACT.md)
- Security issues (injection, auth gaps, race conditions)
- Performance regressions

For each finding, include:
- File path and line number
- Severity level (P0-P3)
- Description of the issue
- Suggested fix

Title: $title

Diff:
\`\`\`
${diff_context:-(no diff available)}
\`\`\`"

# Write prompt to temp file for --from-file input
prompt_tmp="$(mktemp)"
transcript_tmp="$(mktemp)"
cleanup() {
  rm -f "$prompt_tmp" "$transcript_tmp"
}
trap cleanup EXIT

printf '%s' "$review_prompt" > "$prompt_tmp"

# Use claude CLI with opus model
cmd=("claude" "--model" "claude-opus-4-6" "--print" "--verbose")
if [[ ${#extra[@]} -gt 0 ]]; then
  cmd+=("${extra[@]}")
fi

start_epoch="$(date +%s)"
set +e
"${cmd[@]}" < "$prompt_tmp" 2>&1 | tee "$transcript_tmp"
rc="${PIPESTATUS[0]}"
set -e
end_epoch="$(date +%s)"
duration_seconds="$((end_epoch - start_epoch))"

printf '\n' >> "$transcript_tmp"
transcript_hash="$(sha256_file "$transcript_tmp")"
transcript_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"

{
  echo "# Opus review"
  echo
  echo "- Story: $story"
  echo "- Timestamp (UTC): $ts"
  echo "- Branch: $branch"
  echo "- HEAD: $head_sha"
  echo "- Mode: $mode"
  if [[ "$mode" == "commit" ]]; then
    echo "- Commit ref: $commit"
  fi
  if [[ "$mode" == "base" ]]; then
    echo "- Base ref: $base"
  fi
  echo "- Model: claude-opus-4-6"
  echo "- Command: ${cmd[*]}"
  echo "- Artifact Provenance: logger-v1"
  echo "- Generator Script: plans/opus_review_logged.sh"
  echo "- Command Exit Code: $rc"
  echo "- Transcript SHA256: $transcript_hash"
  echo "- Transcript Bytes: $transcript_bytes"
  echo "- Duration Seconds: $duration_seconds"
  echo
  echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
} > "$outfile"
cat "$transcript_tmp" >> "$outfile"
echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"

echo "Saved Opus review: $outfile" >&2
exit "$rc"
