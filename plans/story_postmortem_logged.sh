#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/story_postmortem_logged.sh <STORY_ID> [--head <sha>] [--out-root <path>] [--verify-artifacts <dir>]

Writes:
  artifacts/story/<ID>/postmortem/<UTC_TS>_postmortem.md
USAGE
}

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

head_sha=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"
verify_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
      shift 2
      ;;
    --verify-artifacts)
      verify_dir="${2:?missing dir}"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read HEAD" >&2; exit 2; }
fi

if [[ "$out_root" != /* ]]; then
  out_root="$repo_root/$out_root"
fi

dir="$out_root/$story/postmortem"
mkdir -p "$dir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
file="$dir/${ts}_postmortem.md"

cat > "$file" <<EOF
# Story Postmortem

Story: $story
HEAD: $head_sha
Timestamp (UTC): $ts

## What shipped
- (1-3 bullets)

## Where it hurt (friction)
- (what was confusing, slow, error-prone)

## Codex findings -> fixes
- Codex review artifacts:
  - (paste paths to artifacts/story/$story/codex/*_review.md and/or *_digest.md)
- Blocking/major issues and how they were fixed:
  - Issue:
    Fix:
    Root cause:

## Verify failures -> fixes
- Verify artifacts dir: ${verify_dir:-<fill>}
- FAILED_GATE (if any):
- Fix applied:
- Root cause:

## Root cause analysis (why did I make the mistakes?)
Choose all that apply:
- [ ] Misread contract (cite section)
- [ ] Skipped a self-review step
- [ ] Incomplete concrete walkthrough
- [ ] Tests did not cover the failure mode
- [ ] Tooling / environment issue
- [ ] Other:

## Process improvement (one change)
- What I will change next story to prevent repeat:
EOF

echo "Saved postmortem: $file"
