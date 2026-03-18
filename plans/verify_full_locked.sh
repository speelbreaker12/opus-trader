#!/usr/bin/env bash
# plans/verify_full_locked.sh — enforce one full verify per machine
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./plans/verify_full_locked.sh <STORY_ID> [additional verify args...]

Runs ./plans/verify.sh full under a machine-local lock so only one full verify
can run at a time.
USAGE
}

STORY_ID="${1:-}"
if [[ -z "$STORY_ID" ]]; then
  usage >&2
  exit 2
fi
shift || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

LOCKFILE="${VERIFY_FULL_LOCKFILE:-/tmp/verify_full.lock}"
LOCKDIR="${LOCKFILE}.d"

cleanup() {
  rm -f "$LOCKFILE" 2>/dev/null || true
  rmdir "$LOCKDIR" 2>/dev/null || true
}

describe_holder() {
  if [[ -f "$LOCKFILE" ]]; then
    cat "$LOCKFILE"
  else
    echo "unknown holder"
  fi
}

if command -v flock >/dev/null 2>&1; then
  exec 200>"$LOCKFILE"
  if ! flock -n 200; then
    echo "BLOCKED: verify already running ($(describe_holder))" >&2
    exit 1
  fi
else
  if ! mkdir "$LOCKDIR" 2>/dev/null; then
    echo "BLOCKED: verify already running ($(describe_holder))" >&2
    exit 1
  fi
fi

trap cleanup EXIT INT TERM

printf 'Story=%s PID=%s Started=%s Host=%s Cwd=%s\n' \
  "$STORY_ID" "$$" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$(hostname 2>/dev/null || echo unknown)" "$ROOT" > "$LOCKFILE"

./plans/verify.sh full "$@"
