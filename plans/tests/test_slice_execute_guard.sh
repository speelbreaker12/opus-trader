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

# Case 3: wrong-implementation section reference regressed to §4.
fixture_wrong_impl="$tmp_dir/wrong_impl"
mk_fixture "$fixture_wrong_impl"
replace_text \
  "$fixture_wrong_impl/SKILLS/slice-execute.md" \
  "At least one case from the premortem §5 (wrong impl gate) — the tightened AT" \
  "At least one case from the premortem §4 (wrong impl gate) — the tightened AT"

set +e
wrong_impl_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_wrong_impl" "$SCRIPT" 2>&1)"
wrong_impl_rc=$?
set -e
[[ "$wrong_impl_rc" -ne 0 ]] || fail "expected wrong-impl section drift case to fail"
echo "$wrong_impl_output" | grep -Fq "WRONG_IMPL_SECTION_DRIFT" || fail "missing WRONG_IMPL_SECTION_DRIFT diagnostic"

# Case 4: stale preflight wording appears while required premortem lines still exist.
fixture_preflight="$tmp_dir/preflight"
mk_fixture "$fixture_preflight"
printf '\nLegacy wording: GO (preflight was GREEN/YELLOW-addressed)\n' >> "$fixture_preflight/SKILLS/slice-execute.md"

set +e
preflight_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_preflight" "$SCRIPT" 2>&1)"
preflight_rc=$?
set -e
[[ "$preflight_rc" -ne 0 ]] || fail "expected preflight wording drift case to fail"
echo "$preflight_output" | grep -Fq "PREMORTEM_WORDING_DRIFT" || fail "missing PREMORTEM_WORDING_DRIFT diagnostic"

# Case 5: premortem immutability statement removed.
fixture_immut="$tmp_dir/immut"
mk_fixture "$fixture_immut"
replace_text \
  "$fixture_immut/SKILLS/slice-execute.md" \
  "keep premortem §10 STOPLIGHT as the pre-implementation gate record" \
  "update premortem stoplight after implementation"

set +e
immut_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_immut" "$SCRIPT" 2>&1)"
immut_rc=$?
set -e
[[ "$immut_rc" -ne 0 ]] || fail "expected premortem immutability drift case to fail"
echo "$immut_output" | grep -Fq "PREMORTEM_IMMUTABILITY_DRIFT" || fail "missing PREMORTEM_IMMUTABILITY_DRIFT diagnostic"

# Case 6: trading-system lens heading removed.
fixture_lens="$tmp_dir/lens"
mk_fixture "$fixture_lens"
replace_text \
  "$fixture_lens/SKILLS/slice-execute.md" \
  "### 0A) Trading-System Implementation Lens" \
  "### 0A) Implementation Lens"

set +e
lens_output="$(SLICE_EXECUTE_GUARD_ROOT="$fixture_lens" "$SCRIPT" 2>&1)"
lens_rc=$?
set -e
[[ "$lens_rc" -ne 0 ]] || fail "expected trading-lens drift case to fail"
echo "$lens_output" | grep -Fq "TRADING_LENS_MISSING" || fail "missing TRADING_LENS_MISSING diagnostic"

echo "PASS: slice execute guard test"
