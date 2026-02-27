#!/usr/bin/env bash
set -euo pipefail

# PREMORTEM_READY gate — checks if a story can enter reconciliation mode.
#
# Usage: plans/premortem_ready.sh STORY_ID [--json]
#
# Exit codes:
#   0 = ready
#   1 = not ready (reasons printed to stderr, JSON to stdout if --json)
#   2 = usage error
#
# Checks:
#   1. reviews/premortems/${STORY_ID}_premortem.md exists
#   2. premortem_gate.sh passes (sections present, no placeholders)
#   3. STOPLIGHT != RED
#   4. No AT ownership conflicts (no AT claimed as primary by 2+ stories globally)
#
# Output (--json): premortem_ready.json matching specs/schemas/recon/premortem_ready.schema.json

usage() {
  cat <<'USAGE'
Usage: plans/premortem_ready.sh STORY_ID [--json]

Mechanical gate that checks if a story's premortem is ready for reconciliation.

Options:
  --json    Output structured JSON to stdout
  -h|--help Show this help

Exit codes:
  0 = ready
  1 = not ready
  2 = usage error
USAGE
}

# --- args ---
story_id="${1:-}"
if [[ -z "$story_id" ]]; then
  usage >&2
  exit 2
fi
shift

json_mode=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json)   json_mode=true; shift ;;
    -h|--help) usage; exit 0 ;;
    *)        echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

# --- locate repo root ---
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repo" >&2
  exit 2
}
cd "$repo_root"

PREMORTEM_PATH="reviews/premortems/${story_id}_premortem.md"
reasons=()
premortem_gate_detail=""

# ---- Check 1: premortem file exists ----
premortem_exists=false
if [[ -f "$PREMORTEM_PATH" ]]; then
  premortem_exists=true
else
  reasons+=("premortem file not found: $PREMORTEM_PATH")
fi

# ---- Check 2: premortem_gate.sh passes ----
premortem_gate_exit_code=127
if [[ -x "plans/premortem_gate.sh" ]]; then
  if premortem_gate_output="$(plans/premortem_gate.sh "$story_id" 2>&1)"; then
    premortem_gate_exit_code=0
  else
    premortem_gate_exit_code=$?
    reasons+=("premortem_gate.sh failed with exit code $premortem_gate_exit_code")
    premortem_gate_detail="$(printf '%s\n' "$premortem_gate_output" | head -n 1 || true)"
    [[ -n "$premortem_gate_detail" ]] && reasons+=("premortem_gate detail: $premortem_gate_detail")
  fi
elif [[ -f "plans/premortem_gate.sh" ]]; then
  # File exists but not executable — try running via bash
  if premortem_gate_output="$(bash plans/premortem_gate.sh "$story_id" 2>&1)"; then
    premortem_gate_exit_code=0
  else
    premortem_gate_exit_code=$?
    reasons+=("premortem_gate.sh failed with exit code $premortem_gate_exit_code")
    premortem_gate_detail="$(printf '%s\n' "$premortem_gate_output" | head -n 1 || true)"
    [[ -n "$premortem_gate_detail" ]] && reasons+=("premortem_gate detail: $premortem_gate_detail")
  fi
else
  # Script doesn't exist — fail-closed (missing gate = cannot validate)
  premortem_gate_exit_code=127
  reasons+=("premortem_gate.sh not found: cannot validate section quality")
  echo "FAIL: plans/premortem_gate.sh not found — fail-closed" >&2
fi

# ---- Check 3: STOPLIGHT != RED ----
stoplight="RED"
stoplight_is_red=true
if [[ "$premortem_exists" == "true" ]]; then
  stoplight_match="$(grep -oE '\*\*STOPLIGHT\*\*:\s*(GREEN|YELLOW|RED)' "$PREMORTEM_PATH" | head -1 || true)"
  if [[ -n "$stoplight_match" ]]; then
    stoplight="$(echo "$stoplight_match" | grep -oE '(GREEN|YELLOW|RED)' | head -1)"
    if [[ "$stoplight" == "RED" ]]; then
      stoplight_is_red=true
      reasons+=("STOPLIGHT is RED")
    else
      stoplight_is_red=false
    fi
  else
    # Fail-closed: missing stoplight → treat as RED
    stoplight="RED"
    stoplight_is_red=true
    reasons+=("STOPLIGHT line not found in premortem (defaulting to RED — fail-closed)")
  fi
else
  # No premortem → RED
  stoplight="RED"
  stoplight_is_red=true
fi

# ---- Check 4: YELLOW gap disposition ----
# POLICY §3.2 check 4 (pragmatic parsing): if STOPLIGHT is YELLOW, unresolved debt rows
# in the §10 Debt/Deferral Register block the story. A row is considered resolved for entry if it has
# either explicit "FIX IN STEP 5" or a non-empty "Why deferred" reason.
yellow_gaps_ok=true
if [[ "$premortem_exists" == "true" && "$stoplight" == "YELLOW" ]]; then
  # Extract §10 content (between "## 10)" and EOF or next "## ")
  s10_content="$(sed -n '/^## 10)/,/^## [0-9]/{/^## [0-9]/!p;}' "$PREMORTEM_PATH" 2>/dev/null || true)"
  if [[ -z "$s10_content" ]]; then
    # Also try to end of file if §10 is last section
    s10_content="$(sed -n '/^## 10)/,$p' "$PREMORTEM_PATH" 2>/dev/null || true)"
  fi

  # Evaluate only Debt Register rows to avoid false positives from explanatory prose/checklists.
  unresolved_yellow_gaps=0
  debt_register_rows=0
  in_debt_register=false
  while IFS= read -r line; do
    [[ "$line" =~ ^##[[:space:]] ]] && break
    if [[ "$line" =~ ^\*\*(Debt|Deferral)[[:space:]]Register\*\* ]]; then
      in_debt_register=true
      continue
    fi
    [[ "$in_debt_register" == "true" ]] || continue

    # Only process table rows after Debt Register heading.
    [[ "$line" =~ ^\| ]] || continue
    # Skip separator/header rows.
    if echo "$line" | grep -qE '^\|[-|[:space:]]+\|$' 2>/dev/null; then
      continue
    fi
    if echo "$line" | grep -qiE '^\|[[:space:]]*Item[[:space:]]*\|' 2>/dev/null; then
      continue
    fi

    debt_register_rows=$((debt_register_rows + 1))

    # Parse "Why deferred" column (3rd content column in a 6-column table).
    IFS='|' read -r _ col_item col_severity col_why col_owner col_target col_proof _ <<< "$line"
    why_deferred="$(echo "${col_why:-}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    if echo "$line" | grep -qiE 'FIX IN STEP 5' 2>/dev/null; then
      continue
    fi
    if [[ -z "$why_deferred" ]]; then
        unresolved_yellow_gaps=$((unresolved_yellow_gaps + 1))
    fi
  done <<< "$s10_content"

  if [[ $debt_register_rows -eq 0 ]]; then
    yellow_gaps_ok=false
    reasons+=("STOPLIGHT is YELLOW but §10 Debt/Deferral Register has no gap rows")
  elif [[ $unresolved_yellow_gaps -gt 0 ]]; then
    yellow_gaps_ok=false
    reasons+=("STOPLIGHT is YELLOW with $unresolved_yellow_gaps unresolved debt row(s) (missing Why deferred/FIX IN STEP 5)")
  fi

fi

# ---- Check 5: AT ownership conflicts ----
ownership_conflicts=0
ownership_conflict_details=()
ownership_conflict_human=()
if [[ -f "plans/prd.json" ]] && command -v jq >/dev/null 2>&1; then
  # Determine ownership from PRD metadata:
  # - If primary_owner_for key exists, use it (even if empty: explicit shared-only story)
  # - Else fallback to enforcing_contract_ats for legacy stories
  conflict_json="$(jq -c --arg sid "$story_id" '
    def owner_claims:
      if has("primary_owner_for") then
        (.primary_owner_for // [])
      else
        (.enforcing_contract_ats // [])
      end;

    ([.items[]? | {id, claims: (owner_claims | map(tostring))}] ) as $stories
    | ($stories[]? | select(.id == $sid) | .claims // []) as $my_claims
    | [
        $my_claims[] as $at
        | {at_id: $at, claiming_stories: [$stories[] | select((.claims // []) | index($at)) | .id]}
        | select((.claiming_stories | length) > 1)
      ]
  ' plans/prd.json 2>/dev/null || echo "[]")"

  if ! echo "$conflict_json" | jq -e . >/dev/null 2>&1; then
    conflict_json="[]"
  fi

  ownership_conflicts="$(echo "$conflict_json" | jq -r 'length' 2>/dev/null || echo 0)"
  if [[ -z "$ownership_conflicts" || "$ownership_conflicts" == "null" ]]; then
    ownership_conflicts=0
  fi

  if [[ "$ownership_conflicts" -gt 0 ]]; then
    reasons+=("$ownership_conflicts AT ownership conflict(s) found")

    while IFS= read -r obj; do
      [[ -n "$obj" ]] && ownership_conflict_details+=("$obj")
    done < <(echo "$conflict_json" | jq -c '.[]' 2>/dev/null)

    while IFS= read -r detail; do
      [[ -n "$detail" ]] && ownership_conflict_human+=("$detail")
    done < <(echo "$conflict_json" | jq -r '.[] | "\(.at_id) -> \(.claiming_stories | join(", "))"' 2>/dev/null)
  fi
elif [[ "$premortem_exists" == "true" ]]; then
  # Legacy fallback when jq is unavailable: infer ownership from premortem section 1.
  s1_content="$(sed -n '/^## 1)/,/^## [0-9]/{/^## [0-9]/!p;}' "$PREMORTEM_PATH" 2>/dev/null || true)"
  my_ats=()
  while IFS= read -r at_id; do
    [[ -n "$at_id" ]] && my_ats+=("$at_id")
  done < <(echo "$s1_content" | grep -E '^\|' | grep -oE 'AT-[0-9]+' | sort -u)

  if [[ ${#my_ats[@]} -gt 0 ]]; then
    for at_id in "${my_ats[@]}"; do
      claimants="$story_id"
      for other_pm in reviews/premortems/*_premortem.md; do
        [[ "$other_pm" == "$PREMORTEM_PATH" ]] && continue
        [[ -f "$other_pm" ]] || continue
        other_s1="$(sed -n '/^## 1)/,/^## [0-9]/{/^## [0-9]/!p;}' "$other_pm" 2>/dev/null || true)"
        if echo "$other_s1" | grep -E '^\|' | grep -qF "$at_id" 2>/dev/null; then
          other_story="$(basename "$other_pm" _premortem.md)"
          claimants="${claimants},$other_story"
        fi
      done
      comma_count="$(echo "$claimants" | tr -cd ',' | wc -c | tr -d '[:space:]')"
      if [[ "$comma_count" -gt 0 ]]; then
        ownership_conflicts=$((ownership_conflicts + 1))
        ownership_conflict_details+=("{\"at_id\":\"$at_id\",\"claiming_stories\":[\"${claimants//,/\",\"}\"]}")
        ownership_conflict_human+=("$at_id -> ${claimants//,/, }")
      fi
    done
  fi

  if [[ $ownership_conflicts -gt 0 ]]; then
    reasons+=("$ownership_conflicts AT ownership conflict(s) found")
  fi
fi

# ---- Check sections present (s0-s10) ----
s0=false; s1=false; s2=false; s3=false; s4=false
s5=false; s6=false; s7=false; s8=false; s9=false; s10=false

if [[ "$premortem_exists" == "true" ]]; then
  grep -qE '^## 0\)' "$PREMORTEM_PATH" 2>/dev/null && s0=true
  grep -qE '^## 1\)' "$PREMORTEM_PATH" 2>/dev/null && s1=true
  grep -qE '^## 2\)' "$PREMORTEM_PATH" 2>/dev/null && s2=true
  grep -qE '^## 3\)' "$PREMORTEM_PATH" 2>/dev/null && s3=true
  grep -qE '^## 4\)' "$PREMORTEM_PATH" 2>/dev/null && s4=true
  grep -qE '^## 5\)' "$PREMORTEM_PATH" 2>/dev/null && s5=true
  grep -qE '^## 6\)' "$PREMORTEM_PATH" 2>/dev/null && s6=true
  grep -qE '^## 7\)' "$PREMORTEM_PATH" 2>/dev/null && s7=true
  grep -qE '^## 8\)' "$PREMORTEM_PATH" 2>/dev/null && s8=true
  grep -qE '^## 9\)' "$PREMORTEM_PATH" 2>/dev/null && s9=true
  grep -qE '^## 10\)' "$PREMORTEM_PATH" 2>/dev/null && s10=true

  # Check if any sections are missing
  missing_sections=()
  [[ "$s0"  == "false" ]] && missing_sections+=("s0")
  [[ "$s1"  == "false" ]] && missing_sections+=("s1")
  [[ "$s2"  == "false" ]] && missing_sections+=("s2")
  [[ "$s3"  == "false" ]] && missing_sections+=("s3")
  [[ "$s4"  == "false" ]] && missing_sections+=("s4")
  [[ "$s5"  == "false" ]] && missing_sections+=("s5")
  [[ "$s6"  == "false" ]] && missing_sections+=("s6")
  [[ "$s7"  == "false" ]] && missing_sections+=("s7")
  [[ "$s8"  == "false" ]] && missing_sections+=("s8")
  [[ "$s9"  == "false" ]] && missing_sections+=("s9")
  [[ "$s10" == "false" ]] && missing_sections+=("s10")

  if [[ ${#missing_sections[@]} -gt 0 ]]; then
    reasons+=("missing sections: ${missing_sections[*]}")
  fi
fi

# ---- Check 6: Required context files exist ----
context_files_ok=true
if [[ ! -f "specs/CONTRACT.md" ]]; then
  context_files_ok=false
  reasons+=("required context file missing: specs/CONTRACT.md")
fi
if [[ ! -f "plans/prd.json" ]]; then
  context_files_ok=false
  reasons+=("required context file missing: plans/prd.json")
fi
# Check story exists in prd.json
if [[ -f "plans/prd.json" ]] && command -v jq >/dev/null 2>&1; then
  prd_entry="$(jq -e --arg sid "$story_id" '.items[] | select(.id == $sid)' plans/prd.json 2>/dev/null || true)"
  if [[ -z "$prd_entry" ]]; then
    context_files_ok=false
    reasons+=("story $story_id not found in plans/prd.json")
  else
    # Check scope.touch paths exist (files or directories; globs validated by prd_lint)
    while IFS= read -r touch_file; do
      if [[ -n "$touch_file" && ! -e "$touch_file" ]]; then
        context_files_ok=false
        reasons+=("scope.touch path missing: $touch_file")
      fi
    done < <(echo "$prd_entry" | jq -r '.scope.touch[]? // empty' 2>/dev/null)
  fi
fi

# ---- Determine ready status ----
ready=true
if [[ ${#reasons[@]} -gt 0 ]]; then
  ready=false
fi

# ---- Output ----
head_commit="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$json_mode" == "true" ]]; then
  # Build conflict details JSON array (structured objects)
  conflict_json="[]"
  if [[ ${#ownership_conflict_details[@]} -gt 0 ]]; then
    # Each entry is already a JSON object string from the detection loop
    conflict_json="[$(IFS=','; echo "${ownership_conflict_details[*]}")]"
    # Validate via jq if available
    if command -v jq >/dev/null 2>&1; then
      conflict_json="$(echo "$conflict_json" | jq '.')"
    fi
  fi

  # Build reasons JSON array
  reasons_json="[]"
  if [[ ${#reasons[@]} -gt 0 ]]; then
    if command -v jq >/dev/null 2>&1; then
      reasons_json="$(printf '%s\n' "${reasons[@]}" | jq -R . | jq -s .)"
    else
      reasons_json="["
      first=true
      for reason in "${reasons[@]}"; do
        if [[ "$first" == "true" ]]; then
          first=false
        else
          reasons_json+=","
        fi
        escaped="$(echo "$reason" | sed 's/"/\\"/g')"
        reasons_json+="\"$escaped\""
      done
      reasons_json+="]"
    fi
  fi

  if command -v jq >/dev/null 2>&1; then
    jq -n \
      --arg schema_version "premortem_ready.v1" \
      --arg head_commit "$head_commit" \
      --arg created_at "$created_at" \
      --arg story_id "$story_id" \
      --argjson ready "$ready" \
      --argjson premortem_exists "$premortem_exists" \
      --arg stoplight "$stoplight" \
      --argjson stoplight_is_red "$stoplight_is_red" \
      --argjson yellow_gaps_ok "$yellow_gaps_ok" \
      --argjson context_files_ok "$context_files_ok" \
      --argjson ownership_conflicts "$ownership_conflicts" \
      --argjson ownership_conflict_details "$conflict_json" \
      --argjson s0 "$s0" \
      --argjson s1 "$s1" \
      --argjson s2 "$s2" \
      --argjson s3 "$s3" \
      --argjson s4 "$s4" \
      --argjson s5 "$s5" \
      --argjson s6 "$s6" \
      --argjson s7 "$s7" \
      --argjson s8 "$s8" \
      --argjson s9 "$s9" \
      --argjson s10 "$s10" \
      --argjson premortem_gate_exit_code "$premortem_gate_exit_code" \
      --argjson reasons "$reasons_json" \
      '{
        schema_version: $schema_version,
        head_commit: $head_commit,
        created_at: $created_at,
        story_id: $story_id,
        ready: $ready,
        premortem_exists: $premortem_exists,
        stoplight: $stoplight,
        stoplight_is_red: $stoplight_is_red,
        yellow_gaps_ok: $yellow_gaps_ok,
        context_files_ok: $context_files_ok,
        ownership_conflicts: $ownership_conflicts,
        ownership_conflict_details: $ownership_conflict_details,
        sections_present: {
          s0: $s0, s1: $s1, s2: $s2, s3: $s3, s4: $s4,
          s5: $s5, s6: $s6, s7: $s7, s8: $s8, s9: $s9, s10: $s10
        },
        premortem_gate_exit_code: $premortem_gate_exit_code,
        reasons: $reasons
      }'
  else
    # Fallback: printf-based JSON (no jq available)
    printf '{\n'
    printf '  "schema_version": "premortem_ready.v1",\n'
    printf '  "head_commit": "%s",\n' "$head_commit"
    printf '  "created_at": "%s",\n' "$created_at"
    printf '  "story_id": "%s",\n' "$story_id"
    printf '  "ready": %s,\n' "$ready"
    printf '  "premortem_exists": %s,\n' "$premortem_exists"
    printf '  "stoplight": "%s",\n' "$stoplight"
    printf '  "stoplight_is_red": %s,\n' "$stoplight_is_red"
    printf '  "yellow_gaps_ok": %s,\n' "$yellow_gaps_ok"
    printf '  "context_files_ok": %s,\n' "$context_files_ok"
    printf '  "ownership_conflicts": %d,\n' "$ownership_conflicts"
    printf '  "ownership_conflict_details": %s,\n' "$conflict_json"
    printf '  "sections_present": {\n'
    printf '    "s0": %s, "s1": %s, "s2": %s, "s3": %s, "s4": %s,\n' \
      "$s0" "$s1" "$s2" "$s3" "$s4"
    printf '    "s5": %s, "s6": %s, "s7": %s, "s8": %s, "s9": %s, "s10": %s\n' \
      "$s5" "$s6" "$s7" "$s8" "$s9" "$s10"
    printf '  },\n'
    printf '  "premortem_gate_exit_code": %d,\n' "$premortem_gate_exit_code"
    printf '  "reasons": %s\n' "$reasons_json"
    printf '}\n'
  fi
fi

# ---- Human-readable output to stderr ----
if [[ "$ready" == "true" ]]; then
  echo "OK: premortem ready for $story_id (STOPLIGHT=$stoplight)" >&2
  exit 0
else
  echo "FAIL: premortem NOT ready for $story_id" >&2
  for reason in "${reasons[@]}"; do
    echo "  - $reason" >&2
  done
  if [[ ${#ownership_conflict_human[@]} -gt 0 ]]; then
    echo "  - ownership conflict details:" >&2
    for detail in "${ownership_conflict_human[@]}"; do
      echo "      * $detail" >&2
    done
  fi
  exit 1
fi
