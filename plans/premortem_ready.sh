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
#   4. No AT ownership conflicts (no AT claimed as primary by 2+ stories)
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

# ---- Check 1: premortem file exists ----
premortem_exists=false
if [[ -f "$PREMORTEM_PATH" ]]; then
  premortem_exists=true
else
  reasons+=("premortem file not found: $PREMORTEM_PATH")
fi

# ---- Check 2: premortem_gate.sh passes ----
premortem_gate_exit_code=-1
if [[ -x "plans/premortem_gate.sh" ]]; then
  if plans/premortem_gate.sh "$story_id" >/dev/null 2>&1; then
    premortem_gate_exit_code=0
  else
    premortem_gate_exit_code=$?
    reasons+=("premortem_gate.sh failed with exit code $premortem_gate_exit_code")
  fi
elif [[ -f "plans/premortem_gate.sh" ]]; then
  # File exists but not executable — try running via bash
  if bash plans/premortem_gate.sh "$story_id" >/dev/null 2>&1; then
    premortem_gate_exit_code=0
  else
    premortem_gate_exit_code=$?
    reasons+=("premortem_gate.sh failed with exit code $premortem_gate_exit_code")
  fi
else
  # Script doesn't exist — graceful degradation
  premortem_gate_exit_code=-1
  echo "WARN: plans/premortem_gate.sh not found, skipping gate check" >&2
fi

# ---- Check 3: STOPLIGHT != RED ----
stoplight="UNKNOWN"
stoplight_is_red=false
if [[ "$premortem_exists" == "true" ]]; then
  stoplight_match="$(grep -oE '\*\*STOPLIGHT\*\*:\s*(GREEN|YELLOW|RED)' "$PREMORTEM_PATH" | head -1 || true)"
  if [[ -n "$stoplight_match" ]]; then
    stoplight="$(echo "$stoplight_match" | grep -oE '(GREEN|YELLOW|RED)' | head -1)"
    if [[ "$stoplight" == "RED" ]]; then
      stoplight_is_red=true
      reasons+=("STOPLIGHT is RED")
    fi
  else
    stoplight="MISSING"
    reasons+=("STOPLIGHT line not found in premortem")
  fi
fi

# ---- Check 4: AT ownership conflicts ----
ownership_conflicts=0
ownership_conflict_details=()
if [[ "$premortem_exists" == "true" ]]; then
  # Extract AT-IDs from this story's section 1 table
  # Get content between "## 1)" heading and next "## " heading
  s1_content="$(sed -n '/^## 1)/,/^## [0-9]/{/^## [0-9]/!p;}' "$PREMORTEM_PATH" 2>/dev/null || true)"

  # Extract AT-IDs from table rows (lines starting with |)
  my_ats=()
  while IFS= read -r at_id; do
    [[ -n "$at_id" ]] && my_ats+=("$at_id")
  done < <(echo "$s1_content" | grep -E '^\|' | grep -oE 'AT-[0-9]+' | sort -u)

  # Check each AT against other premortems
  if [[ ${#my_ats[@]} -gt 0 ]]; then
    for at_id in "${my_ats[@]}"; do
      # Search other premortems (not this story's)
      for other_pm in reviews/premortems/*_premortem.md; do
        [[ "$other_pm" == "$PREMORTEM_PATH" ]] && continue
        [[ -f "$other_pm" ]] || continue

        # Extract other story's section 1 content
        other_s1="$(sed -n '/^## 1)/,/^## [0-9]/{/^## [0-9]/!p;}' "$other_pm" 2>/dev/null || true)"

        # Check if this AT appears in the other story's section 1 table rows
        if echo "$other_s1" | grep -E '^\|' | grep -qF "$at_id" 2>/dev/null; then
          other_story="$(basename "$other_pm" _premortem.md)"
          ownership_conflicts=$((ownership_conflicts + 1))
          ownership_conflict_details+=("$at_id claimed by both $story_id and $other_story")
        fi
      done
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

# ---- Determine ready status ----
ready=true
if [[ ${#reasons[@]} -gt 0 ]]; then
  ready=false
fi

# ---- Output ----
head_commit="$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")"
created_at="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

if [[ "$json_mode" == "true" ]]; then
  # Build conflict details JSON array
  conflict_json="[]"
  if [[ ${#ownership_conflict_details[@]} -gt 0 ]]; then
    if command -v jq >/dev/null 2>&1; then
      conflict_json="$(printf '%s\n' "${ownership_conflict_details[@]}" | jq -R . | jq -s .)"
    else
      # Fallback: manual JSON array construction
      conflict_json="["
      first=true
      for detail in "${ownership_conflict_details[@]}"; do
        if [[ "$first" == "true" ]]; then
          first=false
        else
          conflict_json+=","
        fi
        # Escape double quotes in the detail string
        escaped="$(echo "$detail" | sed 's/"/\\"/g')"
        conflict_json+="\"$escaped\""
      done
      conflict_json+="]"
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
  exit 1
fi
