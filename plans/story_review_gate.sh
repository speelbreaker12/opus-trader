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
  - artifacts/story/<ID>/codex/*_review.md containing:
      - Story: <ID>
      - HEAD: <sha>
  - artifacts/story/<ID>/review_resolution.md with:
      Story: <ID>
      HEAD: <sha>
      Blocking addressed: YES
      Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
      Codex final review file: <path>   (must exist and match HEAD)

Artifact root selection:
  --artifacts-root overrides all.
  Else uses STORY_ARTIFACTS_ROOT, else CODEX_ARTIFACTS_ROOT, else artifacts/story.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

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

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$repo_root"

if [[ -z "$HEAD_SHA" ]]; then
  HEAD_SHA="$(git rev-parse HEAD 2>/dev/null)" || die "failed to read HEAD"
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

grep -Fq "Story: $story" "$self_file" || die "self-review missing 'Story: $story' ($self_file)"
grep -Fq "HEAD: $HEAD_SHA" "$self_file" || die "self-review not for current HEAD ($HEAD_SHA) ($self_file)"
grep -Fq "Decision: PASS" "$self_file" || die "self-review Decision is not PASS ($self_file)"
grep -Fq "Failure-Mode Review: DONE" "$self_file" || die "self-review missing 'Failure-Mode Review: DONE' ($self_file)"
grep -Fq "Strategic Failure Review: DONE" "$self_file" || die "self-review missing 'Strategic Failure Review: DONE' ($self_file)"

# ---------- Codex review (must match HEAD) ----------
codex_dir="$story_dir/codex"
codex_match=""
if [[ -d "$codex_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fq -- "- Story: $story" "$f" && grep -Fq -- "- HEAD: $HEAD_SHA" "$f"; then
      codex_match="$f"
      break
    fi
  done < <(find "$codex_dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort -r)
fi
[[ -n "$codex_match" ]] || die "missing Codex review artifact for HEAD=$HEAD_SHA in: $codex_dir"

# ---------- Resolution ----------
res_file="$story_dir/review_resolution.md"
[[ -f "$res_file" ]] || die "missing review resolution file: $res_file"

grep -Fq "Story: $story" "$res_file" || die "resolution missing 'Story: $story' ($res_file)"
grep -Fq "HEAD: $HEAD_SHA" "$res_file" || die "resolution not for current HEAD ($HEAD_SHA) ($res_file)"
grep -Fq "Blocking addressed: YES" "$res_file" || die "resolution missing 'Blocking addressed: YES' ($res_file)"
grep -Fq "Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0" "$res_file" || die "resolution must assert no BLOCKING/MAJOR/MEDIUM remain ($res_file)"

codex_ref_line="$(grep -E '^Codex final review file:' "$res_file" | head -n 1 || true)"
[[ -n "$codex_ref_line" ]] || die "resolution missing 'Codex final review file: ...' ($res_file)"

codex_ref_path="$(printf '%s' "$codex_ref_line" | sed -E 's/^Codex final review file:[[:space:]]*//; s/[[:space:]]+$//')"
[[ -n "$codex_ref_path" ]] || die "Codex final review file path is empty ($res_file)"

if [[ "$codex_ref_path" != /* ]]; then
  if [[ -f "$repo_root/$codex_ref_path" ]]; then
    codex_ref_path="$repo_root/$codex_ref_path"
  elif [[ -f "$story_dir/$codex_ref_path" ]]; then
    codex_ref_path="$story_dir/$codex_ref_path"
  elif [[ -f "$codex_dir/$codex_ref_path" ]]; then
    codex_ref_path="$codex_dir/$codex_ref_path"
  fi
fi
[[ -f "$codex_ref_path" ]] || die "Codex final review file not found: $codex_ref_path"

codex_dir_abs="$(canonical_path "$codex_dir")"
codex_ref_abs="$(canonical_path "$codex_ref_path")"
case "$codex_ref_abs" in
  "$codex_dir_abs"/*) ;;
  *)
    die "Codex final review file must be inside $codex_dir (got $codex_ref_abs)"
    ;;
esac

grep -Fq -- "- Story: $story" "$codex_ref_path" || die "referenced Codex file missing '- Story: $story' ($codex_ref_path)"
grep -Fq -- "- HEAD: $HEAD_SHA" "$codex_ref_path" || die "referenced Codex file does not match HEAD=$HEAD_SHA ($codex_ref_path)"

echo "OK: review gate passed for $story @ $HEAD_SHA"
echo "  self_review: $self_file"
echo "  codex_review: $codex_match"
echo "  resolution: $res_file"
