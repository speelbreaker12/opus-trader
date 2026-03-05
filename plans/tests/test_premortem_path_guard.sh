#!/usr/bin/env bash
set -euo pipefail

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

cat > "$fixture/docs/good.md" <<'MD'
Use reviews/premortems/S1-007_premortem.md.
MD

PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" >/dev/null

legacy_root="artifacts/story"
legacy_leaf="premortem.md"
printf 'legacy: %s/%s/%s\n' "$legacy_root" "<ID>" "$legacy_leaf" > "$fixture/docs/bad.md"
git -C "$fixture" add docs/bad.md

set +e
out="$(PREMORTEM_PATH_GUARD_ROOT="$fixture" "$SCRIPT" 2>&1)"
rc=$?
set -e

[[ "$rc" -ne 0 ]] || fail "expected guard to fail on legacy path reference"
echo "$out" | grep -Fq "FAIL: legacy premortem path reference(s) detected" || fail "missing failure banner"
echo "$out" | grep -Fq "docs/bad.md:1" || fail "missing offending file/line diagnostic"
echo "$out" | grep -Fq "Canonical path: reviews/premortems/<ID>_premortem.md" || fail "missing canonical path hint"

echo "PASS: premortem path guard"
