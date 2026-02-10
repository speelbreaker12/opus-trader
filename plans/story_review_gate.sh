#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  ./plans/story_review_gate.sh <STORY_ID> [--head <sha>] [--artifacts-root <path>]

Purpose:
  Fail-closed gate that enforces review evidence exists for the current HEAD.

Requires (for HEAD):
  - artifacts/story/<ID>/self_review/*_self_review.md with:
      Story: <ID>
      HEAD: <sha>
      Decision: PASS
      Failure-Mode Review: DONE
      Strategic Failure Review: DONE
  - artifacts/story/<ID>/kimi/*_review.md containing:
      - Story: <ID>
      - HEAD: <sha>
  - artifacts/story/<ID>/codex/*_review.md containing:
      - Story: <ID>
      - HEAD: <sha>
    and at least 2 Codex review artifacts must match HEAD.
  - artifacts/story/<ID>/review_resolution.md with:
      Story: <ID>
      HEAD: <sha>
      Blocking addressed: YES
      Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
      Kimi final review file: <path>   (must exist and match HEAD)
      Codex final review file: <path>   (must exist and match HEAD)
      Codex second review file: <path>  (must exist and match HEAD)
    template: plans/review_resolution_template.md

Artifact root selection:
  --artifacts-root overrides all.
  Else uses STORY_ARTIFACTS_ROOT, else CODEX_ARTIFACTS_ROOT, else artifacts/story.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

require_fixed_line() {
  local file="$1"
  local expected="$2"
  local message="$3"
  grep -Fxq -- "$expected" "$file" || die "$message ($file)"
}

canonical_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
    return 0
  fi
  (
    cd "$(dirname "$path")" && \
      printf '%s/%s\n' "$(pwd -P)" "$(basename "$path")"
  )
}

latest_matching_file() {
  local dir="$1"
  local pattern="$2"
  if [[ ! -d "$dir" ]]; then
    return 0
  fi
  find "$dir" -maxdepth 1 -type f -name "$pattern" | LC_ALL=C sort -r | head -n 1
}

validate_review_reference() {
  local res_file="$1"
  local label="$2"
  local prefix="$3"
  local review_dir="$4"

  local ref_line ref_path ref_abs review_dir_abs
  ref_line="$(grep -E "^${prefix}[[:space:]]*" "$res_file" | head -n 1 || true)"
  [[ -n "$ref_line" ]] || die "resolution missing '${label}: ...' ($res_file)"

  ref_path="$(printf '%s' "$ref_line" | sed -E "s#^${prefix}[[:space:]]*##; s/[[:space:]]+$//")"
  [[ -n "$ref_path" ]] || die "${label} path is empty ($res_file)"
  [[ "$ref_path" == *_review.md ]] || die "${label} must be a *_review.md artifact: $ref_path"

  if [[ "$ref_path" != /* ]]; then
    if [[ -f "$repo_root/$ref_path" ]]; then
      ref_path="$repo_root/$ref_path"
    elif [[ -f "$story_dir/$ref_path" ]]; then
      ref_path="$story_dir/$ref_path"
    elif [[ -f "$review_dir/$ref_path" ]]; then
      ref_path="$review_dir/$ref_path"
    fi
  fi
  [[ -f "$ref_path" ]] || die "${label} not found: $ref_path"

  review_dir_abs="$(canonical_path "$review_dir")"
  ref_abs="$(canonical_path "$ref_path")"
  case "$ref_abs" in
    "$review_dir_abs"/*) ;;
    *)
      die "${label} must be inside $review_dir (got $ref_abs)"
      ;;
  esac

  grep -Fxq -- "- Story: $story" "$ref_path" || die "referenced ${label} missing '- Story: $story' ($ref_path)"
  grep -Fxq -- "- HEAD: $HEAD_SHA" "$ref_path" || die "referenced ${label} does not match HEAD=$HEAD_SHA ($ref_path)"

  printf '%s\n' "$ref_path"
}

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

HEAD_SHA=""
ART_ROOT_OVERRIDE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --head)
      HEAD_SHA="${2:?missing sha}"
      shift 2
      ;;
    --artifacts-root)
      ART_ROOT_OVERRIDE="${2:?missing path}"
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

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd -P)"
cd "$repo_root"

if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git -C "$repo_root" rev-parse HEAD 2>/dev/null)" || die "failed to read HEAD"
fi

art_root="${ART_ROOT_OVERRIDE:-${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}}"
if [[ "$art_root" != /* ]]; then
  art_root="$repo_root/$art_root"
fi
story_dir="$art_root/$story"

# ---------- Self review ----------
self_dir="$story_dir/self_review"
self_file="$(latest_matching_file "$self_dir" '*_self_review.md')"
[[ -n "$self_file" && -f "$self_file" ]] || die "missing self-review artifact in: $self_dir"

require_fixed_line "$self_file" "Story: $story" "self-review missing 'Story: $story'"
require_fixed_line "$self_file" "HEAD: $HEAD_SHA" "self-review not for current HEAD ($HEAD_SHA)"
require_fixed_line "$self_file" "Decision: PASS" "self-review Decision is not PASS"
require_fixed_line "$self_file" "- Failure-Mode Review: DONE" "self-review missing '- Failure-Mode Review: DONE'"
require_fixed_line "$self_file" "- Strategic Failure Review: DONE" "self-review missing '- Strategic Failure Review: DONE'"

# ---------- Kimi review (must match HEAD) ----------
kimi_dir="$story_dir/kimi"
kimi_match=""
if [[ -d "$kimi_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $HEAD_SHA" "$f"; then
      kimi_match="$f"
      break
    fi
  done < <(find "$kimi_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
fi
[[ -n "$kimi_match" ]] || die "missing Kimi review artifact for HEAD=$HEAD_SHA in: $kimi_dir"

# ---------- Codex review(s) (must match HEAD) ----------
codex_dir="$story_dir/codex"
codex_matches=()
if [[ -d "$codex_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $HEAD_SHA" "$f"; then
      codex_matches+=("$f")
    fi
  done < <(find "$codex_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
fi
[[ "${#codex_matches[@]}" -ge 2 ]] || die "need at least two Codex review artifacts for HEAD=$HEAD_SHA in: $codex_dir"

# ---------- Resolution ----------
res_file="$story_dir/review_resolution.md"
[[ -f "$res_file" ]] || die "missing review resolution file: $res_file"

require_fixed_line "$res_file" "Story: $story" "resolution missing 'Story: $story'"
require_fixed_line "$res_file" "HEAD: $HEAD_SHA" "resolution not for current HEAD ($HEAD_SHA)"
require_fixed_line "$res_file" "Blocking addressed: YES" "resolution missing 'Blocking addressed: YES'"
require_fixed_line "$res_file" "Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0" "resolution must assert no BLOCKING/MAJOR/MEDIUM remain"
kimi_ref_path="$(validate_review_reference "$res_file" "Kimi final review file" "Kimi final review file:" "$kimi_dir")"
codex_final_ref_path="$(validate_review_reference "$res_file" "Codex final review file" "Codex final review file:" "$codex_dir")"
codex_second_ref_path="$(validate_review_reference "$res_file" "Codex second review file" "Codex second review file:" "$codex_dir")"

if [[ "$(canonical_path "$codex_final_ref_path")" == "$(canonical_path "$codex_second_ref_path")" ]]; then
  die "Codex final review file and Codex second review file must be different artifacts"
fi

echo "OK: review gate passed for $story @ $HEAD_SHA"
echo "  self_review: $self_file"
echo "  kimi_review: $kimi_match"
echo "  codex_reviews: ${#codex_matches[@]}"
echo "  kimi_resolution_ref: $kimi_ref_path"
echo "  codex_final_ref: $codex_final_ref_path"
echo "  codex_second_ref: $codex_second_ref_path"
echo "  resolution: $res_file"
