#!/usr/bin/env bash
set -euo pipefail
# Neutralize GIT_DIR leak from parent (pre-push hook sets GIT_DIR)
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_OBJECT_DIRECTORY 2>/dev/null || true

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/premortem_path_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

fixture="$tmp_dir/repo"
mkdir -p "$fixture/docs" "$fixture/reviews/premortems"
git init -q "$fixture"
git -C "$fixture" config core.hooksPath /dev/null

cat > "$fixture/docs/good.md" <<'MD'
Use reviews/premortems/S1-007_premortem.md.
MD

PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" >/dev/null

legacy_root="artifacts/story"
legacy_leaf="premortem.md"
printf 'legacy: %s/%s/%s\n' "$legacy_root" "<ID>" "$legacy_leaf" > "$fixture/docs/bad.md"

set +e
out="$(PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1)"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || fail "expected guard to fail on untracked legacy path reference"
echo "$out" | grep -Fq "FAIL: legacy premortem path reference(s) detected" || fail "missing failure banner for untracked file"
echo "$out" | grep -Fq "docs/bad.md:1" || fail "missing offending file/line diagnostic for untracked file"

git -C "$fixture" add docs/bad.md

set +e
out="$(PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1)"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || fail "expected guard to fail on staged legacy path reference"
echo "$out" | grep -Fq "FAIL: legacy premortem path reference(s) detected" || fail "missing failure banner"
echo "$out" | grep -Fq "docs/bad.md:1" || fail "missing offending file/line diagnostic"
echo "$out" | grep -Fq "Canonical path: reviews/premortems/<ID>_premortem.md" || fail "missing canonical path hint"

printf 'legacy-untracked: %s/%s/%s\n' "$legacy_root" "<ID>" "$legacy_leaf" > "$fixture/docs/untracked_bad.md"

set +e
untracked_out="$(PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1)"
untracked_rc=$?
set -e

[[ "$untracked_rc" -ne 0 ]] || fail "expected guard to fail on untracked legacy path reference"
echo "$untracked_out" | grep -Fq "docs/untracked_bad.md:1" || fail "missing untracked offending file/line diagnostic"

echo "PASS: premortem path guard"
