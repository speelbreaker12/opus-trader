#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/self_review_logged.sh <STORY_ID> [--decision DRAFT|PASS|FAIL] [--head <sha>] [--out-root <path>]

Writes a self-review template to:
  artifacts/story/<ID>/self_review/<UTC_TS>_self_review.md

Default decision is DRAFT (gate requires PASS).
USAGE
}

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

decision="DRAFT"
head_sha=""
out_root="${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --decision)
      decision="${2:?missing decision}"
      shift 2
      ;;
    --head)
      head_sha="${2:?missing sha}"
      shift 2
      ;;
    --out-root)
      out_root="${2:?missing path}"
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

case "$decision" in
  DRAFT|PASS|FAIL) ;;
  *)
    echo "ERROR: --decision must be DRAFT|PASS|FAIL" >&2
    exit 2
    ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$head_sha" ]]; then
  head_sha="$(git rev-parse HEAD 2>/dev/null)" || { echo "ERROR: failed to read HEAD" >&2; exit 2; }
fi

if [[ "$out_root" != /* ]]; then
  out_root="$repo_root/$out_root"
fi

dir="$out_root/$story/self_review"
mkdir -p "$dir"

ts="$(date -u +%Y%m%dT%H%M%SZ)"
file="$dir/${ts}_self_review.md"

fm="TODO"
sf="TODO"
if [[ "$decision" == "PASS" ]]; then
  fm="DONE"
  sf="DONE"
fi

cat > "$file" <<EOF
# Self Review

Story: $story
HEAD: $head_sha
Timestamp (UTC): $ts
Decision: $decision

Checklist:
- Failure-Mode Review: $fm
- Strategic Failure Review: $sf
- Contract alignment checked: YES/NO
- Acceptance criteria met: YES/NO

## Failure-Mode Review Notes
- (inputs / error paths / edge cases / concrete walkthrough)

## Strategic Failure Review Notes
- (assumptions / complexity-to-benefit / simpler alternative)

## Risks / Follow-ups
- (if any)
EOF

echo "Saved self review: $file"
