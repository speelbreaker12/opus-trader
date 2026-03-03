#!/usr/bin/env bash
# rgr_gate.sh — Validate RGR (Red-Green-Refactor) receipt chain
#
# Usage:
#   plans/rgr_gate.sh <STORY_ID>           # validate all iterations for story
#   plans/rgr_gate.sh <STORY_ID> --iter N  # validate single iteration
#   plans/rgr_gate.sh --all                # validate all stories
#   plans/rgr_gate.sh --schema             # print JSON schema
#
# Exit codes:
#   0 = all receipts valid
#   1 = validation failure (details printed)
#   2 = usage error

set -euo pipefail

EVIDENCE_ROOT="evidence/rgr"

# ── Schema ──────────────────────────────────────────────────────────────────

REQUIRED_FIELDS=(
  "story"
  "iter"
  "behavior"
  "test.path"
  "test.name"
  "cmd"
  "red.output"
  "green.output"
  "files_changed"
  "diff_summary"
  "commit"
  "timestamp_utc"
)

print_schema() {
  cat <<'SCHEMA'
{
  "story": "string (required, e.g. S2-003)",
  "iter": "integer (required, 1-indexed, sequential)",
  "behavior": "string (required, 1 sentence max)",
  "test": {
    "path": "string (required, file must exist)",
    "name": "string (required, test function name)"
  },
  "cmd": "string (required, exact shell command)",
  "red": {
    "output": "string (required, must contain assertion failure)"
  },
  "green": {
    "output": "string (required, must contain pass confirmation)"
  },
  "refactor": "null | { summary: string, output: string, files_changed: [string] }",
  "files_changed": "[string] (required, non-empty, exact paths)",
  "diff_summary": "string (required, what changed and why)",
  "commit": "string (required, valid git SHA)",
  "timestamp_utc": "string (required, ISO 8601)"
}
SCHEMA
}

# ── Helpers ─────────────────────────────────────────────────────────────────

errors=0
warnings=0

err() {
  echo "  FAIL: $1" >&2
  ((errors++)) || true
}

warn() {
  echo "  WARN: $1" >&2
  ((warnings++)) || true
}

ok() {
  echo "  OK: $1"
}

# ── Validate single receipt ─────────────────────────────────────────────────

validate_receipt() {
  local file="$1"
  local story_id="$2"
  local expected_iter="${3:-}"

  echo "Checking: $file"

  # File must be valid JSON
  if ! jq empty "$file" 2>/dev/null; then
    err "Invalid JSON: $file"
    return 1
  fi

  # Check required top-level fields
  for field in story iter behavior cmd diff_summary commit timestamp_utc; do
    local val
    val=$(jq -r ".$field // empty" "$file")
    if [[ -z "$val" ]]; then
      err "Missing or empty field: $field"
    fi
  done

  # Check nested required fields
  local test_path test_name red_output green_output
  test_path=$(jq -r '.test.path // empty' "$file")
  test_name=$(jq -r '.test.name // empty' "$file")
  red_output=$(jq -r '.red.output // empty' "$file")
  green_output=$(jq -r '.green.output // empty' "$file")

  [[ -z "$test_path" ]] && err "Missing: test.path"
  [[ -z "$test_name" ]] && err "Missing: test.name"
  [[ -z "$red_output" ]] && err "Missing: red.output"
  [[ -z "$green_output" ]] && err "Missing: green.output"

  # files_changed must be non-empty array
  local fc_count
  fc_count=$(jq '.files_changed | length' "$file" 2>/dev/null || echo 0)
  if [[ "$fc_count" -eq 0 ]]; then
    err "files_changed is empty or missing"
  fi

  # Story ID must match
  local file_story
  file_story=$(jq -r '.story // empty' "$file")
  if [[ -n "$file_story" && "$file_story" != "$story_id" ]]; then
    err "Story mismatch: receipt says '$file_story', expected '$story_id'"
  fi

  # Iteration number check
  if [[ -n "$expected_iter" ]]; then
    local file_iter
    file_iter=$(jq -r '.iter // empty' "$file")
    if [[ "$file_iter" != "$expected_iter" ]]; then
      err "Iteration mismatch: receipt says '$file_iter', expected '$expected_iter'"
    fi
  fi

  # Test file must exist in codebase
  if [[ -n "$test_path" && ! -f "$test_path" ]]; then
    err "Test file not found: $test_path"
  fi

  # Commit SHA must exist in git
  local commit_sha
  commit_sha=$(jq -r '.commit // empty' "$file")
  if [[ -n "$commit_sha" ]]; then
    if ! git cat-file -t "$commit_sha" &>/dev/null; then
      err "Commit SHA not found in git: $commit_sha"
    else
      ok "Commit $commit_sha exists"

      # Verify files_changed appear in the commit diff
      local changed_files
      changed_files=$(git diff-tree --no-commit-id --name-only -r "$commit_sha" 2>/dev/null || true)
      if [[ -n "$changed_files" ]]; then
        local receipt_files
        receipt_files=$(jq -r '.files_changed[]' "$file" 2>/dev/null)
        local missing_in_commit=0
        while IFS= read -r rf; do
          if ! echo "$changed_files" | grep -qF "$rf"; then
            warn "files_changed entry '$rf' not in commit $commit_sha diff"
            ((missing_in_commit++)) || true
          fi
        done <<< "$receipt_files"
        if [[ "$missing_in_commit" -eq 0 ]]; then
          ok "All files_changed match commit diff"
        fi
      fi
    fi
  fi

  # RED output should look like a real failure (heuristic)
  if [[ -n "$red_output" ]]; then
    if echo "$red_output" | grep -qiE '(panicked|assert|fail|error|expected|FAILED)'; then
      ok "RED output contains failure indicator"
    else
      warn "RED output may not contain a real assertion failure"
    fi
  fi

  # GREEN output should look like a real pass (heuristic)
  if [[ -n "$green_output" ]]; then
    if echo "$green_output" | grep -qiE '(ok|passed|PASSED|success)'; then
      ok "GREEN output contains pass indicator"
    else
      warn "GREEN output may not contain a real pass confirmation"
    fi
  fi

  # Refactor field: must be null or valid object
  local refactor_type
  refactor_type=$(jq -r '.refactor | type' "$file" 2>/dev/null)
  if [[ "$refactor_type" == "object" ]]; then
    local ref_summary ref_output
    ref_summary=$(jq -r '.refactor.summary // empty' "$file")
    ref_output=$(jq -r '.refactor.output // empty' "$file")
    [[ -z "$ref_summary" ]] && err "refactor.summary is empty (required when refactor is not null)"
    [[ -z "$ref_output" ]] && err "refactor.output is empty (must re-run after refactor)"
    ok "Refactor block present with summary"
  elif [[ "$refactor_type" == "null" ]]; then
    ok "No refactor (null)"
  else
    err "refactor must be null or an object, got: $refactor_type"
  fi

  return 0
}

# ── Validate story chain ───────────────────────────────────────────────────

validate_story() {
  local story_id="$1"
  local specific_iter="${2:-}"
  local story_dir="$EVIDENCE_ROOT/$story_id"

  echo "=== Validating RGR receipts for $story_id ==="

  if [[ ! -d "$story_dir" ]]; then
    err "No evidence directory: $story_dir"
    return 1
  fi

  local receipt_files
  receipt_files=$(find "$story_dir" -name '*.json' -type f | sort)

  if [[ -z "$receipt_files" ]]; then
    err "No receipt files found in $story_dir"
    return 1
  fi

  local count
  count=$(echo "$receipt_files" | wc -l | tr -d ' ')
  echo "Found $count receipt(s)"

  if [[ -n "$specific_iter" ]]; then
    # Validate single iteration
    local padded
    padded=$(printf "%03d" "$specific_iter")
    local target="$story_dir/${padded}.json"
    if [[ ! -f "$target" ]]; then
      err "Receipt not found: $target"
      return 1
    fi
    validate_receipt "$target" "$story_id" "$specific_iter"
  else
    # Validate all + check sequential
    local expected_iter=1
    while IFS= read -r receipt; do
      validate_receipt "$receipt" "$story_id" "$expected_iter"
      ((expected_iter++))
      echo ""
    done <<< "$receipt_files"

    # Summary
    local actual_count=$((expected_iter - 1))
    echo "=== Chain: $actual_count iteration(s), $errors error(s), $warnings warning(s) ==="
  fi
}

# ── Main ────────────────────────────────────────────────────────────────────

usage() {
  echo "Usage: plans/rgr_gate.sh <STORY_ID> [--iter N]"
  echo "       plans/rgr_gate.sh --all"
  echo "       plans/rgr_gate.sh --schema"
  exit 2
}

if [[ $# -lt 1 ]]; then
  usage
fi

case "$1" in
  --schema)
    print_schema
    exit 0
    ;;
  --all)
    if [[ ! -d "$EVIDENCE_ROOT" ]]; then
      echo "No evidence directory: $EVIDENCE_ROOT"
      exit 1
    fi
    total_errors=0
    for story_dir in "$EVIDENCE_ROOT"/*/; do
      story_id=$(basename "$story_dir")
      validate_story "$story_id"
      total_errors=$((total_errors + errors))
      errors=0
      echo ""
    done
    if [[ "$total_errors" -gt 0 ]]; then
      echo "TOTAL ERRORS: $total_errors"
      exit 1
    fi
    echo "ALL STORIES VALID"
    exit 0
    ;;
  --help|-h)
    usage
    ;;
  *)
    story_id="$1"
    shift
    iter_flag=""
    if [[ "${1:-}" == "--iter" ]]; then
      iter_flag="${2:-}"
      [[ -z "$iter_flag" ]] && usage
    fi
    validate_story "$story_id" "$iter_flag"
    if [[ "$errors" -gt 0 ]]; then
      echo ""
      echo "GATE FAILED: $errors error(s)"
      exit 1
    fi
    echo ""
    echo "GATE PASSED"
    exit 0
    ;;
esac
