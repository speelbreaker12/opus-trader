#!/usr/bin/env bash
set -euo pipefail

ROOT="${SLICE_EXECUTE_GUARD_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
skill="$ROOT/SKILLS/slice-execute.md"

fail() {
  local code="$1"
  local message="$2"
  echo "FAIL: ${code}: ${message}" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "MISSING_FILE" "$path"
}

require_contains() {
  local path="$1"
  local pattern="$2"
  local code="$3"
  grep -Fq "$pattern" "$path" || fail "$code" "$path missing required token: $pattern"
}

require_file "$skill"

require_contains "$skill" '`./plans/verify_mechanical.sh` is a partial mechanical check' "MECHANICAL_SCOPE_MISSING"
require_contains "$skill" 'stories that already have `passes=true`' "MECHANICAL_SCOPE_MISSING"
require_contains "$skill" 'This skill covers the implementation step only; it does not replace self-review, external review, resolution, or pass gating.' "IMPLEMENT_SCOPE_MISSING"
require_contains "$skill" 'See `specs/WORKFLOW_CONTRACT.md` §6 and `docs/PRD_STORY_WORKFLOW.md` for the canonical full story loop.' "WORKFLOW_LOOP_POINTER_MISSING"

echo "PASS: slice execute guard"
