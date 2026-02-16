#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  plans/kimi_review_logged.sh STORY_ID [--commit REF | --base REF | --uncommitted] [--model MODEL] [--title TITLE] [--out-root PATH] [-- <extra kimi args>]

Defaults:
  --commit HEAD
  --model k2.5
  --title "<STORY_ID>: Kimi review"
  --out-root "${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"

Artifacts:
  - Raw review: artifacts/story/<ID>/kimi/<STAMP>_review.md

Notes:
  - If your installed `kimi` CLI supports `kimi review`, this script uses it directly.
  - Otherwise it falls back to `kimi --print --prompt ...` with the same story/head context.

Examples:
  plans/kimi_review_logged.sh S1-004 --commit HEAD --title "S1-004: Kimi second opinion"
  plans/kimi_review_logged.sh S1-004 --model k2.5 --uncommitted --title "S1-004: WIP Kimi review"
  plans/kimi_review_logged.sh S1-004 --base run/slice1-clean --title "S1-004: review vs integration"
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
model="k2.5"
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
    --model)
      model="${2:?missing model}"
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

if [[ -z "$title" ]]; then
  title="$story: Kimi review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repo" >&2
  exit 2
}
cd "$root"

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/kimi"
else
  outdir="$root/$out_root/$story/kimi"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
stamp="${ts}_$$_${RANDOM}"
outfile="$outdir/${stamp}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
repo_head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"
artifact_head_sha="$repo_head_sha"

if [[ "$mode" == "commit" ]]; then
  resolved_commit="$(git rev-parse "${commit}^{commit}" 2>/dev/null || true)"
  [[ -n "$resolved_commit" ]] || {
    echo "ERROR: --commit ref is not a valid commit: $commit" >&2
    exit 2
  }
  artifact_head_sha="$resolved_commit"
fi

supports_review_subcommand() {
  set +e
  kimi review -h >/dev/null 2>&1
  local rc=$?
  set -e
  [[ $rc -eq 0 ]]
}

cmd_mode="review-subcommand"
cmd=()
if supports_review_subcommand; then
  cmd=("kimi" "review" "--model" "$model" "--title" "$title")
  case "$mode" in
    commit)
      cmd+=("--commit" "$commit")
      ;;
    base)
      cmd+=("--base" "$base")
      ;;
    uncommitted)
      cmd+=("--uncommitted")
      ;;
  esac
else
  cmd_mode="print-prompt"
  review_target=""
  case "$mode" in
    commit)
      review_target="Review commit '$commit' (resolved $artifact_head_sha; repo HEAD $repo_head_sha)."
      ;;
    base)
      review_target="Review diff from base '$base' to HEAD '$repo_head_sha'."
      ;;
    uncommitted)
      review_target="Review uncommitted changes in the current worktree (HEAD $repo_head_sha)."
      ;;
  esac
  review_prompt="You are reviewing story $story on branch $branch.
$review_target
Return findings ordered by severity with file references. Focus on correctness risks, regressions, and missing tests."
  cmd=("kimi" "--print" "--model" "$model" "--work-dir" "$root" "--prompt" "$review_prompt")
fi
if [[ ${#extra[@]} -gt 0 ]]; then
  cmd+=("${extra[@]}")
fi

transcript_tmp="$(mktemp)"
cleanup() {
  rm -f "$transcript_tmp"
}
trap cleanup EXIT

set +e
"${cmd[@]}" 2>&1 | tee "$transcript_tmp"
rc="${PIPESTATUS[0]}"
set -e

printf '\n' >> "$transcript_tmp"
transcript_hash="$(sha256_file "$transcript_tmp")"
transcript_bytes="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"

{
  echo "# Kimi review"
  echo
  echo "- Story: $story"
  echo "- Timestamp (UTC): $ts"
  echo "- Branch: $branch"
  echo "- Repo HEAD: $repo_head_sha"
  echo "- HEAD: $artifact_head_sha"
  echo "- Model: $model"
  echo "- Command mode: $cmd_mode"
  echo "- Mode: $mode"
  if [[ "$mode" == "commit" ]]; then
    echo "- Commit ref: $commit"
    echo "- Reviewed commit SHA: $artifact_head_sha"
  fi
  if [[ "$mode" == "base" ]]; then
    echo "- Base ref: $base"
  fi
  echo "- Command: ${cmd[*]}"
  echo "- Artifact Provenance: logger-v1"
  echo "- Generator Script: plans/kimi_review_logged.sh"
  echo "- Command Exit Code: $rc"
  echo "- Transcript SHA256: $transcript_hash"
  echo "- Transcript Bytes: $transcript_bytes"
  echo
  echo "<<<REVIEW_TRANSCRIPT_BEGIN>>>"
} > "$outfile"
cat "$transcript_tmp" >> "$outfile"
echo "<<<REVIEW_TRANSCRIPT_END>>>" >> "$outfile"

echo "Saved Kimi review: $outfile" >&2
exit "$rc"
