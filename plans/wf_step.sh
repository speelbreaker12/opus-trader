#!/usr/bin/env bash
set -euo pipefail

# Workflow step executor with hash-chained receipt enforcement.
#
# Each step validates prerequisites (previous receipt exists + chain integrity),
# runs step-specific input validation, and writes a hash-chained JSON receipt.
#
# Usage: plans/wf_step.sh <STORY_ID> <step> [options]
#
# Steps (in order — each requires the previous receipt):
#   preflight      — validate preflight/quick-verify passed
#   implement      — validate code changed since preflight
#   self_review    — validate self-review artifacts exist
#   cycle1         — validate cycle 1 review artifact exists
#   fix            — validate fixes applied (code changed since cycle1)
#   cycle2         — validate cycle 2 review artifact exists
#   resolution     — validate review resolution exists
#   verify_full    — validate verify.sh full passed with matching HEAD
#   pass           — final gate (validates full chain, delegates to prd_set_pass.sh)
#
# Options:
#   --dry-run      Validate prerequisites but don't write receipt
#   --status       Show current receipt chain status
#   --reset        Delete all receipts for this story (requires confirmation)
#   --force        Skip prerequisite check (for recovery only; taints receipt)
#   --verify-sigs  Verify HMAC signatures on all receipts (requires WF_HMAC_KEY)
#
# Receipt chain: .wf/receipts/<STORY_ID>/<NN>_<step>.json
# Each receipt includes prev_receipt_hash for tamper detection.
#
# Exit codes:
#   0 — step completed, receipt written
#   1 — prerequisite missing (run the required step first)
#   2 — usage/setup error
#   3 — step validation failed (inputs not ready)
#   4 — receipt chain integrity failure (tampering detected)
#   5 — HEAD mismatch

STEPS=(preflight implement self_review cycle1 fix cycle2 resolution verify_full pass)

usage() {
  cat <<'EOF'
Usage: plans/wf_step.sh <STORY_ID> <step> [--dry-run|--status|--reset|--force]

Steps (in order):
  preflight      Validate preflight/quick-verify passed
  implement      Validate code changed since preflight
  self_review    Validate self-review artifacts exist
  cycle1         Validate cycle 1 review artifact exists
  fix            Validate fixes applied since cycle1
  cycle2         Validate cycle 2 review artifact exists
  resolution     Validate review resolution exists
  verify_full    Validate verify.sh full passed
  pass           Final gate (full chain required)

Options:
  --dry-run      Validate only, don't write receipt
  --status       Show receipt chain status
  --reset        Delete all receipts for story
  --force        Skip prerequisite check (taints receipt)
EOF
}

die()  { echo "WF_STEP ERROR: $*" >&2; exit 2; }
fail() { echo "WF_STEP BLOCKED: $*" >&2; exit 1; }
warn() { echo "WF_STEP WARNING: $*" >&2; }

sha256_of() {
  if [[ ! -f "$1" ]]; then echo "NO_FILE"; return; fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sha256_str() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

hmac_sha256() {
  # Compute HMAC-SHA256 of file $1 using key $2
  local file="$1" key="$2"
  if [[ ! -f "$file" ]]; then echo "NO_FILE"; return; fi
  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 -hmac "$key" "$file" 2>/dev/null | awk '{print $NF}'
  else
    # Fallback: use Python if openssl unavailable
    python3 -c "
import hmac, hashlib, sys
key = sys.argv[1].encode('utf-8')
with open(sys.argv[2], 'rb') as f:
    print(hmac.new(key, f.read(), hashlib.sha256).hexdigest())
" "$key" "$file"
  fi
}

verify_hmac() {
  # Verify HMAC signature on receipt file $1 using key $2
  # Returns 0 if valid, 1 if invalid
  local file="$1" key="$2"
  if [[ ! -f "$file" ]]; then return 1; fi
  local stored_sig
  stored_sig="$(jq -r '.signature // ""' "$file" 2>/dev/null || echo '')"
  if [[ -z "$stored_sig" ]]; then return 1; fi
  # Extract unsigned content (remove signature and receipt_hash), compute HMAC
  local unsigned_tmp
  unsigned_tmp="$(mktemp)"
  jq -S 'del(.signature, .receipt_hash)' "$file" > "$unsigned_tmp" 2>/dev/null
  local computed_sig
  computed_sig="$(hmac_sha256 "$unsigned_tmp" "$key")"
  rm -f "$unsigned_tmp"
  [[ "$computed_sig" == "$stored_sig" ]]
}

# ── Parse args ──────────────────────────────────────────────────────

STORY="${1:-}"
DRY_RUN=0
STATUS_MODE=0
RESET_MODE=0
FORCE=0
VERIFY_SIGS=0
YES=0
STEP=""

# Parse remaining args — position 2 can be a step name or an option
shift $(( $# >= 1 ? 1 : 0 ))
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)      DRY_RUN=1 ;;
    --status)       STATUS_MODE=1 ;;
    --reset)        RESET_MODE=1 ;;
    --force)        FORCE=1 ;;
    --verify-sigs)  VERIFY_SIGS=1 ;;
    --yes)          YES=1 ;;
    -h|--help)      usage; exit 0 ;;
    -*)             die "unknown option: $1" ;;
    *)
      if [[ -z "$STEP" ]]; then
        STEP="$1"
      else
        die "unexpected argument: $1"
      fi
      ;;
  esac
  shift
done

[[ -n "$STORY" ]] || { usage >&2; exit 2; }

# Close stdin to prevent any commands from blocking on input
exec < /dev/null

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
cd "$ROOT"

RECEIPT_DIR="${WF_RECEIPT_DIR:-$ROOT/.wf/receipts/$STORY}"
mkdir -p "$RECEIPT_DIR"

art_root="${STORY_ARTIFACTS_ROOT:-artifacts/story}"
if [[ "$art_root" != /* ]]; then art_root="$ROOT/$art_root"; fi
story_art="$art_root/$STORY"

# ── Step index helpers ──────────────────────────────────────────────

step_index() {
  local s="$1"
  for i in "${!STEPS[@]}"; do
    [[ "${STEPS[$i]}" == "$s" ]] && { echo "$i"; return 0; }
  done
  return 1
}

step_is_valid() {
  step_index "$1" >/dev/null 2>&1
}

receipt_file() {
  local s="$1"
  local idx
  idx="$(step_index "$s")"
  printf '%s/%02d_%s.json' "$RECEIPT_DIR" "$idx" "$s"
}

prev_step_name() {
  local idx
  idx="$(step_index "$1")"
  if [[ "$idx" -eq 0 ]]; then
    echo ""
  else
    echo "${STEPS[$((idx - 1))]}"
  fi
}

# ── Status mode ─────────────────────────────────────────────────────

if [[ "$STATUS_MODE" -eq 1 ]]; then
  echo "Receipt chain for $STORY:"
  echo "─────────────────────────────"
  head_sha="$(git rev-parse HEAD 2>/dev/null || echo '?')"
  for s in "${STEPS[@]}"; do
    f="$(receipt_file "$s")"
    if [[ -f "$f" ]]; then
      r_head="$(jq -r '.head_sha // "?"' "$f" 2>/dev/null || echo '?')"
      r_ts="$(jq -r '.timestamp_utc // "?"' "$f" 2>/dev/null || echo '?')"
      r_tainted="$(jq -r '.tainted // false' "$f" 2>/dev/null || echo 'false')"
      head_match=""
      [[ "$r_head" != "$head_sha" ]] && head_match=" (HEAD MISMATCH!)"
      taint_mark=""
      [[ "$r_tainted" == "true" ]] && taint_mark=" [TAINTED]"
      printf '  [DONE] %-15s  %s  %s%s%s\n' "$s" "$r_ts" "$r_head" "$head_match" "$taint_mark"
    else
      printf '  [    ] %-15s\n' "$s"
    fi
  done
  echo "─────────────────────────────"
  echo "Current HEAD: $head_sha"
  exit 0
fi

# ── Reset mode ──────────────────────────────────────────────────────

if [[ "$RESET_MODE" -eq 1 ]]; then
  count="$(find "$RECEIPT_DIR" -maxdepth 1 -name '*.json' 2>/dev/null | wc -l | tr -d '[:space:]')"
  if [[ "$count" -eq 0 ]]; then
    echo "No receipts to reset for $STORY"
    exit 0
  fi
  # Require --yes flag for confirmation
  if [[ "$YES" -ne 1 && "$FORCE" -ne 1 ]]; then
    echo "WF_STEP: reset will delete $count receipt(s) for $STORY" >&2
    echo "  Add --yes to confirm: plans/wf_step.sh $STORY --reset --yes" >&2
    exit 2
  fi
  echo "Deleting $count receipt(s) for $STORY in $RECEIPT_DIR"
  rm -f "$RECEIPT_DIR"/*.json
  echo "Reset complete."
  exit 0
fi

# ── Verify signatures mode ──────────────────────────────────────────

if [[ "$VERIFY_SIGS" -eq 1 ]]; then
  WF_HMAC_KEY="${WF_HMAC_KEY:-}"
  if [[ -z "$WF_HMAC_KEY" ]]; then
    die "WF_HMAC_KEY not set — cannot verify signatures"
  fi
  echo "Verifying HMAC signatures for $STORY:"
  echo "─────────────────────────────"
  sig_pass=0
  sig_fail=0
  sig_missing=0
  for s in "${STEPS[@]}"; do
    [[ "$s" == "pass" ]] && continue
    f="$(receipt_file "$s")"
    if [[ ! -f "$f" ]]; then
      printf '  [SKIP] %-15s  no receipt\n' "$s"
      continue
    fi
    stored_sig="$(jq -r '.signature // ""' "$f" 2>/dev/null || echo '')"
    if [[ -z "$stored_sig" ]]; then
      printf '  [NOSIG] %-15s  unsigned receipt\n' "$s"
      sig_missing=$((sig_missing + 1))
      continue
    fi
    if verify_hmac "$f" "$WF_HMAC_KEY"; then
      printf '  [OK]   %-15s  signature valid\n' "$s"
      sig_pass=$((sig_pass + 1))
    else
      printf '  [FAIL] %-15s  SIGNATURE INVALID\n' "$s"
      sig_fail=$((sig_fail + 1))
    fi
  done
  echo "─────────────────────────────"
  echo "Verified: $sig_pass  Missing: $sig_missing  Failed: $sig_fail"
  if [[ "$sig_fail" -gt 0 ]]; then
    echo "SIGNATURE VERIFICATION FAILED" >&2
    exit 4
  fi
  if [[ "$sig_missing" -gt 0 ]]; then
    echo "WARNING: $sig_missing receipt(s) have no signature" >&2
  fi
  exit 0
fi

# ── Validate step name (not required for --status/--reset) ──────────

if [[ "$STATUS_MODE" -eq 0 && "$RESET_MODE" -eq 0 ]]; then
  [[ -n "$STEP" ]] || { usage >&2; exit 2; }
  step_is_valid "$STEP" || die "unknown step: $STEP (valid: ${STEPS[*]})"
fi

HEAD_SHA="$(git rev-parse HEAD)"
STEP_IDX="$(step_index "$STEP")"

# ── Validate receipt chain integrity ────────────────────────────────

validate_chain() {
  # Walk all existing receipts up to (but not including) the target step.
  # Verify each receipt's prev_receipt_hash matches the actual hash of the previous receipt.
  local expected_prev="GENESIS"
  for i in $(seq 0 $((STEP_IDX - 1))); do
    local s="${STEPS[$i]}"
    local f
    f="$(receipt_file "$s")"
    if [[ ! -f "$f" ]]; then
      if [[ "$FORCE" -eq 1 ]]; then
        warn "missing receipt for '$s' — skipped (--force)"
        expected_prev="FORCE_SKIP"
        continue
      fi
      fail "missing receipt for step '$s' — run: plans/wf_step.sh $STORY $s"
    fi
    # Verify prev_receipt_hash
    local actual_prev
    actual_prev="$(jq -r '.prev_receipt_hash' "$f" 2>/dev/null || echo '?')"
    if [[ "$expected_prev" != "FORCE_SKIP" && "$actual_prev" != "$expected_prev" ]]; then
      echo "WF_STEP CHAIN BREAK at step '$s':" >&2
      echo "  expected prev_receipt_hash: $expected_prev" >&2
      echo "  actual prev_receipt_hash:   $actual_prev" >&2
      echo "  Receipt chain has been tampered with or receipts were regenerated out of order." >&2
      echo "  Run: plans/wf_step.sh $STORY --reset  then re-run all steps." >&2
      exit 4
    fi
    # The hash of this receipt becomes the expected prev for next step
    expected_prev="$(sha256_of "$f")"
  done
  echo "$expected_prev"
}

# ── Validate prerequisites ──────────────────────────────────────────

PREV_HASH="GENESIS"
if [[ "$STEP_IDX" -gt 0 ]]; then
  PREV_HASH="$(validate_chain)"
fi

# ── Step-specific input validation ──────────────────────────────────

INPUTS_HASH=""

compute_inputs_hash() {
  # Hash step-specific evidence files. Concatenate their hashes and hash again.
  local combined=""
  for f in "$@"; do
    if [[ -f "$f" ]]; then
      combined+="$(sha256_of "$f")"
    else
      combined+="MISSING:$f"
    fi
  done
  sha256_str "$combined"
}

get_base_head() {
  # Extract BASE_HEAD from the preflight receipt (the starting point for all diffs).
  # This ensures all diffs cover the FULL story change, not just the last commit.
  local pf
  pf="$(receipt_file preflight)"
  if [[ ! -f "$pf" ]]; then
    die "no preflight receipt — cannot determine BASE_HEAD"
  fi
  jq -r '.head_sha' "$pf" 2>/dev/null || die "cannot read head_sha from preflight receipt"
}

find_review_artifacts() {
  # Find review artifacts in codex/ or opus/ directories
  local dir="$1" min_count="$2"
  local count=0
  local files=()
  for d in "$story_art/codex" "$story_art/opus"; do
    if [[ -d "$d" ]]; then
      while IFS= read -r f; do
        [[ -f "$f" ]] && { files+=("$f"); count=$((count + 1)); }
      done < <(find "$d" -maxdepth 1 -type f -name '*_review.md' 2>/dev/null | LC_ALL=C sort)
    fi
  done
  if [[ "$count" -lt "$min_count" ]]; then
    return 1
  fi
  printf '%s\n' "${files[@]}"
}

case "$STEP" in
  preflight)
    # First step — record HEAD as BASE_HEAD (the starting point for all diffs).
    # All subsequent steps use this as the diff baseline.
    INPUTS_HASH="$(sha256_str "preflight:$HEAD_SHA")"
    ;;

  implement)
    # Validate code has changed since preflight BASE_HEAD.
    # Uses BASE_HEAD..HEAD (full story diff), NOT HEAD~1..HEAD (single commit).
    base_head="$(get_base_head)"
    diff_output="$(git diff --name-only "$base_head"..HEAD 2>/dev/null || true)"
    if [[ -z "$diff_output" ]]; then
      echo "WF_STEP: no code changes since preflight base ($base_head)" >&2
      echo "  Implement the story before running this step." >&2
      exit 3
    fi
    diff_hash="$(sha256_str "$diff_output")"
    INPUTS_HASH="$(sha256_str "implement:$HEAD_SHA:base:$base_head:$diff_hash")"
    ;;

  self_review)
    # Validate self-review artifacts exist
    sr_dir="$story_art/self_review"
    if [[ ! -d "$sr_dir" ]]; then
      echo "WF_STEP: no self_review directory at $sr_dir" >&2
      exit 3
    fi
    sr_count="$(find "$sr_dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d '[:space:]')"
    if [[ "$sr_count" -lt 1 ]]; then
      echo "WF_STEP: no self-review artifacts found in $sr_dir" >&2
      exit 3
    fi
    # Hash the self-review files
    sr_files=()
    while IFS= read -r f; do sr_files+=("$f"); done < <(find "$sr_dir" -maxdepth 1 -type f -name '*.md' | LC_ALL=C sort)
    INPUTS_HASH="$(compute_inputs_hash "${sr_files[@]}")"
    ;;

  cycle1)
    # Validate at least 1 review artifact exists (codex or opus)
    review_files="$(find_review_artifacts "$story_art" 1)" || {
      echo "WF_STEP: no cycle 1 review artifact found in $story_art/codex/ or $story_art/opus/" >&2
      exit 3
    }
    # Hash ALL review artifacts (sorted), not just the first
    cycle1_hash_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && cycle1_hash_files+=("$f"); done <<< "$review_files"
    INPUTS_HASH="$(compute_inputs_hash "${cycle1_hash_files[@]}")"
    ;;

  fix)
    # Validate real code changed since cycle1 receipt (not just artifact tweaks).
    # Must change at least one non-artifact file — UNLESS cycle1 had 0 findings.
    cycle1_file="$(receipt_file cycle1)"
    cycle1_head="$(jq -r '.head_sha' "$cycle1_file" 2>/dev/null || echo '')"
    if [[ -z "$cycle1_head" ]]; then
      die "cannot read head_sha from cycle1 receipt"
    fi

    # Check if cycle1 was a "perfect" review (0 findings → no fixes needed).
    # Look for a cycle1 review artifact with P0+P1 count of 0.
    cycle1_perfect=0
    for d in "$story_art/codex" "$story_art/opus"; do
      if [[ -d "$d" ]]; then
        while IFS= read -r rf; do
          [[ -f "$rf" ]] || continue
          # Check if this review mentions 0 findings / 0 issues
          if grep -qiE '(0 findings|no findings|no issues|0 P0.*0 P1|P0: 0.*P1: 0)' "$rf" 2>/dev/null; then
            cycle1_perfect=1
            break
          fi
        done < <(find "$d" -maxdepth 1 -type f -name '*_review.md' 2>/dev/null | LC_ALL=C sort | head -1)
      fi
      [[ "$cycle1_perfect" -eq 1 ]] && break
    done

    # Get files changed since cycle1, excluding artifacts and workflow metadata
    changed_files="$(git diff --name-only "$cycle1_head"..HEAD 2>/dev/null || true)"
    if [[ -z "$changed_files" ]]; then
      # Check staged/unstaged if HEAD hasn't moved
      changed_files="$(git diff --name-only 2>/dev/null || true)"
      changed_files+="$(git diff --cached --name-only 2>/dev/null || true)"
    fi
    # Filter out artifact-only changes
    non_artifact_changes="$(echo "$changed_files" | grep -vE '^(artifacts/|\.wf/|plans/prd\.json$|plans/progress)' || true)"

    if [[ -z "$non_artifact_changes" ]]; then
      if [[ "$cycle1_perfect" -eq 1 ]]; then
        echo "WF_STEP: cycle1 had 0 findings — fix step passes with no code changes" >&2
        INPUTS_HASH="$(sha256_str "fix:$HEAD_SHA:perfect_cycle1:$cycle1_head")"
      else
        echo "WF_STEP: no non-artifact code changes since cycle1 receipt (HEAD=$cycle1_head)" >&2
        echo "  Only artifact/metadata files changed. Fix the actual code." >&2
        echo "  Changed files: $(echo "$changed_files" | tr '\n' ' ')" >&2
        exit 3
      fi
    else
      fix_diff_hash="$(sha256_str "$non_artifact_changes")"
      INPUTS_HASH="$(sha256_str "fix:$HEAD_SHA:since:$cycle1_head:$fix_diff_hash")"
    fi
    ;;

  cycle2)
    # Validate at least 2 review artifacts exist (cycle 1 + cycle 2)
    review_files="$(find_review_artifacts "$story_art" 2)" || {
      echo "WF_STEP: need at least 2 review artifacts (cycle 1 + cycle 2) in $story_art/codex/ or $story_art/opus/" >&2
      exit 3
    }
    # Hash ALL review artifacts (sorted), not just the last
    cycle2_hash_files=()
    while IFS= read -r f; do [[ -n "$f" ]] && cycle2_hash_files+=("$f"); done <<< "$review_files"
    INPUTS_HASH="$(compute_inputs_hash "${cycle2_hash_files[@]}")"
    ;;

  resolution)
    # Validate review_resolution.md exists
    res_file="$story_art/review_resolution.md"
    if [[ ! -f "$res_file" ]]; then
      echo "WF_STEP: no review_resolution.md at $res_file" >&2
      exit 3
    fi
    # Validate it has required fields
    if ! grep -q 'Blocking addressed: YES' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Blocking addressed: YES'" >&2
      exit 3
    fi
    if ! grep -q 'Remaining findings: BLOCKING=0' "$res_file" 2>/dev/null; then
      echo "WF_STEP: resolution missing 'Remaining findings: BLOCKING=0'" >&2
      exit 3
    fi
    INPUTS_HASH="$(compute_inputs_hash "$res_file")"
    ;;

  verify_full)
    # Validate verify.meta.json exists with mode=full and matching HEAD
    latest_verify="$(ls -dt "$ROOT"/artifacts/verify/*/ 2>/dev/null | head -1 || true)"
    if [[ -z "$latest_verify" ]]; then
      echo "WF_STEP: no verify artifacts found in artifacts/verify/" >&2
      exit 3
    fi
    meta_file="${latest_verify%/}/verify.meta.json"
    if [[ ! -f "$meta_file" ]]; then
      echo "WF_STEP: no verify.meta.json in $latest_verify" >&2
      exit 3
    fi
    verify_mode="$(jq -r '.mode // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_mode" != "full" ]]; then
      echo "WF_STEP: verify was mode=$verify_mode, need mode=full" >&2
      exit 3
    fi
    verify_head="$(jq -r '.head_sha // empty' "$meta_file" 2>/dev/null || true)"
    if [[ "$verify_head" != "$HEAD_SHA" ]]; then
      echo "WF_STEP: verify HEAD mismatch (verify=$verify_head current=$HEAD_SHA)" >&2
      exit 5
    fi
    # Check no failed gate
    if [[ -f "${latest_verify%/}/FAILED_GATE" ]]; then
      echo "WF_STEP: FAILED_GATE present in $latest_verify" >&2
      exit 3
    fi
    INPUTS_HASH="$(compute_inputs_hash "$meta_file")"
    ;;

  pass)
    # Final gate — validate FULL chain exists and is consistent.
    # Don't write a receipt — this step delegates to prd_set_pass.sh.
    echo "WF_STEP: full receipt chain validated for $STORY"
    echo "WF_STEP: chain integrity: OK (all ${#STEPS[@]} steps verified)"
    # Check for tainted receipts
    tainted=0
    for s in "${STEPS[@]}"; do
      [[ "$s" == "pass" ]] && continue
      f="$(receipt_file "$s")"
      if [[ -f "$f" ]]; then
        t="$(jq -r '.tainted // false' "$f" 2>/dev/null || echo 'false')"
        if [[ "$t" == "true" ]]; then
          echo "WF_STEP WARNING: receipt for '$s' is TAINTED (--force was used)" >&2
          tainted=1
        fi
      fi
    done
    if [[ "$tainted" -eq 1 ]]; then
      echo "WF_STEP: tainted receipts detected — prd_set_pass.sh WILL reject (exit 4)" >&2
      exit 4
    fi
    echo "WF_STEP: ready for prd_set_pass.sh"
    exit 0
    ;;
esac

# ── Dry run ─────────────────────────────────────────────────────────

if [[ "$DRY_RUN" -eq 1 ]]; then
  echo "WF_STEP DRY RUN: step '$STEP' prerequisites OK, would write receipt"
  echo "  HEAD: $HEAD_SHA"
  echo "  inputs_hash: $INPUTS_HASH"
  echo "  prev_receipt_hash: $PREV_HASH"
  exit 0
fi

# ── Write receipt ───────────────────────────────────────────────────

receipt_path="$(receipt_file "$STEP")"
ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

tainted="false"
if [[ "$FORCE" -eq 1 ]]; then
  tainted="true"
  warn "receipt will be marked TAINTED (--force used)"
fi

# Build receipt JSON (without receipt_hash — that's computed over the content)
tmp_receipt="$(mktemp)"
trap 'rm -f "$tmp_receipt"' EXIT

jq -n \
  --arg story_id "$STORY" \
  --arg step_name "$STEP" \
  --argjson step_index "$STEP_IDX" \
  --arg head_sha "$HEAD_SHA" \
  --arg timestamp_utc "$ts" \
  --arg inputs_hash "$INPUTS_HASH" \
  --arg prev_receipt_hash "$PREV_HASH" \
  --argjson tainted "$tainted" \
  '{
    story_id: $story_id,
    step_name: $step_name,
    step_index: $step_index,
    head_sha: $head_sha,
    timestamp_utc: $timestamp_utc,
    inputs_hash: $inputs_hash,
    prev_receipt_hash: $prev_receipt_hash,
    tainted: $tainted
  }' > "$tmp_receipt"

# Compute receipt_hash over the content
receipt_hash="$(sha256_of "$tmp_receipt")"

# Add receipt_hash (and optionally HMAC signature)
WF_HMAC_KEY="${WF_HMAC_KEY:-}"
if [[ -n "$WF_HMAC_KEY" ]]; then
  # Compute HMAC over the unsigned canonical content (sorted keys, no signature/receipt_hash)
  unsigned_tmp="$(mktemp)"
  jq -S '.' "$tmp_receipt" > "$unsigned_tmp"
  sig="$(hmac_sha256 "$unsigned_tmp" "$WF_HMAC_KEY")"
  rm -f "$unsigned_tmp"
  jq --arg h "$receipt_hash" --arg s "$sig" '. + {receipt_hash: $h, signature: $s}' "$tmp_receipt" > "$receipt_path"
else
  jq --arg h "$receipt_hash" '. + {receipt_hash: $h}' "$tmp_receipt" > "$receipt_path"
fi

echo "WF_STEP: [$STEP] receipt written → $receipt_path"
echo "  HEAD: $HEAD_SHA"
echo "  receipt_hash: $receipt_hash"
echo "  prev_receipt_hash: $PREV_HASH"
if [[ -n "$WF_HMAC_KEY" ]]; then
  echo "  signature: present (HMAC-SHA256)"
fi
if [[ "$tainted" == "true" ]]; then
  echo "  TAINTED: yes (--force was used)"
fi
