#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/plans/slice_execute_guard.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$SCRIPT" ]] || fail "missing executable script: $SCRIPT"

mk_fixture() {
  local dst="$1"
  mkdir -p "$dst/SKILLS"
  cp "$ROOT/SKILLS/slice-execute.md" "$dst/SKILLS/slice-execute.md"
}

replace_text() {
  local path="$1"
  local old="$2"
  local new="$3"
  python3 - "$path" "$old" "$new" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
old = sys.argv[2]
new = sys.argv[3]
text = path.read_text()
if old not in text:
    raise SystemExit(f"missing target text in {path}")
path.write_text(text.replace(old, new, 1))
PY
}

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

SLICE_EXECUTE_GUARD_ROOT="$ROOT" "$SCRIPT" >/dev/null

# Case 1: mechanical verification boundary removed.
fixture_mech="$tmp_dir/mech"
mk_fixture "$fixture_mech"
replace_text \
  "$fixture_mech/SKILLS/slice-execute.md" \
  '`./plans/verify_mechanical.sh` is a partial mechanical check: it confirms compileability and validates PRD metadata only for stories that already have `passes=true`.' \
  '`./plans/verify_mechanical.sh` fully proves this story is correct.'

set +e
mech_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_mech" "$SCRIPT" 2>&1)"
mech_rc=$?
set -e
[[ "$mech_rc" -ne 0 ]] || fail "expected mechanical-boundary drift case to fail"
echo "$mech_output" | grep -Fq "MECHANICAL_SCOPE_MISSING" || fail "missing MECHANICAL_SCOPE_MISSING diagnostic"

# Case 2: full workflow authority pointer removed.
fixture_loop="$tmp_dir/loop"
mk_fixture "$fixture_loop"
replace_text \
  "$fixture_loop/SKILLS/slice-execute.md" \
  'See `specs/WORKFLOW_CONTRACT.md` §6 and `docs/PRD_STORY_WORKFLOW.md` for the canonical full story loop.' \
  'Story loop details are omitted here.'

set +e
loop_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_loop" "$SCRIPT" 2>&1)"
loop_rc=$?
set -e
[[ "$loop_rc" -ne 0 ]] || fail "expected workflow-loop drift case to fail"
echo "$loop_output" | grep -Fq "WORKFLOW_LOOP_POINTER_MISSING" || fail "missing WORKFLOW_LOOP_POINTER_MISSING diagnostic"

echo "PASS: slice execute guard test"
