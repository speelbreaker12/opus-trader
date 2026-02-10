#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  plans/codex_review_logged.sh STORY_ID [--commit REF | --base REF | --uncommitted] [--title TITLE] [--out-root PATH] [-- <extra codex args>]

Defaults:
  --commit HEAD
  --title "<STORY_ID>: Codex review"
  --out-root "${CODEX_ARTIFACTS_ROOT:-artifacts/story}"

Artifacts:
  - Raw review:   artifacts/story/<ID>/codex/<UTC_TS>_review.md
  - Digest review: artifacts/story/<ID>/codex/<UTC_TS>_digest.md (best effort)

Examples:
  plans/codex_review_logged.sh S1-004 --commit HEAD --title "S1-004: OrderSize canonical sizing"
  plans/codex_review_logged.sh S1-004 --uncommitted --title "S1-004: WIP review"
  plans/codex_review_logged.sh S1-004 --base run/slice1-clean --title "S1-004: review vs integration"
  plans/codex_review_logged.sh S1-004 --commit HEAD -- --c model="o3"
EOF
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
out_root="${CODEX_ARTIFACTS_ROOT:-artifacts/story}"
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
  title="$story: Codex review"
fi

if [[ "$mode" == "base" && -z "$base" ]]; then
  echo "ERROR: --base requires a ref" >&2
  exit 2
fi

root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$root"

if [[ "$out_root" = /* ]]; then
  outdir="$out_root/$story/codex"
else
  outdir="$root/$out_root/$story/codex"
fi
mkdir -p "$outdir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
outfile="$outdir/${ts}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
head_sha="$(git rev-parse HEAD 2>/dev/null || echo "?")"

cmd=("codex" "review" "--title" "$title")
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
if [[ ${#extra[@]} -gt 0 ]]; then
  cmd+=("${extra[@]}")
fi

{
  echo "# Codex review"
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
  echo "- Command: ${cmd[*]}"
  echo
  echo "---"
  echo
} > "$outfile"

set +e
"${cmd[@]}" 2>&1 | tee -a "$outfile"
rc="${PIPESTATUS[0]}"
set -e

digest_script="$root/plans/codex_review_digest.sh"
if [[ -x "$digest_script" ]]; then
  if ! "$digest_script" "$outfile" >&2; then
    echo "WARN: failed to generate digest for $outfile" >&2
  fi
else
  echo "WARN: digest script not executable (skipping): $digest_script" >&2
fi

echo "Saved Codex review: $outfile" >&2
exit "$rc"
