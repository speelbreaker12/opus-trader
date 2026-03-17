#!/usr/bin/env bash
set -euo pipefail

# review_matrix.sh — Run the full 4-combo review matrix for a story cycle.
#
# Ensures all 4 mandatory tool x prompt combinations are executed:
#   codex + enriched, codex + generic, sonnet + enriched, sonnet + generic
#
# Usage:
#   plans/review_matrix.sh <STORY_ID> --cycle <c1|c2> --base <BASE_REF> [--dry-run]
#
# Cycle 1 (R3 / story-scope):  4 review_logged.sh runs against story diff
# Cycle 2 (R7d / fix-diff):    4 review_logged.sh runs against fix diff

usage() {
  cat <<'USAGE'
Usage:
  plans/review_matrix.sh <STORY_ID> --cycle <c1|c2> --base <BASE_REF> [options]

Options:
  --cycle CYCLE   Required: c1 (Cycle 1 / R3) or c2 (Cycle 2 / R7d)
  --base REF      Required: base ref for diff
  --dry-run       Print commands without executing
  --continue      Continue on individual review failure (default: stop on first)

Matrix (always all 4):
  codex  + enriched
  codex  + generic
  sonnet + enriched
  sonnet + generic

Canonical outputs (per review_logged.sh normalization):
  artifacts/story/<ID>/<tool>/<tool>.<prompt_style>.md
USAGE
}

die() { echo "ERROR: $*" >&2; exit 1; }

story="${1:-}"
[[ -n "$story" ]] || { usage >&2; exit 2; }
shift

cycle=""
base=""
dry_run=false
continue_on_fail=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cycle)
      cycle="${2:?missing cycle (c1|c2)}"
      shift 2
      ;;
    --base)
      base="${2:?missing base ref}"
      shift 2
      ;;
    --dry-run)
      dry_run=true
      shift
      ;;
    --continue)
      continue_on_fail=true
      shift
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

[[ -n "$cycle" ]] || die "--cycle is required (c1 or c2)"
[[ -n "$base" ]]  || die "--base is required"

case "$cycle" in
  c1|C1) cycle_label="Cycle 1 (R3 / story-scope)" ;;
  c2|C2) cycle_label="Cycle 2 (R7d / fix-diff + AT regression)" ;;
  *) die "unknown cycle '$cycle' (expected: c1 or c2)" ;;
esac

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not in a git repo"
review_script="$repo_root/plans/review_logged.sh"
[[ -x "$review_script" ]] || die "review_logged.sh not found or not executable"

# ── Matrix definition ────────────────────────────────────────────────

TOOLS=("codex" "sonnet")
PROMPTS=("enriched" "generic")

echo "=== Review Matrix: $story — $cycle_label ==="
echo "  Base: $base"
echo ""

total=0
passed=0
failed=0

for tool in "${TOOLS[@]}"; do
  for prompt in "${PROMPTS[@]}"; do
    total=$((total + 1))
    cmd="$review_script $story --tool $tool --prompt $prompt --base $base"
    echo "[$total/4] $tool + $prompt"

    if $dry_run; then
      echo "  [DRY RUN] $cmd"
      echo ""
      passed=$((passed + 1))
      continue
    fi

    echo "  Running: $cmd"
    set +e
    $cmd
    rc=$?
    set -e

    if [[ $rc -eq 0 ]]; then
      passed=$((passed + 1))
      echo "  OK ($tool + $prompt)"
    else
      failed=$((failed + 1))
      echo "  FAILED ($tool + $prompt, exit=$rc)" >&2
      if ! $continue_on_fail; then
        die "Stopping after first failure. Use --continue to run all combos."
      fi
    fi
    echo ""
  done
done

echo "=== Matrix Summary ==="
echo "  Total:  $total"
echo "  Passed: $passed"
echo "  Failed: $failed"

if [[ $failed -gt 0 ]]; then
  die "$failed/$total reviews failed"
fi

echo ""
echo "All $total reviews completed. Canonical artifacts:"
for tool in "${TOOLS[@]}"; do
  for prompt in "${PROMPTS[@]}"; do
    echo "  artifacts/story/$story/$tool/$tool.$prompt.md"
  done
done
exit 0
