#!/usr/bin/env bash
set -euo pipefail

ROOT_DEFAULT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${PREMORTEM_PATH_GUARD_ROOT:-$ROOT_DEFAULT}"
cd "$ROOT"

if ! command -v git >/dev/null 2>&1; then
  echo "FAIL: git is required for premortem path guard" >&2
  exit 1
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "FAIL: premortem path guard must run inside a git worktree" >&2
  exit 1
fi

legacy_root="artifacts/story"
legacy_leaf="premortem.md"
legacy_pattern="${legacy_root}/[^[:space:]]+/${legacy_leaf}"

hits=""

set +e
hits="$(
  git grep --untracked -nE "$legacy_pattern" -- . \
    ':(exclude)plans/premortem_path_guard.sh' \
    ':(exclude)plans/tests/test_premortem_path_guard.sh'
)"
tracked_rc=$?
set -e

case "$tracked_rc" in
  0|1)
    ;;
  *)
    echo "FAIL: scanner error while searching tracked files for legacy premortem paths (git grep rc=$tracked_rc)" >&2
    exit 1
    ;;
esac

if [[ -n "$hits" ]]; then
  echo "FAIL: legacy premortem path reference(s) detected" >&2
  echo "  Canonical path: reviews/premortems/<ID>_premortem.md" >&2
  printf '%s\n' "$hits" | LC_ALL=C sort -u | sed 's/^/  /' >&2
  exit 1
fi

echo "premortem_path_guard: PASS"
