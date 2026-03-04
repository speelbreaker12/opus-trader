#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/recon_operator_run.sh [--story STORY_ID] [--slice N|SN] [--step STEP] [--mode A|B] [--run-root PATH]

Behavior:
  - If --story is omitted, prefer active HANDOFF story, else choose first eligible unreconciled story.
  - Enforces eligibility: passes=true, no 08_pass receipt, no active conflicting run.
  - In Mode B, requires plans/premortem_ready.sh STORY_ID before running wf_step.
  - Records operator trace artifacts with plans/recon_trace.sh.

Options:
  --story STORY_ID   Explicit story (e.g., S2-003)
  --slice N|SN       Optional slice filter/override (e.g., 2 or S2)
  --step STEP        Default: preflight
  --mode A|B         Default: B
  --run-root PATH    Optional trace root (default: .wf/trace/<STORY>/<TRACE_ID>)
  -h|--help          Show this help
USAGE
}

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repository" >&2
  exit 2
}
cd "$ROOT"

TRACE_SCRIPT="${RECON_OPERATOR_TRACE_CMD:-plans/recon_trace.sh}"
PREMORTEM_READY_SCRIPT="${RECON_OPERATOR_PREMORTEM_READY_CMD:-plans/premortem_ready.sh}"
WF_STEP_SCRIPT="${RECON_OPERATOR_WF_STEP_CMD:-plans/wf_step.sh}"
SCOREBOARD_SCRIPT="${RECON_OPERATOR_SCOREBOARD_CMD:-plans/recon_scoreboard.sh}"
HANDOFF_TEMPLATE="${RECON_OPERATOR_HANDOFF_TEMPLATE:-reviews/reconciliations/RECON_HANDOFF_TEMPLATE.md}"
PRD_FILE="${RECON_OPERATOR_PRD_FILE:-plans/prd.json}"

story_id=""
slice_num=""
step_name="preflight"
mode="B"
run_root=""
declare -a no_eligibility_diagnostics=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --story) story_id="${2:?missing story}"; shift 2 ;;
    --slice) slice_num="${2:?missing slice}"; shift 2 ;;
    --step) step_name="${2:?missing step}"; shift 2 ;;
    --mode) mode="${2:?missing mode}"; shift 2 ;;
    --run-root) run_root="${2:?missing run root}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; usage >&2; exit 2 ;;
  esac
done

normalize_slice() {
  local raw="$1"
  if [[ "$raw" =~ ^[Ss]?([0-9]+)$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

slice_from_story() {
  local sid="$1"
  if [[ "$sid" =~ ^[Ss]([0-9]+)-[0-9]+$ ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  return 1
}

validate_step() {
  case "$1" in
    preflight|implement|self_review|cycle1|fix|cycle2|resolution|verify_full|pass) return 0 ;;
    *) return 1 ;;
  esac
}

step_index() {
  case "$1" in
    preflight) echo 0 ;;
    implement) echo 1 ;;
    self_review) echo 2 ;;
    cycle1) echo 3 ;;
    fix) echo 4 ;;
    cycle2) echo 5 ;;
    resolution) echo 6 ;;
    verify_full) echo 7 ;;
    pass) echo 8 ;;
    *) return 1 ;;
  esac
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

list_prd_rows() {
  python3 - "$PRD_FILE" <<'PY'
import json
import re
import sys

path = sys.argv[1]
with open(path, "r", encoding="utf-8") as f:
    data = json.load(f)

entries = {}

def norm_slice(value):
    if isinstance(value, int):
        return str(value)
    if isinstance(value, str):
        m = re.match(r"^[Ss]?(\d+)$", value.strip())
        if m:
            return m.group(1)
    return ""

items = data.get("items")
if isinstance(items, list):
    for item in items:
        if not isinstance(item, dict):
            continue
        sid = item.get("id")
        if not isinstance(sid, str) or not sid:
            continue
        entries[sid] = (norm_slice(item.get("slice")), bool(item.get("passes") is True))

stories = data.get("stories")
if isinstance(stories, dict):
    for sid, payload in stories.items():
        if sid in entries:
            continue
        if not isinstance(sid, str) or not isinstance(payload, dict):
            continue
        entries[sid] = (norm_slice(payload.get("slice")), bool(payload.get("passes") is True))

def sort_key(sid):
    m = re.match(r"^S(\d+)-(\d+)$", sid, re.IGNORECASE)
    if not m:
        return (10**9, 10**9, sid)
    return (int(m.group(1)), int(m.group(2)), sid)

for sid in sorted(entries, key=sort_key):
    sl, passes = entries[sid]
    print(f"{sid}\t{sl}\t{'1' if passes else '0'}")
PY
}

find_active_handoff() {
  ls reviews/reconciliations/*/HANDOFF.md 2>/dev/null | LC_ALL=C sort | head -n 1 || true
}

story_from_handoff() {
  local handoff="$1"
  grep -Eo 'S[0-9]+-[0-9]+' "$handoff" 2>/dev/null | head -n 1 || true
}

lock_file_for_story() {
  local sid="$1"
  printf '.wf/trace/%s/ACTIVE_RUN\n' "$sid"
}

parse_lock_entry() {
  local raw="$1"
  local active_root="$raw"
  local active_pid=""
  if [[ "$raw" == *$'\t'* ]]; then
    active_root="${raw%%$'\t'*}"
    active_pid="${raw#*$'\t'}"
  fi
  printf '%s\t%s\n' "$active_root" "$active_pid"
}

pid_is_live() {
  local pid="$1"
  [[ "$pid" =~ ^[0-9]+$ ]] || return 1
  kill -0 "$pid" >/dev/null 2>&1
}

has_active_conflict() {
  local sid="$1"
  local desired_root="${2:-}"
  local lock_file
  local lock_raw
  local active_root
  local active_pid
  lock_file="$(lock_file_for_story "$sid")"
  if [[ ! -f "$lock_file" ]]; then
    return 1
  fi
  lock_raw="$(cat "$lock_file" 2>/dev/null || true)"
  IFS=$'\t' read -r active_root active_pid <<< "$(parse_lock_entry "$lock_raw")"
  if [[ -z "$active_root" || ! -d "$active_root" ]]; then
    rm -f "$lock_file"
    return 1
  fi
  if [[ -n "$active_pid" ]] && ! pid_is_live "$active_pid"; then
    rm -f "$lock_file"
    return 1
  fi
  if [[ -n "$desired_root" && "$active_root" == "$desired_root" ]]; then
    return 1
  fi
  if [[ -n "$active_pid" && "$active_pid" == "$$" ]]; then
    return 1
  fi
  return 0
}

current_changed_files() {
  {
    git diff --name-only 2>/dev/null || true
    git diff --cached --name-only 2>/dev/null || true
    git ls-files --others --exclude-standard 2>/dev/null || true
  } | awk 'NF' | LC_ALL=C sort -u
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi
  return 1
}

path_fingerprint() {
  local path="$1"
  local digest=""
  if [[ ! -e "$path" ]]; then
    echo "__MISSING__"
    return 0
  fi
  if [[ -d "$path" ]]; then
    echo "__DIR__"
    return 0
  fi
  digest="$(sha256_file "$path" 2>/dev/null || true)"
  if [[ -n "$digest" ]]; then
    echo "$digest"
    return 0
  fi
  echo "__UNHASHABLE__"
  return 0
}

current_production_fingerprints() {
  local changed_path
  while IFS= read -r changed_path; do
    [[ -n "$changed_path" ]] || continue
    if path_is_production_code "$changed_path"; then
      printf '%s\t%s\n' "$changed_path" "$(path_fingerprint "$changed_path")"
    fi
  done < <(current_changed_files)
}

path_is_production_code() {
  local path="$1"
  case "$path" in
    crates/*)
      case "$path" in
        */tests/*) return 1 ;;
      esac
      return 0
      ;;
    src/*|python/*|Cargo.toml|Cargo.lock)
      return 0
      ;;
  esac
  return 1
}

story_is_passed_in_prd() {
  local sid="$1"
  local row
  local passes_val
  row="$(list_prd_rows | awk -F '\t' -v sid="$sid" '$1==sid {print; exit}')"
  [[ -n "$row" ]] || return 1
  passes_val="$(printf '%s\n' "$row" | awk -F '\t' '{print $3}')"
  [[ "$passes_val" == "1" ]]
}

story_slice_in_prd() {
  local sid="$1"
  list_prd_rows | awk -F '\t' -v sid="$sid" '$1==sid {print $2; exit}'
}

premortem_ready() {
  local sid="$1"
  local out_file="$2"
  if [[ ! -x "$PREMORTEM_READY_SCRIPT" && ! -f "$PREMORTEM_READY_SCRIPT" ]]; then
    echo "missing premortem_ready gate script: $PREMORTEM_READY_SCRIPT" > "$out_file"
    return 3
  fi
  if [[ -x "$PREMORTEM_READY_SCRIPT" ]]; then
    "$PREMORTEM_READY_SCRIPT" "$sid" >"$out_file" 2>&1
  else
    bash "$PREMORTEM_READY_SCRIPT" "$sid" >"$out_file" 2>&1
  fi
}

is_story_eligible() {
  local sid="$1"
  local sl="$2"
  local reason_file="$3"

  : > "$reason_file"
  if [[ -z "$sl" ]]; then
    echo "missing slice in PRD" > "$reason_file"
    return 1
  fi
  if ! story_is_passed_in_prd "$sid"; then
    echo "passes!=true in PRD" > "$reason_file"
    return 1
  fi
  if [[ -f ".wf/receipts/$sid/08_pass.json" ]]; then
    echo "final pass receipt already exists" > "$reason_file"
    return 1
  fi
  if has_active_conflict "$sid"; then
    echo "active conflicting run exists for story" > "$reason_file"
    return 1
  fi
  if [[ "$mode" == "B" ]]; then
    if ! premortem_ready "$sid" "$reason_file"; then
      if [[ ! -s "$reason_file" ]]; then
        echo "premortem_ready gate failed" > "$reason_file"
      fi
      return 1
    fi
  fi
  return 0
}

first_nonempty_line() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    return 0
  fi
  awk 'NF {print; exit}' "$file" 2>/dev/null || true
}

record_no_eligibility_reason() {
  local sid="$1"
  local reason_file="$2"
  local reason
  reason="$(first_nonempty_line "$reason_file")"
  if [[ -z "$reason" ]]; then
    reason="unknown ineligibility reason"
  fi
  no_eligibility_diagnostics+=("$sid: $reason")
}

classify_failure_category() {
  local log_file="$1"
  local lowered=""
  if [[ -f "$log_file" ]]; then
    lowered="$(tr '[:upper:]' '[:lower:]' < "$log_file" 2>/dev/null || true)"
  fi

  if [[ "$lowered" == *"ownership conflict"* || "$lowered" == *"not ready"* || "$lowered" == *"stoplight"* || "$lowered" == *"deferred"* ]]; then
    echo "AMBIGUITY"
    return 0
  fi
  if [[ "$lowered" == *"missing"* || "$lowered" == *"not found"* || "$lowered" == *"no such file"* ]]; then
    echo "SEARCH"
    return 0
  fi
  if [[ "$lowered" == *"hallucinat"* ]]; then
    echo "HALLUCINATION"
    return 0
  fi
  if [[ "$lowered" == *"context loss"* || "$lowered" == *"lost context"* ]]; then
    echo "CONTEXT_LOSS"
    return 0
  fi
  if [[ "$lowered" == *"non_write_step_prod_edit_blocked"* || "$lowered" == *"forbidden production-code changes"* ]]; then
    echo "CEREMONY"
    return 0
  fi
  echo "TOOLING"
}

if [[ -n "$slice_num" ]]; then
  slice_num="$(normalize_slice "$slice_num")" || {
    echo "ERROR: invalid --slice '$slice_num' (expected N or SN)" >&2
    exit 2
  }
fi

mode="$(printf '%s' "$mode" | tr '[:lower:]' '[:upper:]')"
if [[ "$mode" != "A" && "$mode" != "B" ]]; then
  echo "ERROR: --mode must be A or B" >&2
  exit 2
fi

validate_step "$step_name" || {
  echo "ERROR: invalid --step '$step_name'" >&2
  exit 2
}

if [[ ! -f "$PRD_FILE" ]]; then
  echo "ERROR: PRD not found: $PRD_FILE" >&2
  exit 2
fi

if [[ -z "$story_id" ]]; then
  active_handoff="$(find_active_handoff)"
  if [[ -n "$active_handoff" ]]; then
    handoff_slice="$(basename "$(dirname "$active_handoff")")"
    if [[ -z "$slice_num" ]]; then
      slice_num="$(normalize_slice "$handoff_slice" 2>/dev/null || true)"
    fi
    handoff_story="$(story_from_handoff "$active_handoff")"
    if [[ -n "$handoff_story" ]]; then
      reason_tmp="$(mktemp)"
      if [[ -z "$slice_num" || "$slice_num" == "$(slice_from_story "$handoff_story" 2>/dev/null || true)" ]]; then
        handoff_story_slice="$(story_slice_in_prd "$handoff_story")"
        if [[ -n "$handoff_story_slice" ]] && is_story_eligible "$handoff_story" "$handoff_story_slice" "$reason_tmp"; then
          story_id="$handoff_story"
          slice_num="$handoff_story_slice"
        else
          record_no_eligibility_reason "$handoff_story" "$reason_tmp"
        fi
      fi
      rm -f "$reason_tmp"
    fi
  fi
fi

if [[ -z "$story_id" ]]; then
  reason_tmp="$(mktemp)"
  while IFS=$'\t' read -r sid sl passes; do
    [[ -n "$sid" ]] || continue
    [[ "$passes" == "1" ]] || continue
    if [[ -n "$slice_num" && "$sl" != "$slice_num" ]]; then
      continue
    fi
    if is_story_eligible "$sid" "$sl" "$reason_tmp"; then
      story_id="$sid"
      slice_num="$sl"
      break
    else
      record_no_eligibility_reason "$sid" "$reason_tmp"
    fi
  done < <(list_prd_rows)
  rm -f "$reason_tmp"
fi

if [[ -z "$story_id" ]]; then
  echo "ERROR: no eligible unreconciled story found" >&2
  if [[ -n "$slice_num" ]]; then
    echo "Eligibility diagnostics (slice=$slice_num):" >&2
  else
    echo "Eligibility diagnostics:" >&2
  fi
  if [[ "${#no_eligibility_diagnostics[@]}" -gt 0 ]]; then
    for line in "${no_eligibility_diagnostics[@]}"; do
      echo "  - $line" >&2
    done
  else
    if [[ -n "$slice_num" ]]; then
      echo "  - no matching pass=true candidates for slice $slice_num" >&2
    else
      echo "  - no matching pass=true candidates in PRD" >&2
    fi
  fi
  exit 1
fi

if [[ -z "$slice_num" ]]; then
  slice_num="$(story_slice_in_prd "$story_id")"
fi
if [[ -z "$slice_num" ]]; then
  slice_num="$(slice_from_story "$story_id" 2>/dev/null || true)"
fi
if [[ -z "$slice_num" ]]; then
  echo "ERROR: unable to determine slice for story $story_id" >&2
  exit 1
fi

if ! story_is_passed_in_prd "$story_id"; then
  echo "ERROR: story $story_id is not passes=true in PRD" >&2
  exit 1
fi

if [[ -f ".wf/receipts/$story_id/08_pass.json" ]]; then
  echo "ERROR: story $story_id already has final pass receipt (.wf/receipts/$story_id/08_pass.json)" >&2
  exit 1
fi

slice_token="S${slice_num}"
trace_id="$(date -u +%Y%m%dT%H%M%SZ)-${story_id}"
if [[ -z "$run_root" ]]; then
  run_root=".wf/trace/$story_id/$trace_id"
fi

lock_file="$(lock_file_for_story "$story_id")"
mkdir -p "$(dirname "$lock_file")"
if has_active_conflict "$story_id" "$run_root"; then
  lock_raw="$(cat "$lock_file" 2>/dev/null || true)"
  IFS=$'\t' read -r active_root active_pid <<< "$(parse_lock_entry "$lock_raw")"
  if [[ -n "${active_pid:-}" ]]; then
    echo "ERROR: active conflicting run exists for $story_id: $active_root (pid=$active_pid)" >&2
  else
    echo "ERROR: active conflicting run exists for $story_id: $active_root" >&2
  fi
  exit 1
fi

printf '%s\t%s\n' "$run_root" "$$" > "$lock_file"
lock_owned=1
changed_before_fingerprints_file=""
changed_after_fingerprints_file=""
changed_delta_file=""
cleanup() {
  local f
  for f in "${changed_before_fingerprints_file:-}" "${changed_after_fingerprints_file:-}" "${changed_delta_file:-}"; do
    [[ -n "$f" ]] || continue
    rm -f "$f"
  done
  if [[ "${lock_owned:-0}" -eq 1 && -f "$lock_file" ]]; then
    local current_lock
    local current_root
    local current_pid
    current_lock="$(cat "$lock_file" 2>/dev/null || true)"
    IFS=$'\t' read -r current_root current_pid <<< "$(parse_lock_entry "$current_lock")"
    if [[ "$current_root" == "$run_root" && ( -z "$current_pid" || "$current_pid" == "$$" ) ]]; then
      rm -f "$lock_file"
    fi
  fi
}
trap cleanup EXIT

if [[ ! -f "$TRACE_SCRIPT" ]]; then
  echo "ERROR: trace script missing: $TRACE_SCRIPT" >&2
  exit 2
fi
if [[ ! -x "$TRACE_SCRIPT" ]]; then
  chmod +x "$TRACE_SCRIPT" 2>/dev/null || true
fi

if [[ ! -f "$run_root/RUN_CARD.md" ]]; then
  "$TRACE_SCRIPT" init "$story_id" "$slice_token" --run-root "$run_root" >/dev/null
fi

handoff_path="reviews/reconciliations/$slice_token/HANDOFF.md"
mkdir -p "$(dirname "$handoff_path")"
if [[ ! -f "$handoff_path" ]]; then
  if [[ -f "$HANDOFF_TEMPLATE" ]]; then
    cp "$HANDOFF_TEMPLATE" "$handoff_path"
  else
    printf '# Reconciliation Handoff — %s\n' "$slice_token" > "$handoff_path"
  fi
fi

refresh_scoreboard() {
  if [[ ! -x "$SCOREBOARD_SCRIPT" && ! -f "$SCOREBOARD_SCRIPT" ]]; then
    echo "WARN: scoreboard script missing: $SCOREBOARD_SCRIPT" >&2
    return 1
  fi
  if [[ -x "$SCOREBOARD_SCRIPT" ]]; then
    "$SCOREBOARD_SCRIPT" "$slice_num" >/dev/null 2>&1 || {
      echo "WARN: scoreboard refresh failed for $slice_token" >&2
      return 1
    }
  else
    bash "$SCOREBOARD_SCRIPT" "$slice_num" >/dev/null 2>&1 || {
      echo "WARN: scoreboard refresh failed for $slice_token" >&2
      return 1
    }
  fi
}

update_handoff_hook() {
  local status="$1"
  local log_path="$2"
  local receipt_path="$3"
  local ts
  ts="$(iso_now)"
  {
    echo ""
    echo "## Operator Hook Update ($ts)"
    echo "- Story: $story_id"
    echo "- Step: $step_name"
    echo "- Status: $status"
    echo "- Run root: $run_root"
    echo "- Log: $log_path"
    echo "- Receipt: $receipt_path"
  } >> "$handoff_path"
}

refresh_scoreboard || true

attempt_no="$(find "$run_root/logs" -maxdepth 1 -type f -name "${step_name}_attempt*.log" 2>/dev/null | wc -l | tr -d '[:space:]')"
attempt_no="$((attempt_no + 1))"
mkdir -p "$run_root/logs" "$run_root/steps/$step_name" "$run_root/receipts"
log_path="$run_root/logs/${step_name}_attempt${attempt_no}.log"

status="PASS"
step_kind="execution"
step_rc=0
head_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
start_at="$(iso_now)"
commands_run=()
premortem_out="$run_root/logs/${step_name}_attempt${attempt_no}.premortem.log"
changed_before_fingerprints_file="$(mktemp)"
changed_after_fingerprints_file="$(mktemp)"
changed_delta_file="$(mktemp)"
current_production_fingerprints > "$changed_before_fingerprints_file"

if [[ "$mode" == "B" ]]; then
  commands_run+=("$PREMORTEM_READY_SCRIPT $story_id")
  if ! premortem_ready "$story_id" "$premortem_out"; then
    status="BLOCKED"
    step_kind="gate"
    step_rc=1
    {
      echo "PREMORTEM_READY_FAILED"
      cat "$premortem_out"
    } > "$log_path"
  fi
fi

wf_receipt_expected=".wf/receipts/$story_id/$(printf '%02d_%s.json' "$(step_index "$step_name")" "$step_name")"
if [[ "$status" == "PASS" ]]; then
  commands_run+=("WF_RECON_MODE=1 $WF_STEP_SCRIPT $story_id $step_name")
  set +e
  WF_RECON_MODE=1 "$WF_STEP_SCRIPT" "$story_id" "$step_name" >"$log_path" 2>&1
  step_rc=$?
  set -e
  if [[ "$step_rc" -ne 0 ]]; then
    status="BLOCKED"
  fi
fi

if [[ "$step_name" != "implement" && "$step_name" != "fix" ]]; then
  guard_prior_status="$status"
  guard_prior_rc="$step_rc"
  illegal_paths=()
  current_production_fingerprints > "$changed_after_fingerprints_file"
  awk -F '\t' '
    NR==FNR { before[$1]=$2; before_seen[$1]=1; next }
    { after[$1]=$2; after_seen[$1]=1 }
    END {
      for (p in after_seen) {
        if (!(p in before_seen) || before[p] != after[p]) {
          print p
        }
      }
      for (p in before_seen) {
        if (!(p in after_seen)) {
          print p
        }
      }
    }
  ' "$changed_before_fingerprints_file" "$changed_after_fingerprints_file" | LC_ALL=C sort -u > "$changed_delta_file"
  while IFS= read -r changed_path; do
    [[ -n "$changed_path" ]] || continue
    if path_is_production_code "$changed_path"; then
      illegal_paths+=("$changed_path")
    fi
  done < "$changed_delta_file"

  if [[ "${#illegal_paths[@]}" -gt 0 ]]; then
    quarantined_wf_receipt=""
    if [[ -f "$wf_receipt_expected" ]]; then
      quarantined_wf_receipt="$run_root/receipts/${step_name}_attempt${attempt_no}.wf_receipt_pre_guard.json"
      cp "$wf_receipt_expected" "$quarantined_wf_receipt"
      rm -f "$wf_receipt_expected"
    fi
    status="BLOCKED"
    step_kind="gate"
    if [[ "$guard_prior_status" == "PASS" ]]; then
      step_rc=7
    fi
    {
      echo ""
      echo "NON_WRITE_STEP_PROD_EDIT_BLOCKED"
      echo "Step '$step_name' is non-write. Production code changes are only allowed in implement/fix."
      if [[ "$guard_prior_status" != "PASS" ]]; then
        echo "Prior step status was $guard_prior_status (exit=$guard_prior_rc); non-write production edit guard also triggered."
      fi
      if [[ -n "$quarantined_wf_receipt" ]]; then
        echo "Removed optimistic workflow receipt to keep receipt chain fail-closed:"
        echo "  - removed: $wf_receipt_expected"
        echo "  - quarantined copy: $quarantined_wf_receipt"
      fi
      echo "Forbidden production-code changes:"
      for p in "${illegal_paths[@]}"; do
        echo "  - $p"
      done
    } >> "$log_path"
  fi
fi
end_at="$(iso_now)"

wf_receipt_path="$wf_receipt_expected"
if [[ ! -f "$wf_receipt_path" ]]; then
  wf_receipt_path="$run_root/receipts/${step_name}_attempt${attempt_no}.wf_missing.json"
  jq -n \
    --arg story_id "$story_id" \
    --arg step_name "$step_name" \
    --arg head_sha "$head_commit" \
    --arg timestamp_utc "$end_at" \
    --arg status "$status" \
    --arg log_path "$log_path" \
    --argjson exit_code "$step_rc" \
    '{
      story_id: $story_id,
      step_name: $step_name,
      head_sha: $head_sha,
      timestamp_utc: $timestamp_utc,
      status: $status,
      exit_code: $exit_code,
      synthetic_missing_wf_receipt: true,
      log_path: $log_path
    }' > "$wf_receipt_path"
fi

files_json='["none"]'
if [[ -f "$handoff_path" ]]; then
  files_json="$(jq -cn --arg handoff "$handoff_path" '[$handoff]')"
fi

commands_json="$(printf '%s\n' "${commands_run[@]}" | jq -R . | jq -s .)"
if [[ -z "$commands_json" || "$commands_json" == "[]" ]]; then
  commands_json='["none"]'
fi

strongest_evidence="step log at $log_path"
if [[ -f "$wf_receipt_expected" ]]; then
  strongest_evidence="workflow receipt at $wf_receipt_expected"
fi

not_done="none"
if [[ "$status" != "PASS" ]]; then
  not_done="did not complete step $step_name due to blocker (exit=$step_rc)"
fi

step_report="$run_root/steps/$step_name/attempt_${attempt_no}.step_report.json"
jq -n \
  --arg schema_version "recon_step_report.v1" \
  --arg head_commit "$head_commit" \
  --arg created_at "$end_at" \
  --arg story_id "$story_id" \
  --arg step_name "$step_name" \
  --arg status "$status" \
  --arg strongest_evidence "$strongest_evidence" \
  --arg not_done "$not_done" \
  --argjson step_index "$(step_index "$step_name")" \
  --argjson exit_code "$step_rc" \
  --argjson commands_run "$commands_json" \
  --argjson files_changed "$files_json" \
  --argjson artifacts "$(jq -cn --arg log "$log_path" --arg receipt "$wf_receipt_path" '[$log, $receipt]')" \
  '{
    schema_version: $schema_version,
    head_commit: $head_commit,
    created_at: $created_at,
    story_id: $story_id,
    step_name: $step_name,
    step_index: $step_index,
    status: $status,
    exit_code: $exit_code,
    commands_run: $commands_run,
    files_changed: $files_changed,
    strongest_evidence: $strongest_evidence,
    not_done: $not_done,
    artifacts: $artifacts
  }' > "$step_report"

"$TRACE_SCRIPT" record-step "$story_id" "$step_name" \
  --run-root "$run_root" \
  --start "$start_at" \
  --end "$end_at" \
  --status "$status" \
  --attempt "$attempt_no" \
  --kind "$step_kind" \
  --retries 0 \
  --log-path "$log_path" \
  --wf-receipt "$wf_receipt_path" \
  --step-report "$step_report" \
  --notes "operator-run mode=$mode" >/dev/null

if [[ "$status" != "PASS" ]]; then
  failure_category="$(classify_failure_category "$log_path")"
  "$TRACE_SCRIPT" log-failure "$story_id" "$step_name" \
    --run-root "$run_root" \
    --type "$failure_category" \
    --evidence "$log_path" \
    --action "NO-GO: resolve blocker and rerun" >/dev/null
fi

update_handoff_hook "$status" "$log_path" "$wf_receipt_path"
refresh_scoreboard || true

echo "recon_operator_run: story=$story_id slice=$slice_token step=$step_name status=$status run_root=$run_root"
if [[ "$status" == "PASS" ]]; then
  exit 0
fi
exit 1
