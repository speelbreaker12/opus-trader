#!/usr/bin/env bash
set -euo pipefail

# Unified review artifact logger.
#
# Dispatches to codex or opus review tools, captures transcript with
# provenance header and SHA256, writes to standard artifact path.
#
# Usage:
#   plans/review_logged.sh STORY_ID --tool codex [--commit REF | --base REF | --uncommitted] [--title TITLE]
#   plans/review_logged.sh STORY_ID --tool opus  [--base REF] [--title TITLE]

usage() {
  cat <<'EOF'
Usage:
  plans/review_logged.sh STORY_ID --tool <codex|opus|kimi> [options] [-- <extra tool args>]

Options:
  --tool TOOL      Required: codex, opus, or kimi
  --commit REF     Review a specific commit (default: HEAD)
  --base REF       Review diff from base to HEAD
  --uncommitted    Review uncommitted changes
  --files LIST     Review specific files (space/comma-separated paths; for recon audits)
  --title TITLE    Review title (default: "<STORY_ID>: <TOOL> review")
  --out-root PATH  Override artifact root (default: artifacts/story)

Artifacts:
  - artifacts/story/<ID>/<tool>/<STAMP>_review.md

Examples:
  plans/review_logged.sh S1-004 --tool codex --base run/slice1-clean
  plans/review_logged.sh S1-004 --tool opus --base run/slice1-clean
  plans/review_logged.sh S1-004 --tool kimi --base main
  plans/review_logged.sh S1-004 --tool codex --commit HEAD -- --c model="o3"
  plans/review_logged.sh S1-004 --tool opus --files "crates/soldier_core/src/gate.rs crates/soldier_core/src/risk.rs"
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

# Portable uppercase-first (zsh lacks ${var^})
ucfirst() { echo "$1" | awk '{print toupper(substr($0,1,1)) substr($0,2)}'; }

# Portable lowercase (zsh lacks ${var,,})
lcase() { echo "$1" | tr '[:upper:]' '[:lower:]'; }

story="${1:-}"
if [[ -z "$story" || "$story" == "-h" || "$story" == "--help" ]]; then
  usage
  exit 2
fi
shift

tool=""
mode="commit"
commit="HEAD"
base=""
files_list=""
title=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
extra=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tool)
      tool="${2:?missing tool name}"
      shift 2
      ;;
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
    --files)
      mode="files"
      files_list="${2:?missing files list}"
      shift 2
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

[[ -n "$tool" ]] || { echo "ERROR: --tool is required (codex, opus, or kimi)" >&2; exit 2; }
case "$tool" in
  codex|opus|kimi) ;;
  *) echo "ERROR: unknown tool '$tool' (expected: codex, opus, or kimi)" >&2; exit 2 ;;
esac

if [[ -z "$title" ]]; then
  title="$story: $(ucfirst "$tool") review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$root"

# Verify tool is available
case "$tool" in
  codex)
    command -v codex >/dev/null 2>&1 || { echo "ERROR: codex CLI not found in PATH" >&2; exit 2; }
    ;;
  opus)
    command -v claude >/dev/null 2>&1 || { echo "ERROR: claude CLI not found in PATH" >&2; exit 2; }
    ;;
  kimi)
    command -v kimi >/dev/null 2>&1 || { echo "ERROR: kimi CLI not found in PATH" >&2; exit 2; }
    ;;
esac

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/$tool"
else
  outdir="$root/$out_root/$story/$tool"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
stamp="${ts}_$$_${RANDOM}"
outfile="$outdir/${stamp}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

# ── Build tool-specific command ─────────────────────────────────────

cmd=()
prompt_tmp=""

# ── Build file contents for --files mode ────────────────────────────
files_context=""
if [[ "$mode" == "files" && -n "$files_list" ]]; then
  # Normalize: replace commas with spaces
  normalized_files="${files_list//,/ }"
  for f in $normalized_files; do
    if [[ -f "$f" ]]; then
      files_context+="
=== FILE: $f ===
$(cat "$f")
"
    else
      files_context+="
=== FILE: $f === (NOT FOUND)
"
    fi
  done
fi

case "$tool" in
  codex)
    cmd=("codex" "review" "--title" "$title")
    case "$mode" in
      commit)      cmd+=("--commit" "$commit") ;;
      base)        cmd+=("--base" "$base") ;;
      uncommitted) cmd+=("--uncommitted") ;;
      files)
        echo "ERROR: --files mode is not supported with codex (use --tool opus instead)" >&2
        exit 2
        ;;
    esac
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;

  opus)
    # Build diff context for the review prompt
    diff_context=""
    case "$mode" in
      commit)
        resolved="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
          # Use show for root commits (no parent), diff for normal commits
          if git rev-parse "${resolved}^" >/dev/null 2>&1; then
            diff_context="$(git diff "${resolved}^..${resolved}" 2>/dev/null || true)"
          else
            diff_context="$(git show --format= "${resolved}" 2>/dev/null || true)"
          fi
        fi
        ;;
      base)
        diff_context="$(git diff "${base}...HEAD" 2>/dev/null || true)"
        ;;
      uncommitted)
        diff_context="$(git diff HEAD 2>/dev/null || true)"
        ;;
      files)
        diff_context="$files_context"
        ;;
    esac

    review_context_label="Diff"
    [[ "$mode" == "files" ]] && review_context_label="Files to review"

    review_prompt="You are a senior code reviewer for story $story on branch $branch (HEAD: $head_sha).

Review the following $(lcase "$review_context_label") and provide findings ordered by severity (P0-Critical, P1-High, P2-Medium, P3-Low).

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

${review_context_label}:
\`\`\`
${diff_context:-(no content available)}
\`\`\`"

    prompt_tmp="$(mktemp)"
    printf '%s' "$review_prompt" > "$prompt_tmp"

    cmd=("claude" "--model" "claude-opus-4-6" "--print" "--verbose")
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;

  kimi)
    # Build diff/files context (same as opus)
    diff_context=""
    case "$mode" in
      commit)
        resolved="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
        if [[ -n "$resolved" ]]; then
          if git rev-parse "${resolved}^" >/dev/null 2>&1; then
            diff_context="$(git diff "${resolved}^..${resolved}" 2>/dev/null || true)"
          else
            diff_context="$(git show --format= "${resolved}" 2>/dev/null || true)"
          fi
        fi
        ;;
      base)
        diff_context="$(git diff "${base}...HEAD" 2>/dev/null || true)"
        ;;
      uncommitted)
        diff_context="$(git diff HEAD 2>/dev/null || true)"
        ;;
      files)
        diff_context="$files_context"
        ;;
    esac

    review_context_label="Diff"
    [[ "$mode" == "files" ]] && review_context_label="Files to review"

    review_prompt="You are a senior code reviewer for story $story on branch $branch (HEAD: $head_sha).

Review the following $(lcase "$review_context_label") and provide findings ordered by severity (P0-Critical, P1-High, P2-Medium, P3-Low).

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

${review_context_label}:
\`\`\`
${diff_context:-(no content available)}
\`\`\`"

    prompt_tmp="$(mktemp)"
    printf '%s' "$review_prompt" > "$prompt_tmp"

    cmd=("kimi" "--print" "--final-message-only" "--model" "k2.5")
    if [[ ${#extra[@]} -gt 0 ]]; then
      cmd+=("${extra[@]}")
    fi
    ;;
esac

# ── Run review command ──────────────────────────────────────────────

transcript_tmp="$(mktemp)"
cleanup() {
  rm -f "$transcript_tmp" ${prompt_tmp:+"$prompt_tmp"} ${files_tmp:+"$files_tmp"}
}
trap cleanup EXIT

start_epoch="$(date +%s)"
set +e
if [[ ("$tool" == "kimi" || "$tool" == "opus") && -n "$prompt_tmp" ]]; then
  "${cmd[@]}" < "$prompt_tmp" 2>&1 | tee "$transcript_tmp"
else
  "${cmd[@]}" 2>&1 | tee "$transcript_tmp"
fi
rc="${PIPESTATUS[0]}"
set -e
end_epoch="$(date +%s)"
duration_seconds="$((end_epoch - start_epoch))"

printf '\n' >> "$transcript_tmp"
transcript_hash="$(sha256_file "$transcript_tmp")"
transcript_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"

# ── Write artifact with provenance header ───────────────────────────

{
  echo "# $(ucfirst "$tool") review"
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
  if [[ "$mode" == "files" ]]; then
    echo "- Files: $files_list"
  fi
  if [[ "$tool" == "opus" ]]; then
    echo "- Model: claude-opus-4-6"
  elif [[ "$tool" == "kimi" ]]; then
    echo "- Model: kimi-k2.5"
  fi
  echo "- Command: ${cmd[*]}"
  echo "- Artifact Provenance: logger-v1"
  echo "- Generator Script: plans/review_logged.sh"
  echo "- Command Exit Code: $rc"
  echo "- Transcript SHA256: $transcript_hash"
  echo "- Transcript Bytes: $transcript_bytes"
  echo "- Duration Seconds: $duration_seconds"
  echo
  echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
} > "$outfile"
cat "$transcript_tmp" >> "$outfile"
echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"

# Emit structured findings summary for deterministic gate parsing.
# Counts P0-P3 by matching "| P<N>" or "P<N>:" or "**P<N>**" patterns in transcript.
# Falls back to 999 if counting fails (fail-closed: assume findings exist).
p0="$(grep -coE '\bP0\b' "$transcript_tmp" 2>/dev/null || echo 999)"
p1="$(grep -coE '\bP1\b' "$transcript_tmp" 2>/dev/null || echo 999)"
p2="$(grep -coE '\bP2\b' "$transcript_tmp" 2>/dev/null || echo 999)"
echo "FINDINGS_SUMMARY: P0=$p0 P1=$p1 P2=$p2" >> "$outfile"

# Run codex digest if available (codex only)
if [[ "$tool" == "codex" ]]; then
  digest_script="$root/plans/codex_review_digest.sh"
  if [[ -x "$digest_script" ]]; then
    if ! "$digest_script" "$outfile" >&2; then
      echo "WARN: failed to generate digest for $outfile" >&2
    fi
  fi
fi

echo "Saved $(ucfirst "$tool") review: $outfile" >&2
exit "$rc"
