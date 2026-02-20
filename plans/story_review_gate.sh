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
      - Artifact Provenance: logger-v1
      - Generator Script: plans/kimi_review_logged.sh
      - Command Exit Code: 0
      - Transcript SHA256: <sha256>
      - transcript block between <<<REVIEW_TRANSCRIPT_BEGIN>>> / <<<REVIEW_TRANSCRIPT_END>>>
  - artifacts/story/<ID>/codex/*_review.md OR artifacts/story/<ID>/opus/*_review.md containing:
      - Story: <ID>
      - HEAD: <sha>
      - Artifact Provenance: logger-v1
      - Generator Script: plans/codex_review_logged.sh OR plans/opus_review_logged.sh
      - Command Exit Code: 0
      - Transcript SHA256: <sha256>
      - transcript block between <<<REVIEW_TRANSCRIPT_BEGIN>>> / <<<REVIEW_TRANSCRIPT_END>>>
    and at least 2 Codex/Opus review artifacts must match HEAD.
  - artifacts/story/<ID>/code_review_expert/*_review.md containing:
      - Story: <ID>
      - HEAD: <sha>
      - Review Status: COMPLETE
      - Artifact Provenance: logger-v1
      - Generator Script: plans/code_review_expert_logged.sh
      - Content Source: template|from-file|from-stdin
      - Findings SHA256: <sha256>
      - findings block between <<<FINDINGS_BEGIN>>> / <<<FINDINGS_END>>>
  - artifacts/story/<ID>/review_resolution.md with:
      Story: <ID>
      HEAD: <sha>
      Blocking addressed: YES
      Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0
      Kimi final review file: <path>   (must exist and match HEAD)
      Codex final review file: <path>   (must exist and match HEAD)
      Codex second review file: <path>  (must exist and match HEAD)
      Code-review-expert final review file: <path>  (must exist and match HEAD)
    template: plans/review_resolution_template.md
  - artifacts/story/<ID>/supervisor/ with PASS verdicts for:
      post-cycle1, post-fix, post-cycle2
    (set REQUIRE_SUPERVISOR=0 to skip)

Artifact root selection:
  --artifacts-root overrides all.
  Else uses STORY_ARTIFACTS_ROOT, else CODEX_ARTIFACTS_ROOT, else artifacts/story.
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }
warn() { echo "WARN: $*" >&2; }

# ── Anti-fabrication checks ──────────────────────────────────────────

MIN_TRANSCRIPT_BYTES="${MIN_TRANSCRIPT_BYTES:-500}"
MIN_REVIEW_DURATION="${MIN_REVIEW_DURATION:-3}"

validate_transcript_quality() {
  local file="$1"
  local label="$2"
  local start_marker="$3"
  local end_marker="$4"
  local start_line="" end_line="" transcript_tmp="" byte_count=0

  # Extract transcript block
  start_line="$(grep -Fn -- "$start_marker" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -Fn -- "$end_marker" "$file" | tail -n 1 | cut -d: -f1)"
  transcript_tmp="$(mktemp)"
  sed -n "$((start_line + 1)),$((end_line - 1))p" "$file" > "$transcript_tmp"

  # 1) Minimum byte count
  byte_count="$(wc -c < "$transcript_tmp" | tr -d '[:space:]')"
  if [[ "$byte_count" -lt "$MIN_TRANSCRIPT_BYTES" ]]; then
    rm -f "$transcript_tmp"
    die "${label} transcript too short (${byte_count} bytes, minimum ${MIN_TRANSCRIPT_BYTES}): likely fabricated ($file)"
  fi

  # 2) Must contain file path references (file.ext or path/file patterns)
  local path_refs=0
  path_refs="$(grep -cE '(crates/|src/|tests/|plans/|specs/|python/|[a-zA-Z_]+\.(rs|py|sh|md|json|toml):[0-9]+)' "$transcript_tmp" || true)"
  if [[ "$path_refs" -lt 2 ]]; then
    rm -f "$transcript_tmp"
    die "${label} transcript has no file path references (found ${path_refs}, need ≥2): review must reference actual code ($file)"
  fi

  # 3) Must contain severity markers
  local severity_refs=0
  severity_refs="$(grep -ciE '\b(P[0-3]|Critical|High|Medium|Low|Blocking|MAJOR|MINOR|finding|issue)\b' "$transcript_tmp" || true)"
  if [[ "$severity_refs" -lt 1 ]]; then
    rm -f "$transcript_tmp"
    die "${label} transcript has no severity markers: review must classify findings ($file)"
  fi

  rm -f "$transcript_tmp"
}

validate_review_timing() {
  local file="$1"
  local label="$2"
  local duration=""

  # Check for Duration Seconds field
  duration="$(grep -oE '^- Duration Seconds: [0-9]+' "$file" | head -1 | grep -oE '[0-9]+$' || true)"
  if [[ -z "$duration" ]]; then
    die "${label} missing 'Duration Seconds' field — cannot verify review timing ($file)"
  fi
  if [[ "$duration" -lt "$MIN_REVIEW_DURATION" ]]; then
    die "${label} completed in ${duration}s (minimum ${MIN_REVIEW_DURATION}s): too fast for a real review ($file)"
  fi
}

# Count P0+P1 severity markers in a transcript block
# Returns the count via stdout
count_high_severity() {
  local file="$1"
  local start_marker="$2"
  local end_marker="$3"
  local start_line="" end_line="" transcript_tmp="" count=0

  start_line="$(grep -Fn -- "$start_marker" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -Fn -- "$end_marker" "$file" | tail -n 1 | cut -d: -f1)"
  transcript_tmp="$(mktemp)"
  sed -n "$((start_line + 1)),$((end_line - 1))p" "$file" > "$transcript_tmp"

  # Count lines with structured severity markers (headers, tables, bold markers)
  # Avoid matching prose like "no remaining high severity" or "critical path"
  count="$(grep -cE '(##\s*P[01]\b|\bP[01]\s*[-:|]|\*\*P[01]\*\*|\|\s*P[01]\s*\|)' "$transcript_tmp" || true)"
  rm -f "$transcript_tmp"
  printf '%s\n' "$count"
}

# Extract timestamp from review artifact (UTC ISO field)
extract_review_timestamp() {
  local file="$1"
  grep -oE '^- Timestamp \(UTC\): [0-9T:Z]+' "$file" | head -1 | sed 's/^- Timestamp (UTC): //' || true
}

validate_diff_cross_reference() {
  local file="$1"
  local label="$2"
  local start_marker="$3"
  local end_marker="$4"
  local diff_files_str="$5"
  local start_line="" end_line="" transcript_tmp="" matches=0

  [[ -n "$diff_files_str" ]] || return 0  # skip if no diff available

  start_line="$(grep -Fn -- "$start_marker" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -Fn -- "$end_marker" "$file" | tail -n 1 | cut -d: -f1)"
  transcript_tmp="$(mktemp)"
  sed -n "$((start_line + 1)),$((end_line - 1))p" "$file" > "$transcript_tmp"

  # Check if transcript mentions at least one file from the diff
  while IFS= read -r diff_file; do
    [[ -n "$diff_file" ]] || continue
    local basename=""
    basename="$(basename "$diff_file")"
    if grep -qF "$basename" "$transcript_tmp"; then
      matches=$((matches + 1))
    fi
  done <<< "$diff_files_str"

  rm -f "$transcript_tmp"

  if [[ "$matches" -lt 1 ]]; then
    die "${label} transcript does not reference any files from the diff: review must engage with actual changes ($file)"
  fi
}

require_fixed_line() {
  local file="$1"
  local expected="$2"
  local message="$3"
  grep -Fxq -- "$expected" "$file" || die "$message ($file)"
}

sha256_file() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  shasum -a 256 "$file" | awk '{print $1}'
}

extract_sha256_field() {
  local file="$1"
  local field="$2"
  local label="$3"
  local line=""
  local line_count=0

  line_count="$(grep -Ec "^- ${field}: [0-9a-f]{64}$" "$file" || true)"
  [[ "$line_count" == "1" ]] || die "${label} must contain exactly one SHA256 marker '- ${field}: <sha256>' ($file)"
  line="$(grep -E "^- ${field}: [0-9a-f]{64}$" "$file" | head -n 1 || true)"
  printf '%s\n' "${line#- ${field}: }"
}

verify_hashed_block() {
  local file="$1"
  local field="$2"
  local start_marker="$3"
  local end_marker="$4"
  local label="$5"
  local expected_hash=""
  local actual_hash=""
  local start_count=0
  local end_count=0
  local start_line=""
  local end_line=""
  local block_tmp=""

  expected_hash="$(extract_sha256_field "$file" "$field" "$label")"

  start_count="$(grep -Fxc -- "$start_marker" "$file" || true)"
  end_count="$(grep -Fxc -- "$end_marker" "$file" || true)"
  [[ "$start_count" -ge 1 ]] || die "${label} missing start marker '$start_marker' ($file)"
  [[ "$end_count" -ge 1 ]] || die "${label} missing end marker '$end_marker' ($file)"
  [[ "$start_count" == "$end_count" ]] || die "${label} marker counts must be balanced (start=$start_count end=$end_count) in $file"

  # Log when markers appear multiple times (e.g., in transcript content discussing review format)
  if [[ "$start_count" -gt 1 ]] || [[ "$end_count" -gt 1 ]]; then
    echo "INFO: ${label} has nested markers (start=$start_count, end=$end_count), using first start and last end" >&2
  fi

  start_line="$(grep -Fn -- "$start_marker" "$file" | head -n 1 | cut -d: -f1)"
  end_line="$(grep -Fn -- "$end_marker" "$file" | tail -n 1 | cut -d: -f1)"
  [[ "$end_line" -gt "$start_line" ]] || die "${label} marker order is invalid in $file"

  block_tmp="$(mktemp)"
  sed -n "$((start_line + 1)),$((end_line - 1))p" "$file" > "$block_tmp"
  actual_hash="$(sha256_file "$block_tmp")"
  rm -f "$block_tmp"

  [[ "$actual_hash" == "$expected_hash" ]] || die "${label} hash mismatch ($file)"
}

canonical_path() {
  local path="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$path"
    return 0
  fi
  if command -v python3 >/dev/null 2>&1; then
    local resolved=""
    resolved="$(
      python3 - "$path" <<'PY'
import os
import sys

print(os.path.realpath(sys.argv[1]))
PY
    )" || die "canonical_path: python3 realpath failed for $path"
    [[ -n "$resolved" ]] || die "canonical_path: python3 realpath returned empty output for $path"
    printf '%s\n' "$resolved"
    return 0
  fi
  die "canonical_path: need either realpath or python3 for reliable path resolution"
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
  grep -Fxq -- "- HEAD: $REVIEW_HEAD_SHA" "$ref_path" || die "referenced ${label} does not match HEAD=$REVIEW_HEAD_SHA ($ref_path)"

  printf '%s\n' "$ref_path"
}

find_self_review_for_head() {
  local self_dir="$1"
  local story_id="$2"
  local head_sha="$3"
  local match=""

  if [[ -d "$self_dir" ]]; then
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      if grep -Fxq -- "Story: $story_id" "$f" && grep -Fxq -- "HEAD: $head_sha" "$f"; then
        match="$f"
        break
      fi
    done < <(find "$self_dir" -maxdepth 1 -type f -name '*_self_review.md' | LC_ALL=C sort -r)
  fi

  printf '%s\n' "$match"
}

resolve_artifact_only_parent_head() {
  local head_sha="$1"
  local story_id="$2"
  local parent_sha=""
  local changed_paths=""
  local path=""

  [[ "$head_sha" =~ ^[0-9a-f]{40}$ ]] || return 1
  git cat-file -e "${head_sha}^{commit}" >/dev/null 2>&1 || return 1
  parent_sha="$(git rev-parse "${head_sha}^" 2>/dev/null || true)"
  [[ -n "$parent_sha" ]] || return 1

  changed_paths="$(git diff --name-only "$parent_sha..$head_sha" 2>/dev/null || true)"
  [[ -n "$changed_paths" ]] || return 1

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      artifacts/story/"$story_id"/*) ;;
      *) return 1 ;;
    esac
  done <<< "$changed_paths"

  printf '%s\n' "$parent_sha"
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
REQUESTED_HEAD_SHA="$HEAD_SHA"
REVIEW_HEAD_SHA="$HEAD_SHA"

art_root="${ART_ROOT_OVERRIDE:-${STORY_ARTIFACTS_ROOT:-${CODEX_ARTIFACTS_ROOT:-artifacts/story}}}"
if [[ "$art_root" != /* ]]; then
  art_root="$repo_root/$art_root"
fi
story_dir="$art_root/$story"

# ---------- Self review ----------
self_dir="$story_dir/self_review"
self_file="$(find_self_review_for_head "$self_dir" "$story" "$REVIEW_HEAD_SHA")"
self_files_found=0
review_head_fallback=0
fallback_parent_sha=""
self_files_found=0
if [[ -d "$self_dir" ]]; then
  self_files_found="$(find "$self_dir" -maxdepth 1 -type f -name '*_self_review.md' | wc -l | tr -d ' ')"
fi
if [[ -z "$self_file" ]]; then
  fallback_parent_sha="$(resolve_artifact_only_parent_head "$REQUESTED_HEAD_SHA" "$story" || true)"
  if [[ -n "$fallback_parent_sha" ]]; then
    REVIEW_HEAD_SHA="$fallback_parent_sha"
    review_head_fallback=1
    self_file="$(find_self_review_for_head "$self_dir" "$story" "$REVIEW_HEAD_SHA")"
  fi
fi
if [[ -z "$self_file" ]]; then
  if [[ "$self_files_found" -eq 1 ]]; then
    die "self-review not for current HEAD ($REQUESTED_HEAD_SHA) in: $self_dir"
  fi
  die "missing self-review artifact in: $self_dir"
fi

# ── Compute diff files for cross-reference checks ──
diff_files=""
if git rev-parse --verify "$REVIEW_HEAD_SHA" >/dev/null 2>&1; then
  # Use BASE_HEAD from preflight receipt if available (covers full story diff, not just one commit).
  # Falls back to single-commit diff if no receipt chain exists.
  _base_head=""
  _git_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  _receipt_dir="${WF_RECEIPT_DIR:-${_git_root:-.}/.wf/receipts/$story}"
  _pf_receipt="$_receipt_dir/00_preflight.json"
  if [[ -f "$_pf_receipt" ]]; then
    _base_head="$(jq -r '.head_sha // ""' "$_pf_receipt" 2>/dev/null || true)"
  fi
  if [[ -n "$_base_head" ]]; then
    diff_files="$(git diff --name-only "${_base_head}..${REVIEW_HEAD_SHA}" 2>/dev/null || true)"
  else
    diff_files="$(git diff --name-only "${REVIEW_HEAD_SHA}^..${REVIEW_HEAD_SHA}" 2>/dev/null || true)"
  fi
fi

require_fixed_line "$self_file" "Story: $story" "self-review missing 'Story: $story'"
require_fixed_line "$self_file" "HEAD: $REVIEW_HEAD_SHA" "self-review not for current HEAD ($REVIEW_HEAD_SHA)"
require_fixed_line "$self_file" "Decision: PASS" "self-review Decision is not PASS"
require_fixed_line "$self_file" "- Failure-Mode Review: DONE" "self-review missing '- Failure-Mode Review: DONE'"
require_fixed_line "$self_file" "- Strategic Failure Review: DONE" "self-review missing '- Strategic Failure Review: DONE'"

# ---------- Kimi review (must match HEAD) ----------
kimi_dir="$story_dir/kimi"
kimi_match=""
if [[ -d "$kimi_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $REVIEW_HEAD_SHA" "$f"; then
      kimi_match="$f"
      break
    fi
  done < <(find "$kimi_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
fi
[[ -n "$kimi_match" ]] || die "missing Kimi review artifact for HEAD=$REVIEW_HEAD_SHA in: $kimi_dir"
require_fixed_line "$kimi_match" "- Artifact Provenance: logger-v1" "missing Kimi provenance marker"
require_fixed_line "$kimi_match" "- Generator Script: plans/kimi_review_logged.sh" "missing Kimi generator script marker"
require_fixed_line "$kimi_match" "- Command Exit Code: 0" "Kimi review command did not exit 0"
verify_hashed_block "$kimi_match" "Transcript SHA256" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>" "Kimi transcript"
validate_transcript_quality "$kimi_match" "Kimi" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>"
validate_review_timing "$kimi_match" "Kimi"
validate_diff_cross_reference "$kimi_match" "Kimi" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>" "$diff_files"

# ---------- Codex/Opus review(s) (must match HEAD) ----------
# Accept reviews from either codex or opus directories (opus is fallback for codex)
codex_dir="$story_dir/codex"
opus_dir="$story_dir/opus"
codex_matches=()
for review_search_dir in "$codex_dir" "$opus_dir"; do
  if [[ -d "$review_search_dir" ]]; then
    while IFS= read -r f; do
      [[ -f "$f" ]] || continue
      if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $REVIEW_HEAD_SHA" "$f"; then
        codex_matches+=("$f")
      fi
    done < <(find "$review_search_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
  fi
done
[[ "${#codex_matches[@]}" -ge 2 ]] || die "need at least two Codex/Opus review artifacts for HEAD=$REVIEW_HEAD_SHA in: $codex_dir or $opus_dir"
for codex_file in "${codex_matches[@]}"; do
  require_fixed_line "$codex_file" "- Artifact Provenance: logger-v1" "missing Codex/Opus provenance marker"
  # Accept either codex or opus generator script
  if ! grep -Eq '^- Generator Script: plans/(codex|opus)_review_logged\.sh$' "$codex_file"; then
    die "missing Codex/Opus generator script marker ($codex_file)"
  fi
  require_fixed_line "$codex_file" "- Command Exit Code: 0" "Codex/Opus review command did not exit 0"
  local_label="Codex/Opus"
  verify_hashed_block "$codex_file" "Transcript SHA256" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>" "$local_label transcript"
  validate_transcript_quality "$codex_file" "$local_label" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>"
  validate_review_timing "$codex_file" "$local_label"
  validate_diff_cross_reference "$codex_file" "$local_label" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>" "$diff_files"
done

# ---------- Cycle ordering and cross-cycle validation ----------
# Sort codex/opus reviews by timestamp to identify cycle 1 (older) and cycle 2 (newer)
cycle1_file=""
cycle2_file=""
cycle1_ts=""
cycle2_ts=""
if [[ "${#codex_matches[@]}" -ge 2 ]]; then
  # Sort by timestamp field — earlier = cycle 1, later = cycle 2
  ts_a="$(extract_review_timestamp "${codex_matches[0]}")"
  ts_b="$(extract_review_timestamp "${codex_matches[1]}")"
  if [[ -n "$ts_a" && -n "$ts_b" ]]; then
    if [[ "$ts_a" < "$ts_b" ]]; then
      cycle1_file="${codex_matches[0]}"
      cycle2_file="${codex_matches[1]}"
      cycle1_ts="$ts_a"
      cycle2_ts="$ts_b"
    else
      cycle1_file="${codex_matches[1]}"
      cycle2_file="${codex_matches[0]}"
      cycle1_ts="$ts_b"
      cycle2_ts="$ts_a"
    fi
  else
    # Fallback: array order (sort -r means [0]=newest, [1]=oldest)
    cycle1_file="${codex_matches[1]}"
    cycle2_file="${codex_matches[0]}"
  fi

  # Count high-severity findings in each cycle
  cycle1_high="$(count_high_severity "$cycle1_file" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>")"
  cycle2_high="$(count_high_severity "$cycle2_file" "<<<REVIEW_TRANSCRIPT_BEGIN>>>" "<<<REVIEW_TRANSCRIPT_END>>>")"

  echo "  cycle1_review: $cycle1_file (P0+P1 lines: $cycle1_high)" >&2
  echo "  cycle2_review: $cycle2_file (P0+P1 lines: $cycle2_high)" >&2

  # Monotonicity: cycle 2 must not have MORE high-severity findings than cycle 1
  if [[ "$cycle2_high" -gt "$cycle1_high" ]]; then
    die "cycle 2 has MORE high-severity findings ($cycle2_high) than cycle 1 ($cycle1_high): findings were not resolved between review cycles"
  fi

  # If cycle 1 had high-severity findings, require code changes between cycles
  if [[ "$cycle1_high" -gt 0 ]]; then
    # Check if there are commits between the two review timestamps
    code_changed=0
    if [[ -n "$cycle1_ts" && -n "$cycle2_ts" ]]; then
      # Look for commits between cycle 1 and cycle 2 timestamps
      commits_between="$(git log --oneline --after="$cycle1_ts" --before="$cycle2_ts" --format="%h" 2>/dev/null | head -5 || true)"
      if [[ -n "$commits_between" ]]; then
        code_changed=1
      fi
    fi
    # Fallback: check if the two review files reference different content
    # (different transcript hashes prove different review input)
    if [[ "$code_changed" -eq 0 ]]; then
      c1_hash="$(extract_sha256_field "$cycle1_file" "Transcript SHA256" "cycle1" 2>/dev/null || true)"
      c2_hash="$(extract_sha256_field "$cycle2_file" "Transcript SHA256" "cycle2" 2>/dev/null || true)"
      if [[ -n "$c1_hash" && -n "$c2_hash" && "$c1_hash" != "$c2_hash" ]]; then
        code_changed=1
      fi
    fi
    if [[ "$code_changed" -eq 0 ]]; then
      die "cycle 1 had $cycle1_high high-severity findings but no code changes detected between cycle 1 and cycle 2: agent must fix findings before re-review"
    fi
  fi
fi

# ---------- Code-review-expert review (must match HEAD) ----------
code_review_expert_dir="$story_dir/code_review_expert"
code_review_expert_match=""
if [[ -d "$code_review_expert_dir" ]]; then
  while IFS= read -r f; do
    [[ -f "$f" ]] || continue
    if grep -Fxq -- "- Story: $story" "$f" && grep -Fxq -- "- HEAD: $REVIEW_HEAD_SHA" "$f"; then
      code_review_expert_match="$f"
      break
    fi
  done < <(find "$code_review_expert_dir" -maxdepth 1 -type f -name '*_review.md' | LC_ALL=C sort -r)
fi
[[ -n "$code_review_expert_match" ]] || die "missing code-review-expert review artifact for HEAD=$REVIEW_HEAD_SHA in: $code_review_expert_dir"
grep -Fxq -- "- Review Status: COMPLETE" "$code_review_expert_match" || die "code-review-expert review must be marked '- Review Status: COMPLETE' ($code_review_expert_match)"
require_fixed_line "$code_review_expert_match" "- Artifact Provenance: logger-v1" "missing code-review-expert provenance marker"
require_fixed_line "$code_review_expert_match" "- Generator Script: plans/code_review_expert_logged.sh" "missing code-review-expert generator script marker"
if ! grep -Eq '^- Content Source: (template|from-file|from-stdin)$' "$code_review_expert_match"; then
  die "code-review-expert review missing valid '- Content Source: ...' marker ($code_review_expert_match)"
fi
for placeholder in \
  "- Blocking: <none | summary>" \
  "- Major: <none | summary>" \
  "- Medium: <none | summary>"; do
  if grep -Fxq -- "$placeholder" "$code_review_expert_match"; then
    die "code-review-expert review contains unresolved placeholder '$placeholder' ($code_review_expert_match)"
  fi
done
verify_hashed_block "$code_review_expert_match" "Findings SHA256" "<<<FINDINGS_BEGIN>>>" "<<<FINDINGS_END>>>" "code-review-expert findings"
validate_transcript_quality "$code_review_expert_match" "code-review-expert" "<<<FINDINGS_BEGIN>>>" "<<<FINDINGS_END>>>"
validate_review_timing "$code_review_expert_match" "code-review-expert"
validate_diff_cross_reference "$code_review_expert_match" "code-review-expert" "<<<FINDINGS_BEGIN>>>" "<<<FINDINGS_END>>>" "$diff_files"

# ---------- Resolution ----------
res_file="$story_dir/review_resolution.md"
[[ -f "$res_file" ]] || die "missing review resolution file: $res_file"

require_fixed_line "$res_file" "Story: $story" "resolution missing 'Story: $story'"
require_fixed_line "$res_file" "HEAD: $REVIEW_HEAD_SHA" "resolution not for current HEAD ($REVIEW_HEAD_SHA)"
require_fixed_line "$res_file" "Blocking addressed: YES" "resolution missing 'Blocking addressed: YES'"
require_fixed_line "$res_file" "Remaining findings: BLOCKING=0 MAJOR=0 MEDIUM=0" "resolution must assert no BLOCKING/MAJOR/MEDIUM remain"
kimi_ref_path="$(validate_review_reference "$res_file" "Kimi final review file" "Kimi final review file:" "$kimi_dir")"
# Accept codex/opus review references — try codex dir first, fall back to opus dir
codex_final_ref_path="$(validate_review_reference "$res_file" "Codex final review file" "Codex final review file:" "$codex_dir" 2>/dev/null || validate_review_reference "$res_file" "Codex final review file" "Codex final review file:" "$opus_dir")"
codex_second_ref_path="$(validate_review_reference "$res_file" "Codex second review file" "Codex second review file:" "$codex_dir" 2>/dev/null || validate_review_reference "$res_file" "Codex second review file" "Codex second review file:" "$opus_dir")"
code_review_expert_ref_path="$(validate_review_reference "$res_file" "Code-review-expert final review file" "Code-review-expert final review file:" "$code_review_expert_dir")"

if [[ "$(canonical_path "$codex_final_ref_path")" == "$(canonical_path "$codex_second_ref_path")" ]]; then
  die "Codex final review file and Codex second review file must be different artifacts"
fi

# ---------- Finding Disposition validation ----------
# If cycle 1 had high-severity findings, resolution must include disposition for each
if [[ -n "$cycle1_file" && "${cycle1_high:-0}" -gt 0 ]]; then
  # Require "## Finding Disposition" section
  grep -Fxq "## Finding Disposition" "$res_file" || die "resolution missing '## Finding Disposition' section — required when cycle 1 had findings ($res_file)"

  # Require "Cycle 1 high-severity count: N" and verify it matches actual count
  declared_c1_count="$(grep -oE '^Cycle 1 high-severity count: [0-9]+' "$res_file" | head -1 | grep -oE '[0-9]+$' || true)"
  [[ -n "$declared_c1_count" ]] || die "resolution missing 'Cycle 1 high-severity count: N' ($res_file)"
  if [[ "$declared_c1_count" -lt "$cycle1_high" ]]; then
    die "resolution declares cycle 1 count=$declared_c1_count but transcript has $cycle1_high high-severity lines: undercounting findings ($res_file)"
  fi

  # Count finding disposition rows (lines matching "| F-N | PN | ...")
  disposition_rows="$(grep -cE '^\|[[:space:]]*F-[0-9]+[[:space:]]*\|[[:space:]]*P[0-3][[:space:]]*\|' "$res_file" || true)"
  if [[ "$disposition_rows" -lt 1 ]]; then
    die "resolution has Finding Disposition section but no finding rows (expected at least 1 for $cycle1_high high-severity findings) ($res_file)"
  fi

  # Verify no P0 findings with DEFERRED or WONTFIX disposition
  p0_deferred="$(grep -cE '^\| F-[0-9]+ \| P0 \|.*\| (DEFERRED|WONTFIX) \|' "$res_file" || true)"
  if [[ "$p0_deferred" -gt 0 ]]; then
    die "P0 findings cannot be DEFERRED or WONTFIX — must be FIXED ($res_file)"
  fi

  # Verify DEFERRED findings reference a debt item
  while IFS= read -r deferred_line; do
    [[ -n "$deferred_line" ]] || continue
    if ! echo "$deferred_line" | grep -qiE 'debt|D-[0-9]+|slice'; then
      die "DEFERRED finding must reference a debt item with target slice: $deferred_line ($res_file)"
    fi
  done < <(grep -E '^\| F-[0-9]+ \| P[0-9] \|.*\| DEFERRED \|' "$res_file" || true)

  # Require "Cycle 2 new P0/P1 findings: 0"
  grep -Fxq "Cycle 2 new P0/P1 findings: 0" "$res_file" || die "resolution must declare 'Cycle 2 new P0/P1 findings: 0' — cycle 2 must not introduce new high-severity issues ($res_file)"

elif [[ -n "$cycle1_file" && "${cycle1_high:-0}" -eq 0 ]]; then
  # Cycle 1 had no high-severity findings — disposition section is optional
  # but if present, should say "No high-severity findings"
  if grep -Fxq "## Finding Disposition" "$res_file"; then
    if ! grep -qF "No high-severity findings" "$res_file"; then
      warn "Finding Disposition section present but cycle 1 had 0 high-severity findings — expected 'No high-severity findings in cycle 1.'"
    fi
  fi
fi

# ---------- Supervisor checks ----------
# Verify supervisor artifacts exist with PASS verdict for each checkpoint
supervisor_dir="$story_dir/supervisor"
REQUIRE_SUPERVISOR="${REQUIRE_SUPERVISOR:-1}"
if [[ "$REQUIRE_SUPERVISOR" == "1" ]]; then
  for checkpoint in post-cycle1 post-fix post-cycle2; do
    sup_match=""
    if [[ -d "$supervisor_dir" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" ]] || continue
        if grep -Fxq -- "- Story: $story" "$f" && \
           grep -Fxq -- "- HEAD: $REVIEW_HEAD_SHA" "$f" && \
           grep -Fxq -- "- Checkpoint: $checkpoint" "$f"; then
          sup_match="$f"
          break
        fi
      done < <(find "$supervisor_dir" -maxdepth 1 -type f -name "${checkpoint}_*.md" | LC_ALL=C sort -r)
    fi
    if [[ -z "$sup_match" ]]; then
      die "missing supervisor $checkpoint artifact for HEAD=$REVIEW_HEAD_SHA in: $supervisor_dir"
    fi
    # Verify verdict is PASS
    sup_verdict="$(grep -oE '^- Verdict: (PASS|FAIL)' "$sup_match" | head -1 | grep -oE '(PASS|FAIL)' || true)"
    if [[ "$sup_verdict" != "PASS" ]]; then
      sup_reason="$(grep -oE '^- Reason: .*' "$sup_match" | head -1 | sed 's/^- Reason: //' || true)"
      die "supervisor $checkpoint verdict is $sup_verdict: ${sup_reason:-no reason given} ($sup_match)"
    fi
    # Verify provenance
    grep -Fxq -- "- Artifact Provenance: supervisor-v1" "$sup_match" || die "supervisor $checkpoint missing provenance marker ($sup_match)"
    grep -Fxq -- "- Generator Script: plans/supervisor_check.sh" "$sup_match" || die "supervisor $checkpoint missing generator script marker ($sup_match)"
  done
  echo "  supervisor: all 3 checkpoints PASS" >&2
else
  echo "  supervisor: SKIPPED (REQUIRE_SUPERVISOR=0)" >&2
fi

echo "OK: review gate passed for $story @ $REVIEW_HEAD_SHA"
if [[ "$review_head_fallback" -eq 1 ]]; then
  echo "  requested_head: $REQUESTED_HEAD_SHA"
  echo "  review_head_fallback: artifact-only commit, using parent $REVIEW_HEAD_SHA"
fi
echo "  self_review: $self_file"
echo "  kimi_review: $kimi_match"
echo "  codex_opus_reviews: ${#codex_matches[@]}"
echo "  code_review_expert_review: $code_review_expert_match"
echo "  kimi_resolution_ref: $kimi_ref_path"
echo "  codex_final_ref: $codex_final_ref_path"
echo "  codex_second_ref: $codex_second_ref_path"
echo "  code_review_expert_ref: $code_review_expert_ref_path"
echo "  resolution: $res_file"
