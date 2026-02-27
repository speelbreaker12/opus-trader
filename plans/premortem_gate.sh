#!/usr/bin/env bash
set -euo pipefail

# Fail-closed gate for structured premortem artifacts.
# Validates content depth, not just existence.
# Same pattern as postmortem_gate.sh.

usage() {
  cat <<'USAGE'
Usage:
  ./plans/premortem_gate.sh <STORY_ID> [--premortems-dir <path>]

Purpose:
  Fail-closed gate for structured premortem artifacts.
  Exit 0 only if all checks pass.

Exit codes:
  0 = pass
  1 = validation failure
  2 = usage error
USAGE
}

die() { echo "FAIL: $*" >&2; exit 1; }

require_heading() {
  local file="$1" heading="$2"
  grep -Fxq -- "$heading" "$file" || die "missing required heading: $heading"
}

# Accept minor typography variants for legacy premortems while preserving section intent.
require_heading_any() {
  local file="$1"
  local canonical="$2"
  shift 2
  local heading=""
  if grep -Fxq -- "$canonical" "$file"; then
    return 0
  fi
  for heading in "$@"; do
    if grep -Fxq -- "$heading" "$file"; then
      return 0
    fi
  done
  die "missing required heading: $canonical"
}

# Extract section content between a heading and the next ## heading (or EOF)
section_content() {
  local file="$1" heading="$2"
  sed -n "/^${heading}/,/^## [0-9]/{/^## /d; p;}" "$file" | grep -v '^[[:space:]]*$' || true
}

# Extract by section number to avoid brittle heading-text dependencies.
section_number_content() {
  local file="$1" section_num="$2"
  sed -n "/^## ${section_num})/,/^## [0-9]/{/^## /d; p;}" "$file" | grep -v '^[[:space:]]*$' || true
}

# Count non-empty, non-header rows in a markdown table (lines starting with |, excluding |---|)
table_rows() {
  local content="$1"
  echo "$content" | awk '
    /^\|/ && $0 !~ /^\|[-| ]+\|$/ { count++ }
    END { print count + 0 }
  '
}

# --- args ---
story_id="${1:-}"
[[ -n "$story_id" ]] || { usage >&2; exit 2; }
shift

premortems_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --premortems-dir) premortems_dir="${2:?missing path}"; shift 2 ;;
    -h|--help)        usage; exit 0 ;;
    *)                echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "ERROR: not in a git repo" >&2; exit 2; }
cd "$repo_root"

if [[ -z "$premortems_dir" ]]; then
  premortems_dir="$repo_root/reviews/premortems"
fi
[[ "$premortems_dir" != /* ]] && premortems_dir="$repo_root/$premortems_dir"

# --- artifact exists ---
pm="$premortems_dir/${story_id}_premortem.md"
[[ -f "$pm" ]] || die "premortem artifact not found: $pm"

# --- Story ID in header ---
grep -Eq "^# Story Premortem: $story_id" "$pm" || die "header missing or wrong Story ID (expected: # Story Premortem: $story_id)"

# --- no placeholder markers ---
for marker in '<TODO>' 'TBD' 'FILL_ME'; do
  if grep -Fq -- "$marker" "$pm"; then
    die "placeholder marker found: $marker"
  fi
done

# --- STOPLIGHT ---
grep -Eq '^\*\*STOPLIGHT\*\*: (GREEN|YELLOW|RED)' "$pm" || die "missing or invalid STOPLIGHT line"

# --- required section headings (§0-§10) ---
require_heading "$pm" "## 0) What we're building"
require_heading_any "$pm" \
  "## 1) Clause audit (contract → AT traceability)" \
  "## 1) Clause audit (contract -> AT traceability)"
require_heading "$pm" "## 2) Assumptions (each must become a test or get killed)"
require_heading_any "$pm" \
  "## 3) Top 5 failure modes" \
  "## 3) Top 7 failure modes"
require_heading "$pm" "## 4) Open decisions (resolve before coding)"
require_heading "$pm" "## 5) Wrong implementation gate"
require_heading_any "$pm" \
  "## 6) Proof plan (AT → enforcement → tests)" \
  "## 6) Proof plan (AT -> enforcement -> tests)"
require_heading "$pm" "## 7) Economic risk (loss_mode)"
require_heading "$pm" "## 8) Conflict scan & hot zones"
require_heading "$pm" "## 9) Constraint I expect to hit"
require_heading "$pm" "## 10) STOPLIGHT + Exit criteria"

# --- §0: Story line filled ---
s0=$(section_content "$pm" "## 0) What we're building")
echo "$s0" | grep -Eq '^- Story: .+' || die "§0 missing filled 'Story:' line"
echo "$s0" | grep -Eq '^- Contract clause' || die "§0 missing 'Contract clause' line"
echo "$s0" | grep -Eq '^- Acceptance tests: AT-' || die "§0 missing 'Acceptance tests: AT-' line"

# --- §1: Clause audit table has rows ---
s1=$(section_content "$pm" "## 1) Clause audit")
rows=$(table_rows "$s1")
if [[ "$rows" -lt 1 ]]; then
  die "§1 clause audit table is empty (need at least 1 AT row)"
fi

# --- §3: Failure modes table has at least 3 rows ---
s3=$(section_number_content "$pm" "3")
rows=$(table_rows "$s3")
if [[ "$rows" -lt 3 ]]; then
  die "§3 failure modes table has $rows rows (need at least 3)"
fi

# --- §5: Wrong implementation table has rows ---
s5=$(section_content "$pm" "## 5) Wrong implementation gate")
rows=$(table_rows "$s5")
if [[ "$rows" -lt 1 ]]; then
  die "§5 wrong implementation table is empty (need at least 1 AT row)"
fi

# --- §6: Proof plan table has rows ---
s6=$(section_content "$pm" "## 6) Proof plan")
rows=$(table_rows "$s6")
if [[ "$rows" -lt 1 ]]; then
  die "§6 proof plan table is empty (need at least 1 AT row)"
fi

# --- §7: Economic risk has loss content ---
s7=$(section_content "$pm" "## 7) Economic risk")
echo "$s7" | grep -Eq 'worst financial outcome' || die "§7 missing 'worst financial outcome' content"
echo "$s7" | grep -Eq '(Fail-closed cap|fail-closed cap)' || die "§7 missing 'Fail-closed cap' content"

# --- §9: Carry-forward lines ---
grep -q '^Prior Postmortem: ' "$pm" || die "§9 missing required line: 'Prior Postmortem: <path or NONE>'"
grep -q '^Reused Guardrail: ' "$pm" || die "§9 missing required line: 'Reused Guardrail: <rule or NONE>'"

# --- §10: Exit criteria checklist items ---
s10=$(section_content "$pm" "## 10) STOPLIGHT")
checklist_count=$(echo "$s10" | grep -cE '^\- \[' 2>/dev/null || echo 0)
if [[ "$checklist_count" -lt 5 ]]; then
  die "§10 exit criteria has $checklist_count checklist items (need at least 5)"
fi

# --- pass ---
stoplight="$(grep -oE 'STOPLIGHT\*\*: (GREEN|YELLOW|RED)' "$pm" | head -1 || echo "?")"
echo "OK: premortem gate passed for $story_id"
echo "  artifact: $pm"
echo "  $stoplight"
