#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/postmortem_gate.sh <STORY_ID> [--head <sha>] [--artifacts-root <path>]

Purpose:
  Fail-closed gate for TOC-style postmortem artifacts.
  Exit 0 only if all checks pass.

Exit codes:
  0 = pass
  1 = validation failure
  2 = usage error
USAGE
}

die() { echo "FAIL: $*" >&2; exit 1; }

require_fixed_line() {
  local file="$1" expected="$2" message="$3"
  grep -Fxq -- "$expected" "$file" || die "$message"
}

require_heading() {
  local file="$1" heading="$2"
  grep -Fxq -- "$heading" "$file" || die "missing required heading: $heading"
}

# Extract section content between a heading and the next ## heading (or EOF)
section_content() {
  local file="$1" heading="$2"
  sed -n "/^${heading}/,/^## [0-9]/{/^## /d; p;}" "$file" | grep -v '^[[:space:]]*$' || true
}

# --- args ---
story_id="${1:-}"
[[ -n "$story_id" ]] || { usage >&2; exit 2; }
shift

head_sha=""
artifacts_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)       head_sha="${2:?missing sha}"; shift 2 ;;
    --artifacts-root) artifacts_root="${2:?missing path}"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *)            echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

[[ -z "$head_sha" ]] && head_sha="$(git rev-parse HEAD 2>/dev/null)" || true
[[ "$artifacts_root" != /* ]] && artifacts_root="$repo_root/$artifacts_root"

# --- artifact exists ---
pm="$artifacts_root/$story_id/postmortem.md"
[[ -f "$pm" ]] || die "postmortem artifact not found: $pm"

# --- fixed lines ---
require_fixed_line "$pm" "Story: $story_id" "Story ID line missing or wrong"

if [[ -n "$head_sha" ]]; then
  require_fixed_line "$pm" "HEAD: $head_sha" "HEAD line missing or does not match $head_sha"
fi

# --- STOPLIGHT ---
grep -Eq '^STOPLIGHT: (GREEN|YELLOW|RED)$' "$pm" || die "missing or invalid STOPLIGHT line"

# --- Constraint Class ---
grep -Eq '^(\*\*)?Constraint Class:(\*\*)? .+' "$pm" || die "missing Constraint Class line"

# --- required section headings ---
require_heading "$pm" "## 1) Constraint Summary"
require_heading "$pm" "## 2) TOC Five Focusing Steps"
require_heading "$pm" "## 3) Causal Chain (show the failure path)"
require_heading "$pm" "## 5) What Was Missing (be explicit)"
require_heading "$pm" "## 6) Rule Updates (what changes permanently)"
require_heading "$pm" "## 9) Completion Checklist (postmortem quality gate)"

# --- no placeholder markers ---
for marker in '<TODO>' 'TBD' 'FILL_ME'; do
  if grep -Fq -- "$marker" "$pm"; then
    die "placeholder marker found: $marker"
  fi
done

# --- constraint summary non-empty (section 1) ---
s1=$(section_content "$pm" "## 1) Constraint Summary")
if [[ -z "$s1" ]]; then
  die "section 1 (Constraint Summary) is empty"
fi
char_count=$(echo "$s1" | tr -d '[:space:]' | wc -c | tr -d ' ')
if [[ "$char_count" -lt 15 ]]; then
  die "section 1 (Constraint Summary) too short ($char_count chars, need >=15)"
fi

# --- wrong-implementation risk in section 5 ---
s5=$(section_content "$pm" "## 5) What Was Missing")
echo "$s5" | grep -Fq "Wrong-Implementation Risk" || die "section 5 missing 'Wrong-Implementation Risk' subsection"

# --- rule updates table has content (section 6) ---
s6=$(section_content "$pm" "## 6) Rule Updates")
if [[ -z "$s6" ]]; then
  die "section 6 (Rule Updates) is empty"
fi
# Must contain at least one concrete file path or layer reference
has_path=0
for token in 'plans/' 'SKILLS/' 'docs/' 'crates/' 'CLAUDE.md' 'specs/' 'python/' 'Contract' 'PRD' 'Tests' 'Gate' 'Prompt' 'Pattern'; do
  if echo "$s6" | grep -Fq -- "$token"; then
    has_path=1
    break
  fi
done
[[ "$has_path" -eq 1 ]] || die "section 6 (Rule Updates) must reference concrete layers or file paths"

# --- next-story startup note (section 8) ---
s8=$(section_content "$pm" "## 8) Next-Story Startup Note")
if [[ -z "$s8" ]]; then
  die "section 8 (Next-Story Startup Note) is empty"
fi

# --- completion checklist (section 9) ---
s9=$(section_content "$pm" "## 9) Completion Checklist")
echo "$s9" | grep -Fq "Constraint named clearly" || die "section 9 missing checklist item: 'Constraint named clearly'"
echo "$s9" | grep -Fq "Wrong implementation risk" || die "section 9 missing checklist item: 'Wrong implementation risk'"
echo "$s9" | grep -Fq "Permanent rule/gate/test" || die "section 9 missing checklist item: 'Permanent rule/gate/test'"

# --- pass ---
echo "OK: postmortem gate passed for $story_id"
echo "  artifact: $pm"
echo "  stoplight: $(grep -oE 'STOPLIGHT: (GREEN|YELLOW|RED)' "$pm")"
