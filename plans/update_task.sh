#!/usr/bin/env bash
set -euo pipefail

# Fix: prevent concurrent state mutation with file locking
LOCK_FILE="${RPH_STATE_FILE:-.ralph/state.json}.lock"
LOCK_DIR="${LOCK_FILE}.d"
mkdir -p "$(dirname "$LOCK_FILE")"
if command -v flock >/dev/null 2>&1; then
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    echo "ERROR: state locked by another process" >&2
    exit 7
  fi
else
  if ! mkdir "$LOCK_DIR" 2>/dev/null; then
    echo "ERROR: state locked by another process" >&2
    exit 7
  fi
  trap 'rmdir "$LOCK_DIR"' EXIT
fi

ID="${1:-}"
STATUS="${2:-}"
PRD_FILE="${PRD_FILE:-plans/prd.json}"
STATE_FILE="${RPH_STATE_FILE:-.ralph/state.json}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq required" >&2; exit 2; }
command -v git >/dev/null 2>&1 || { echo "ERROR: git required" >&2; exit 2; }
[[ -n "$ID" && -n "$STATUS" ]] || { echo "Usage: $0 <task_id> <true|false>" >&2; exit 1; }

if [[ "$STATUS" != "true" && "$STATUS" != "false" ]]; then
  echo "ERROR: status must be true or false" >&2
  exit 1
fi

if [[ "$STATUS" == "true" ]]; then
  echo "ERROR: passes=true updates must use ./plans/prd_set_pass.sh with verify artifacts" >&2
  exit 4
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: not inside a git repository" >&2
  exit 2
fi
cd "$REPO_ROOT"

[[ -f "$PRD_FILE" ]] || { echo "ERROR: missing $PRD_FILE" >&2; exit 1; }

sha256_file() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    echo ""
    return 0
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
  else
    shasum -a 256 "$file" | awk '{print $1}'
  fi
}

extract_verify_log_sha() {
  local log="$1"
  local line=""
  if [[ -f "$log" ]]; then
    line="$(grep -m1 '^VERIFY_SH_SHA=' "$log" || true)"
  fi
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi
  echo "${line#VERIFY_SH_SHA=}"
}

extract_verify_mode_line() {
  local log="$1"
  if [[ ! -f "$log" ]]; then
    return 0
  fi
  grep -m1 '^mode=' "$log" || true
}

extract_verify_log_mode() {
  local log="$1"
  local line=""
  line="$(extract_verify_mode_line "$log")"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi
  local mode="${line#mode=}"
  mode="${mode%% *}"
  echo "$mode"
}

extract_verify_log_verify_mode() {
  local log="$1"
  local line=""
  line="$(extract_verify_mode_line "$log")"
  if [[ -z "$line" ]]; then
    echo ""
    return 0
  fi
  if [[ "$line" != *"verify_mode="* ]]; then
    echo ""
    return 0
  fi
  local verify_mode="${line#*verify_mode=}"
  verify_mode="${verify_mode%% *}"
  echo "$verify_mode"
}

# Ensure PRD is valid
jq . "$PRD_FILE" >/dev/null 2>&1 || { echo "ERROR: $PRD_FILE invalid JSON" >&2; exit 1; }
if ! jq -e '.items and (.items | type == "array")' "$PRD_FILE" >/dev/null 2>&1; then
  echo "ERROR: PRD must be an object with .items array: $PRD_FILE" >&2
  exit 1
fi

# Ensure task exists
exists="$(jq --arg id "$ID" '
  any(.items[]; .id==$id)
' "$PRD_FILE")"

if [[ "$exists" != "true" ]]; then
  echo "ERROR: task id not found in PRD: $ID" >&2
  exit 3
fi

tmp="$(mktemp)"
jq --arg id "$ID" --argjson status "$STATUS" '
  .items = (.items | map(if .id == $id then .passes = $status else . end))
' "$PRD_FILE" > "$tmp" && mv "$tmp" "$PRD_FILE"

echo "Updated task $ID: passes=$STATUS"
