#!/usr/bin/env bash
# pattern_guard.sh — Diff-based scanner for fail-open code smells.
#
# Scans added lines in Rust files (git diff against BASE_REF) for patterns
# that indicate potential fail-open or unsafe code.
#
# Known limitations:
# - Macro-based evasion not detectable
# - Semantic analysis not possible (e.g., AT-201 intent classification correctness)
# - Diff-based: only scans changes since BASE_REF, not full codebase
# - unwrap_or_else closures flagged as advisory only (can't parse closure body)
# - Inline #[cfg(test)] modules within production files: uses heuristic tracking

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${BASE_REF:-origin/main}"

# Ensure BASE_REF is valid
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "ERROR: BASE_REF=$BASE_REF not resolvable (shallow clone?)" >&2
  echo "  Set PATTERN_GUARD_ALLOW_MISSING_BASE=1 to skip." >&2
  if [[ "${PATTERN_GUARD_ALLOW_MISSING_BASE:-0}" == "1" ]]; then
    echo "WARN: skipping pattern guard (PATTERN_GUARD_ALLOW_MISSING_BASE=1)" >&2
    exit 0
  fi
  exit 1
fi

ALLOWLIST_FILE="$ROOT/plans/pattern_guard_allowlist.txt"

# ── Extract diff ─────────────────────────────────────────────────────────

diff_output="$(git diff "$BASE_REF"...HEAD -- '*.rs' 2>/dev/null || true)"

if [[ -z "$diff_output" ]]; then
  echo "pattern_guard: no Rust diff against $BASE_REF — PASS"
  exit 0
fi

echo "pattern_guard: scanning diff against $BASE_REF"

# ── Step 1: Extract added lines with file context ────────────────────────
# Output format: FILE_PATH<TAB>CONTENT
# Excludes test files and #[cfg(test)] blocks

tmpfile="$(mktemp)"
trap 'rm -f "$tmpfile"' EXIT

# Parse diff once: extract file:content pairs for added non-test lines
current_file=""
in_test_block=0
while IFS= read -r line; do
  # Track current file
  if [[ "$line" == diff\ --git\ a/* ]]; then
    current_file="$(echo "$line" | sed 's|^diff --git a/\(.*\) b/.*|\1|')"
    in_test_block=0
    # Skip test files entirely
    case "$current_file" in
      */tests/*|*test_*) current_file="" ;;
    esac
    continue
  fi

  [[ -n "$current_file" ]] || continue

  # Heuristic: track #[cfg(test)] blocks on ALL diff lines (context, added, removed)
  # This must run before the added-line filter below
  case "$line" in
    *'#[cfg(test)]'*|*'mod tests'*)
      in_test_block=1
      ;;
  esac

  # Only look at added lines for pattern scanning
  case "$line" in
    +[!+]*) ;;
    *) continue ;;
  esac

  [[ "$in_test_block" -eq 0 ]] || continue

  local_content="${line#+}"

  printf '%s\t%s\n' "$current_file" "$local_content" >> "$tmpfile"
done <<< "$diff_output"

if [[ ! -s "$tmpfile" ]]; then
  echo "pattern_guard: no non-test added lines — PASS"
  exit 0
fi

# ── Step 2: Scan patterns against extracted lines ────────────────────────

blocking_count=0
advisory_count=0

scan_pattern() {
  local pattern_num="$1"
  local pattern_regex="$2"
  local severity="$3"
  local pattern_desc="$4"
  local exclude_pattern="${5:-}"

  local matches
  matches="$(grep -E "$pattern_regex" "$tmpfile" || true)"
  [[ -n "$matches" ]] || return 0

  # Apply exclusions
  if [[ -n "$exclude_pattern" ]]; then
    matches="$(echo "$matches" | grep -vE "$exclude_pattern" || true)"
    [[ -n "$matches" ]] || return 0
  fi

  # Apply allowlist
  if [[ -f "$ALLOWLIST_FILE" ]]; then
    local filtered=""
    while IFS= read -r match_line; do
      local file_path
      file_path="$(echo "$match_line" | cut -f1)"
      local key="${file_path}:${pattern_num}"
      if ! grep -qxF "$key" "$ALLOWLIST_FILE" 2>/dev/null; then
        filtered="${filtered}${match_line}"$'\n'
      fi
    done <<< "$matches"
    matches="${filtered%$'\n'}"
    [[ -n "$matches" ]] || return 0
  fi

  local count
  count="$(echo "$matches" | wc -l | tr -d ' ')"

  echo "$matches" | while IFS=$'\t' read -r file content; do
    echo "  [$severity] P${pattern_num} ($pattern_desc): $file: $content"
  done

  if [[ "$severity" == "BLOCK" ]]; then
    blocking_count=$((blocking_count + count))
  else
    advisory_count=$((advisory_count + count))
  fi
}

# NOTE: scan_pattern modifies blocking_count/advisory_count via direct assignment.
# Do NOT pipe these calls (e.g., `scan_pattern ... | tee`) — subshell would discard counts.

# Pattern 1: unwrap/expect family (BLOCK)
scan_pattern "1" '\.unwrap(_unchecked)?[[:space:]]*\(|\.expect[[:space:]]*\(' "BLOCK" "unwrap/expect"

# Pattern 2: warn on missing config (Advisory)
scan_pattern "2" 'warn!.*missing|warn!.*not found' "Advisory" "warn-missing-config"

# Pattern 3: Direct state assignment outside authority modules (BLOCK)
# Matches single `=` (assignment) but not `==` (comparison) or `=>` (match arm).
# Exclude authority modules: policy_guard, build_order_intent, state.rs, risk/mod.rs
scan_pattern "3" 'risk_state[[:space:]]*=[^=>\!]|trading_mode[[:space:]]*=[^=>\!]' "BLOCK" "direct-state-assign" \
  'policy_guard|build_order_intent|state\.rs|risk/mod\.rs'

# Pattern 4: Fail-open defaults (BLOCK)
scan_pattern "4" 'unwrap_or\(0\.0\)|unwrap_or\(f64::INFINITY\)|unwrap_or\(f64::MAX\)|unwrap_or\(Active\)|unwrap_or\(Healthy\)|unwrap_or\(RiskState::Healthy\)|unwrap_or\(TradingMode::Active\)|unwrap_or_default\(\)' "BLOCK" "fail-open-default"

# Pattern 5: Silent Result discard (BLOCK)
scan_pattern "5" 'let[[:space:]]+_[[:space:]]*=.*\.(ok|map_err|unwrap|expect)' "BLOCK" "silent-result-discard"

# Pattern 6: unwrap_or_else (Advisory)
scan_pattern "6" 'unwrap_or_else' "Advisory" "unwrap_or_else"

echo ""
echo "pattern_guard summary: blocking=$blocking_count advisory=$advisory_count"

if [[ "$blocking_count" -gt 0 ]]; then
  echo "FAIL: $blocking_count blocking pattern violation(s) found" >&2
  exit 1
fi

echo "pattern_guard: PASS"
exit 0
