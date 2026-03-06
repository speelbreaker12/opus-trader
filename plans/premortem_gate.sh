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

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

is_valid_gap_id_list() {
  local value
  value="$(trim "$1")"
  [[ "$value" =~ ^GAP-[A-Za-z0-9-]+([[:space:]]*,[[:space:]]*GAP-[A-Za-z0-9-]+)*$ ]]
}

validate_trading_risk_hard_gate() {
  local file="$1" stoplight="$2"
  local section=""
  local question=""
  local row=""
  local answer=""
  local why=""
  local proof=""
  local gap_id=""
  local question_col=""
  local i=0
  local blocking_answer=""
  local blocking_question=""
  local debt_section=""
  local gap_group=""
  local gap_item=""
  local old_ifs=""
  local unknown_answer_seen=false

  grep -Eq '^## Trading Risk Hard Gate([[:space:]]*\(.*\))?$' "$file" \
    || die "missing required heading: ## Trading Risk Hard Gate"

  section="$(
    sed -n '/^## Trading Risk Hard Gate/,/^## 1)/{ /^## /d; p; }' "$file" \
      | grep -v '^[[:space:]]*$' || true
  )"
  [[ -n "$section" ]] || die "Trading Risk Hard Gate section is empty"

  for question in \
    "Loss prevention" \
    "Profit preservation" \
    "Best design choice" \
    "Better alternative check" \
    "Failure-path correctness" \
    "Fail-closed enforcement" \
    "Proof, not belief"; do
    row="$(
      printf '%s\n' "$section" | awk -F'|' -v q="$question" '
        function trim_field(s) {
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
          return s
        }
        /^\|/ {
          for (i = 2; i <= NF; i++) {
            if (trim_field($i) == q) {
              print
              exit
            }
          }
        }
      '
    )"
    [[ -n "$row" ]] || die "Trading Risk Hard Gate missing row: $question"

    IFS='|' read -r -a columns <<< "$row"
    question_col=""
    for (( i = 1; i < ${#columns[@]}; i++ )); do
      if [[ "$(trim "${columns[$i]}")" == "$question" ]]; then
        question_col="$i"
        break
      fi
    done
    [[ -n "$question_col" ]] || die "Trading Risk Hard Gate row '$question' could not be parsed"

    answer="$(trim "${columns[$((question_col + 1))]:-}")"
    why="$(trim "${columns[$((question_col + 2))]:-}")"
    proof="$(trim "${columns[$((question_col + 3))]:-}")"
    gap_id="$(trim "${columns[$((question_col + 4))]:-}")"

    [[ "$answer" =~ ^(YES|NO|UNKNOWN)$ ]] \
      || die "Trading Risk Hard Gate row '$question' has invalid answer '$answer' (expected YES/NO/UNKNOWN)"
    [[ -n "$why" && "$why" != "-" ]] \
      || die "Trading Risk Hard Gate row '$question' is missing Why"
    [[ -n "$proof" && "$proof" != "-" ]] \
      || die "Trading Risk Hard Gate row '$question' is missing Proof"

    if [[ "$answer" == "NO" || "$answer" == "UNKNOWN" ]]; then
      if [[ -z "$gap_id" || "$gap_id" == "-" || "$gap_id" == "N/A" || "$gap_id" == "NONE" ]]; then
        die "Trading Risk Hard Gate row '$question' requires Gap ID for answer $answer"
      fi
      is_valid_gap_id_list "$gap_id" \
        || die "Trading Risk Hard Gate row '$question' has invalid Gap ID list '$gap_id'"
      if [[ "$answer" == "NO" && -z "$blocking_answer" ]]; then
        blocking_answer="$answer"
        blocking_question="$question"
      fi
      if [[ "$answer" == "UNKNOWN" ]]; then
        unknown_answer_seen=true
      fi
    fi
  done

  echo "$section" | grep -Fq "GO only if all 7 answers are YES with concrete proof." \
    || die "Trading Risk Hard Gate missing GO decision rule"
  echo "$section" | grep -Fq "YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment." \
    || die "Trading Risk Hard Gate missing YELLOW decision rule"
  echo "$section" | grep -Fq "NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim." \
    || die "Trading Risk Hard Gate missing NO-GO decision rule"

  if [[ -n "$blocking_answer" ]]; then
    die "Trading Risk Hard Gate row '$blocking_question' hard gate blocks implementation for answer $blocking_answer"
  fi

  if [[ "$unknown_answer_seen" == "true" ]]; then
    [[ "$stoplight" == "YELLOW" ]] \
      || die "Trading Risk Hard Gate has UNKNOWN answers but STOPLIGHT is $stoplight (expected YELLOW with containment)"

    debt_section="$(section_content "$file" "## 10) STOPLIGHT")"
    printf '%s\n' "$debt_section" | grep -Fq "**Debt Register**" \
      || die "Trading Risk Hard Gate requires Debt Register when STOPLIGHT is YELLOW"

    for question in \
      "Loss prevention" \
      "Profit preservation" \
      "Best design choice" \
      "Better alternative check" \
      "Failure-path correctness" \
      "Fail-closed enforcement" \
      "Proof, not belief"; do
      row="$(
        printf '%s\n' "$section" | awk -F'|' -v q="$question" '
          function trim_field(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
          }
          /^\|/ {
            for (i = 2; i <= NF; i++) {
              if (trim_field($i) == q) {
                print
                exit
              }
            }
          }
        '
      )"
      [[ -n "$row" ]] || continue

      IFS='|' read -r -a columns <<< "$row"
      question_col=""
      for (( i = 1; i < ${#columns[@]}; i++ )); do
        if [[ "$(trim "${columns[$i]}")" == "$question" ]]; then
          question_col="$i"
          break
        fi
      done
      [[ -n "$question_col" ]] || continue

      answer="$(trim "${columns[$((question_col + 1))]:-}")"
      gap_id="$(trim "${columns[$((question_col + 4))]:-}")"
      [[ "$answer" == "UNKNOWN" ]] || continue

      old_ifs="$IFS"
      IFS=','
      read -r -a gap_ids <<< "$gap_id"
      IFS="$old_ifs"
      for gap_group in "${gap_ids[@]}"; do
        gap_item="$(trim "$gap_group")"
        [[ -n "$gap_item" ]] || continue
        printf '%s\n' "$debt_section" | grep -Fq "| $gap_item |" \
          || die "Trading Risk Hard Gate UNKNOWN Gap ID '$gap_item' missing from Debt Register"
      done
    done
  fi
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
stoplight_value="$(sed -nE 's/^\*\*STOPLIGHT\*\*: (GREEN|YELLOW|RED)$/\1/p' "$pm" | head -1)"
[[ -n "$stoplight_value" ]] || die "missing or invalid STOPLIGHT line"

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

premortem_schema_v2=false
if grep -Fq "> Premortem Schema: v2" "$pm"; then
  premortem_schema_v2=true
fi

if [[ "$premortem_schema_v2" == "true" ]] || grep -Eq '^## Trading Risk Hard Gate([[:space:]]*\(.*\))?$' "$pm"; then
  validate_trading_risk_hard_gate "$pm" "$stoplight_value"
fi

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
echo "OK: premortem gate passed for $story_id"
echo "  artifact: $pm"
echo "  STOPLIGHT: $stoplight_value"
