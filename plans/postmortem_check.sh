#!/usr/bin/env bash
set -euo pipefail

# Postmortem check: verifies at least one postmortem artifact was changed.
# Checks both legacy (reviews/postmortems/) and current (artifacts/story/*/postmortem.md) paths.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BASE_REF="${BASE_REF:-origin/main}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

warn() {
  echo "WARN: $*" >&2
}

if ! command -v git >/dev/null 2>&1; then
  fail "git is required for postmortem check"
fi

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  if [[ -n "${CI:-}" ]]; then
    fail "CI must be able to diff against BASE_REF=$BASE_REF"
  else
    warn "Cannot verify BASE_REF=$BASE_REF (skipping postmortem check locally)"
    exit 0
  fi
fi

changed_files="$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null || true)"
if [[ -z "$changed_files" ]]; then
  echo "postmortem check: no changes detected"
  exit 0
fi

# Check current path: artifacts/story/*/postmortem.md
current_pm="$(echo "$changed_files" | grep -E '^artifacts/story/.+/postmortem\.md$' || true)"

# Check legacy path: reviews/postmortems/*.md (excluding README/templates)
legacy_pm="$(echo "$changed_files" | grep -E '^reviews/postmortems/.*\.md$' | grep -vE '(README|TEMPLATE)\.md$' || true)"

if [[ -z "$current_pm" && -z "$legacy_pm" ]]; then
  fail "No postmortem entry changed (expected artifacts/story/<ID>/postmortem.md or reviews/postmortems/*.md)"
fi

echo "postmortem check: OK"
