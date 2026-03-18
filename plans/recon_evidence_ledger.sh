#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/recon_evidence_ledger.sh STORY_ID [--check|--scaffold] [--output <path>]

Purpose:
  Check for or scaffold the evidence ledger artifact required before:
    WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> cycle1

Options:
  --check            Validate JSON-first evidence ledger readiness (default)
  --scaffold         Create a starter JSON ledger when missing
  --output <path>    Override scaffold output path
  -h, --help         Show this help

Exit codes:
  0 = ready/found/scaffolded
  1 = missing/invalid/blocked in check mode
  2 = usage error
USAGE
}

story_id="${1:-}"
[[ -n "$story_id" ]] || { usage >&2; exit 2; }
shift || true

mode="check"
output_path=""

is_placeholder_ledger() {
  local path="$1"
  if [[ ! -f "$path" ]]; then
    return 1
  fi

  # Fail closed on known scaffold placeholders.
  if grep -Fq "AT-UNKNOWN" "$path"; then
    return 0
  fi
  if grep -Fq "Replace with real evidence before cycle1" "$path"; then
    return 0
  fi
  if grep -Fq "Replace with evidence-backed gap list entry." "$path"; then
    return 0
  fi
  return 1
}

trim_value() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

normalize_verdict() {
  local value
  value="$(trim_value "$1")"
  printf '%s' "$value" | tr '[:lower:]' '[:upper:]'
}

is_allowed_verdict() {
  local verdict="$1"
  case "$verdict" in
    PROVEN|PROVEN_INTEGRATED|PROVEN_UNIT|WEAK_PROOF|CLAIMED_NOT_PROVEN|UNTESTED_ENFORCEMENT|WRONG_IMPL_UNBLOCKED|FAIL_OPEN_RISK|MISSING|DEFERRED)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

has_file_line_citation() {
  local value="$1"
  [[ "$value" =~ [A-Za-z0-9_./-]+:[0-9]+ ]]
}

resolve_legacy_symbol_citation() {
  local value="$1"
  local file_path=""
  local symbol=""
  local line=""
  local match_line=""

  [[ "$value" == *"::"* ]] || return 1

  file_path="${value%%::*}"
  symbol="${value##*::}"
  file_path="$(trim_value "$file_path")"
  symbol="$(trim_value "$symbol")"

  [[ -n "$file_path" && -n "$symbol" ]] || return 1
  [[ -f "$file_path" ]] || return 1
  [[ "$symbol" =~ ^[A-Za-z0-9_]+$ ]] || return 1

  if command -v rg >/dev/null 2>&1; then
    match_line="$(rg -n -m1 "^[[:space:]]*(fn|def)[[:space:]]+${symbol}([[:space:](]|$)" "$file_path" 2>/dev/null | head -1 || true)"
  fi
  if [[ -z "$match_line" ]]; then
    match_line="$(grep -nE "^[[:space:]]*(fn|def)[[:space:]]+${symbol}([[:space:](]|$)" "$file_path" 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$match_line" ]] || return 1

  line="${match_line%%:*}"
  [[ "$line" =~ ^[0-9]+$ ]] || return 1

  printf '%s:%s' "$file_path" "$line"
}

emit_ledger_rows() {
  local ledger_path="$1"
  if [[ "$ledger_path" == *.json ]]; then
    jq -r '
      def as_str: if . == null then "" else tostring end;
      def first_nonempty($vals):
        ($vals | map(select(. != null and . != "")) | .[0] // "");
      (.evidence_ledger // .evidence // .) as $root
      | if (($root.at_verdicts // null) | type) == "array" then
        $root.at_verdicts[]
        | [
            (.at_id // .at // ""),
            (.verdict // .status // ""),
            ((.enforcement // .enforcement_point // .enforcement_ref // "") | as_str),
            ((.test // .test_ref // "") | as_str)
          ]
        | @tsv
      elif (($root.at_verdicts // null) | type) == "object" then
        ($root.at_verdicts | to_entries[]?)
        | [
            (.key // ""),
            (.value.verdict // .value.status // ""),
            (
              first_nonempty([
                (if ((.value.enforcement_file // null) != null and (.value.enforcement_line // null) != null)
                  then ((.value.enforcement_file | as_str) + ":" + (.value.enforcement_line | as_str))
                  else ""
                 end),
                (.value.enforcement // ""),
                (.value.enforcement_point // ""),
                (.value.enforcement_ref // "")
              ])
              | as_str
            ),
            (
              first_nonempty([
                (if ((.value.proving_tests // null) | type) == "array" and ((.value.proving_tests // []) | length) > 0
                  then (.value.proving_tests[0] // "")
                  else ""
                 end),
                (if ((.value.tests // null) | type) == "array" and ((.value.tests // []) | length) > 0
                  then (.value.tests[0].test_name // .value.tests[0].name // .value.tests[0].test // "")
                  else ""
                 end),
                (.value.test // ""),
                (.value.test_ref // "")
              ])
              | as_str
            )
          ]
        | @tsv
      elif (($root.ats // null) | type) == "array" then
        $root.ats[]
        | [
            (.at_id // .at // ""),
            (.at_verdict.verdict // .verdict // ""),
            ((.enforcement.evidence[0] // .enforcement_point // .enforcement // "") | as_str),
            ((if (.tests | type) == "array" and (.tests | length) > 0 then (.tests[0].test_name // .tests[0].name // .tests[0].test // "") else "" end) | as_str)
          ]
        | @tsv
      else
        empty
      end
    ' "$ledger_path" 2>/dev/null || true
  else
    awk -F'|' '
      /^\|/ {
        at=$2; verdict=$3; enforcement=$4; test=$5;
        gsub(/^[ \t]+|[ \t]+$/, "", at)
        gsub(/^[ \t]+|[ \t]+$/, "", verdict)
        gsub(/^[ \t]+|[ \t]+$/, "", enforcement)
        gsub(/^[ \t]+|[ \t]+$/, "", test)
        if (at == "" || at == "AT" || at ~ /^-+$/) {
          next
        }
        print at "\t" verdict "\t" enforcement "\t" test
      }
    ' "$ledger_path"
  fi
}

validate_ledger_against_prd() {
  local sid="$1"
  local ledger_path="$2"

  if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: jq is required for evidence ledger validation" >&2
    return 1
  fi

  local prd_file="plans/prd.json"
  if [[ ! -f "$prd_file" ]]; then
    echo "FAIL: missing PRD file at $prd_file" >&2
    return 1
  fi

  local story_exists
  story_exists="$(jq -r --arg id "$sid" 'any(.items[]?; .id == $id)' "$prd_file" 2>/dev/null || echo "false")"
  if [[ "$story_exists" != "true" ]]; then
    echo "FAIL: story $sid not found in $prd_file" >&2
    return 1
  fi

  local required_ats
  required_ats="$(jq -r --arg id "$sid" '.items[] | select(.id == $id) | (.enforcing_contract_ats // [])[]' "$prd_file" 2>/dev/null || true)"

  local ledger_rows
  ledger_rows="$(emit_ledger_rows "$ledger_path")"

  if [[ -n "$required_ats" && -z "$ledger_rows" ]]; then
    echo "FAIL: evidence ledger for $sid has no AT verdict rows at $ledger_path" >&2
    return 1
  fi

  if [[ -n "$ledger_rows" ]]; then
    while IFS=$'\t' read -r at verdict enforcement test_ref; do
      local normalized_verdict=""
      local enforcement_citation=""
      local test_citation=""
      local resolved_legacy=""

      [[ -z "$at" ]] && continue
      normalized_verdict="$(normalize_verdict "$verdict")"
      if [[ -z "$normalized_verdict" ]]; then
        echo "FAIL: evidence ledger row for $at has empty verdict at $ledger_path" >&2
        return 1
      fi
      if ! is_allowed_verdict "$normalized_verdict"; then
        echo "FAIL: evidence ledger row for $at has unknown verdict '$verdict' (normalized '$normalized_verdict') at $ledger_path" >&2
        return 1
      fi

      if [[ "$normalized_verdict" == "PROVEN" ]]; then
        enforcement_citation="$(trim_value "$enforcement")"
        test_citation="$(trim_value "$test_ref")"

        if ! has_file_line_citation "$enforcement_citation"; then
          if resolved_legacy="$(resolve_legacy_symbol_citation "$enforcement_citation")"; then
            enforcement_citation="$resolved_legacy"
          fi
        fi
        if ! has_file_line_citation "$enforcement_citation"; then
          echo "FAIL: PROVEN row for $at missing enforcement file:line citation at $ledger_path" >&2
          return 1
        fi

        if ! has_file_line_citation "$test_citation"; then
          if resolved_legacy="$(resolve_legacy_symbol_citation "$test_citation")"; then
            test_citation="$resolved_legacy"
          fi
        fi
        if ! has_file_line_citation "$test_citation"; then
          echo "FAIL: PROVEN row for $at missing test file:line citation at $ledger_path" >&2
          return 1
        fi
      fi
    done <<< "$ledger_rows"
  fi

  if [[ -n "$required_ats" ]]; then
    while IFS= read -r required_at; do
      [[ -z "$required_at" ]] && continue
      local found=0
      while IFS=$'\t' read -r at verdict enforcement test_ref; do
        [[ -z "$at" ]] && continue
        if [[ "$at" == "$required_at" ]]; then
          found=1
          break
        fi
      done <<< "$ledger_rows"

      if [[ "$found" -ne 1 ]]; then
        echo "FAIL: evidence ledger missing verdict row for required AT $required_at at $ledger_path" >&2
        return 1
      fi
    done <<< "$required_ats"
  fi

  return 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check"; shift ;;
    --scaffold) mode="scaffold"; shift ;;
    --output)
      output_path="${2:-}"
      [[ -n "$output_path" ]] || { echo "ERROR: --output requires a path" >&2; exit 2; }
      shift 2
      ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$story_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "ERROR: invalid STORY_ID '$story_id'" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repo" >&2
  exit 2
}
cd "$repo_root"

slice_id="${story_id%%-*}"
if [[ -z "$slice_id" || "$slice_id" == "$story_id" ]]; then
  if command -v jq >/dev/null 2>&1 && [[ -f "plans/prd.json" ]]; then
    slice_num="$(jq -r --arg sid "$story_id" '.items[] | select(.id == $sid) | .slice // empty' plans/prd.json 2>/dev/null | head -1 || true)"
    if [[ -n "$slice_num" ]]; then
      slice_id="S${slice_num}"
    fi
  fi
fi

candidate_paths=(
  "artifacts/story/${story_id}/evidence_ledger.json"
  "artifacts/story/${story_id}/${story_id}_reconciliation.json"
  "reviews/reconciliations/${slice_id}/${story_id}_reconciliation.json"
  "artifacts/story/${story_id}/evidence_ledger.md"
  "artifacts/story/${story_id}/${story_id}_reconciliation.md"
  "reviews/reconciliations/${slice_id}/${story_id}_reconciliation.md"
  "artifacts/story/${story_id}/preflight/audit.md"
)

found_path=""
placeholder_path=""
for p in "${candidate_paths[@]}"; do
  [[ -f "$p" ]] || continue
  if is_placeholder_ledger "$p"; then
    [[ -z "$placeholder_path" ]] && placeholder_path="$p"
    continue
  fi
  found_path="$p"
  break
done

if [[ "$mode" == "check" ]]; then
  if [[ -n "$found_path" ]]; then
    if ! validate_ledger_against_prd "$story_id" "$found_path"; then
      exit 1
    fi

    if [[ "$found_path" == *.md ]]; then
      echo "WARN: using legacy markdown evidence ledger path for $story_id at $found_path" >&2
      echo "  Migrate to artifacts/story/$story_id/evidence_ledger.json" >&2
    fi

    echo "OK: evidence ledger found for $story_id at $found_path"
    exit 0
  fi

  if [[ -n "$placeholder_path" ]]; then
    echo "FAIL: evidence ledger for $story_id is scaffold placeholder content at $placeholder_path" >&2
    echo "Replace scaffold placeholders with real AT evidence before cycle1." >&2
    exit 1
  fi

  echo "FAIL: no evidence ledger found for $story_id" >&2
  echo "Expected one of:" >&2
  for p in "${candidate_paths[@]}"; do
    echo "  - $p" >&2
  done
  echo "Scaffold command:" >&2
  echo "  plans/recon_evidence_ledger.sh $story_id --scaffold" >&2
  exit 1
fi

# --scaffold mode
if [[ -n "$found_path" ]]; then
  echo "OK: evidence ledger already exists for $story_id at $found_path"
  exit 0
fi

if [[ -z "$output_path" ]]; then
  output_path="artifacts/story/${story_id}/evidence_ledger.json"
fi

mkdir -p "$(dirname "$output_path")"

cat > "$output_path" <<EOF_JSON
{
  "story_id": "$story_id",
  "review_basis": "STORY_SCOPE",
  "path": "GREEN",
  "at_verdicts": [
    {
      "at_id": "AT-UNKNOWN",
      "verdict": "CLAIMED_NOT_PROVEN",
      "enforcement": "file:line::fn",
      "test": "file:line::test_fn",
      "notes": "Replace with real evidence before cycle1"
    }
  ],
  "gaps": [
    {
      "id": "GAP-${story_id}-1",
      "severity": "P1",
      "summary": "Replace with evidence-backed gap list entry."
    }
  ]
}
EOF_JSON

echo "OK: scaffolded evidence ledger at $output_path"
exit 0
