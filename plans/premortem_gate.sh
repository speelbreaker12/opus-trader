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

is_nonempty_debt_cell() {
  local value
  value="$(trim "$1")"
  [[ -n "$value" && "$value" != "-" ]]
}

validate_trading_risk_hard_gate() {
  local file="$1"
  local stoplight="$2"
  local section=""
  local question=""
  local row=""
  local answer=""
  local why=""
  local proof=""
  local gap_id=""
  local yes_count=0
  local no_count=0
  local unknown_count=0
  local section10=""
  local debt_row=""
  local debt_why=""
  local debt_owner=""
  local debt_target=""
  local seen_gaps="|"
  local split_gap=""
  local -a trading_gap_ids=()
  local -a split_gap_ids=()

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
          if (trim_field($2) == q) {
            print
            exit
          }
        }
      '
    )"
    [[ -n "$row" ]] || die "Trading Risk Hard Gate missing row: $question"

    IFS='|' read -r _ _col_question _col_answer _col_why _col_proof _col_gap _ <<< "$row"
    answer="$(trim "${_col_answer:-}")"
    why="$(trim "${_col_why:-}")"
    proof="$(trim "${_col_proof:-}")"
    gap_id="$(trim "${_col_gap:-}")"

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

      IFS=',' read -r -a split_gap_ids <<< "$gap_id"
      for split_gap in "${split_gap_ids[@]}"; do
        split_gap="$(trim "$split_gap")"
        [[ -n "$split_gap" ]] && trading_gap_ids+=("$split_gap")
      done

      if [[ "$answer" == "NO" ]]; then
        no_count=$((no_count + 1))
      else
        unknown_count=$((unknown_count + 1))
      fi
    else
      yes_count=$((yes_count + 1))
    fi
  done

  echo "$section" | grep -Fq "GO only if all 7 answers are YES with concrete proof." \
    || die "Trading Risk Hard Gate missing GO decision rule"
  echo "$section" | grep -Fq "YELLOW if the change is still design-reviewable but one or more answers are UNKNOWN with explicit Gap IDs and containment." \
    || die "Trading Risk Hard Gate missing YELLOW decision rule"
  echo "$section" | grep -Fq "NO-GO if any answer is NO, or if proof is missing for any loss-prevention or fail-closed claim." \
    || die "Trading Risk Hard Gate missing NO-GO decision rule"

  # UNKNOWN may remain reviewable under explicit YELLOW debt, but an explicit NO
  # is always a hard block per the Trading Risk Hard Gate decision rule.
  if [[ "$no_count" -gt 0 ]]; then
    die "Trading Risk Hard Gate has NO answers; premortem is NO-GO"
  fi

  if [[ "$stoplight" == "GREEN" ]] && [[ "$unknown_count" -gt 0 ]]; then
    die "STOPLIGHT is GREEN but Trading Risk Hard Gate has UNKNOWN answers"
  fi

  if [[ "${#trading_gap_ids[@]}" -gt 0 ]]; then
    section10="$(section_content "$file" "## 10) STOPLIGHT")"
    for split_gap in "${trading_gap_ids[@]}"; do
      if [[ "$seen_gaps" == *"|$split_gap|"* ]]; then
        continue
      fi
      seen_gaps="${seen_gaps}${split_gap}|"

      debt_row="$(
        printf '%s\n' "$section10" | awk -F'|' -v target_gap="$split_gap" '
          function trim_field(s) {
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
            return s
          }
          /^\|/ {
            if (trim_field($2) == target_gap) {
              print
              exit
            }
          }
        '
      )"
      [[ -n "$debt_row" ]] || die "Trading Risk Hard Gate Gap ID '$split_gap' must be listed in §10 Debt Register"

      IFS='|' read -r _ _debt_gap _debt_item _debt_severity _debt_why _debt_owner _debt_target _debt_proof _ <<< "$debt_row"
      debt_why="$(trim "${_debt_why:-}")"
      debt_owner="$(trim "${_debt_owner:-}")"
      debt_target="$(trim "${_debt_target:-}")"

      is_nonempty_debt_cell "$debt_why" || die "Debt Register row '$split_gap' is missing Why deferred/containment"
      is_nonempty_debt_cell "$debt_owner" || die "Debt Register row '$split_gap' is missing Owner"
      is_nonempty_debt_cell "$debt_target" || die "Debt Register row '$split_gap' is missing Target slice"
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
grep -Eq '^\*\*STOPLIGHT\*\*: (GREEN|YELLOW|RED)' "$pm" || die "missing or invalid STOPLIGHT line"
stoplight_value="$(grep -oE '^\*\*STOPLIGHT\*\*:[[:space:]]*(GREEN|YELLOW|RED)' "$pm" | head -1 | grep -oE '(GREEN|YELLOW|RED)' | head -1 || true)"
[[ -n "$stoplight_value" ]] || die "failed to parse STOPLIGHT value"

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
