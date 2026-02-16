#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/code_review_expert_logged.sh STORY_ID [--head <sha>] [--status DRAFT|COMPLETE] [--title <text>] [--out-root <path>] [--from-file <path>] [--from-stdin]

Writes a findings-review artifact to:
  artifacts/story/<STORY_ID>/code_review_expert/<UTC_TS>_review.md

Content source (priority):
  1) --from-file
  2) --from-stdin
  3) placeholder template
USAGE
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

head_sha=""
status="DRAFT"
title=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
from_file=""
from_stdin=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --status)
      status="${2:?missing status}"
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
    --from-file)
      from_file="${2:?missing path}"
      shift 2
      ;;
    --from-stdin)
      from_stdin=1
      shift 1
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$status" in
  DRAFT|COMPLETE) ;;
  *)
    echo "ERROR: --status must be DRAFT or COMPLETE" >&2
    exit 2
    ;;
esac

if [[ -n "$from_file" && "$from_stdin" -eq 1 ]]; then
  echo "ERROR: choose only one content source: --from-file or --from-stdin" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read HEAD" >&2; exit 2; }
fi

if [[ -z "$title" ]]; then
  title="$story: code-review-expert findings"
fi

if [[ "$out_root" != /* ]]; then
  out_root="$repo_root/$out_root"
fi

out_dir="$out_root/$story/code_review_expert"
mkdir -p "$out_dir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
stamp="${ts}_$$_${RANDOM}"
out_file="$out_dir/${stamp}_review.md"

branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")"
content_source="template"
findings_tmp="$(mktemp)"
cleanup() {
  rm -f "$findings_tmp"
}
trap cleanup EXIT

if [[ -n "$from_file" ]]; then
  [[ -f "$from_file" ]] || { echo "ERROR: --from-file not found: $from_file" >&2; exit 2; }
  content_source="from-file"
  cat "$from_file" > "$findings_tmp"
elif [[ "$from_stdin" -eq 1 ]]; then
  [[ ! -t 0 ]] || { echo "ERROR: --from-stdin requires piped input" >&2; exit 2; }
  content_source="from-stdin"
  cat > "$findings_tmp"
else
  content_source="template"
  cat > "$findings_tmp" <<'TEMPLATE'
- Blocking: <none | summary>
- Major: <none | summary>
- Medium: <none | summary>

## Actions
- Tests added from top findings:
- Fixes applied:

## Final Disposition
- Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
TEMPLATE
fi

printf '\n' >> "$findings_tmp"
findings_hash="$(sha256_file "$findings_tmp")"
findings_bytes="$(wc -c < "$findings_tmp" | tr -d '[:space:]')"

{
  echo "# Code-review-expert findings"
  echo
  echo "- Story: $story"
  echo "- HEAD: $head_sha"
  echo "- Timestamp (UTC): $ts"
  echo "- Branch: $branch"
  echo "- Skill Path: ~/.agents/skills/code-review-expert/SKILL.md"
  echo "- Review Status: $status"
  echo "- Title: $title"
  echo "- Artifact Provenance: logger-v1"
  echo "- Generator Script: plans/code_review_expert_logged.sh"
  echo "- Content Source: $content_source"
  echo "- Findings SHA256: $findings_hash"
  echo "- Findings Bytes: $findings_bytes"
  echo
  echo "## Findings"
  echo
  echo "<<<FINDINGS_BEGIN>>>"
} > "$out_file"
cat "$findings_tmp" >> "$out_file"
echo "<<<FINDINGS_END>>>" >> "$out_file"

echo "Saved code-review-expert artifact: $out_file"
