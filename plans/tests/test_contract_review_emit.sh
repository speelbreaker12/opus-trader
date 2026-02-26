#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EMIT="$ROOT/plans/contract_review_emit.sh"
VALIDATE="$ROOT/plans/contract_review_validate.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ -x "$EMIT" ]] || fail "missing executable emitter: $EMIT"
[[ -x "$VALIDATE" ]] || fail "missing validator: $VALIDATE"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

blocked_out="$tmp_dir/contract_review_blocked.json"
"$EMIT" --out "$blocked_out"
[[ -f "$blocked_out" ]] || fail "blocked output not created"
"$VALIDATE" "$blocked_out"
[[ "$(jq -r '.decision' "$blocked_out")" == "BLOCKED" ]] \
  || fail "default decision must be BLOCKED"
[[ "$(jq -r '.pass_flip_check.decision_on_pass_flip' "$blocked_out")" == "BLOCKED" ]] \
  || fail "default pass_flip_check.decision_on_pass_flip must be BLOCKED"

pass_out="$tmp_dir/contract_review_pass.json"
"$EMIT" --out "$pass_out" --decision PASS --story-id S14-003
[[ -f "$pass_out" ]] || fail "pass output not created"
"$VALIDATE" "$pass_out"
[[ "$(jq -r '.decision' "$pass_out")" == "PASS" ]] \
  || fail "decision override PASS not emitted"
[[ "$(jq -r '.selected_story_id' "$pass_out")" == "S14-003" ]] \
  || fail "story-id override not emitted"
[[ "$(jq -r '.pass_flip_check.requested_mark_pass_id' "$pass_out")" == "S14-003" ]] \
  || fail "requested_mark_pass_id should match story-id by default"
[[ "$(jq -r '.pass_flip_check.decision_on_pass_flip' "$pass_out")" == "ALLOW" ]] \
  || fail "PASS decision should map to ALLOW for decision_on_pass_flip"

set +e
invalid_output="$("$EMIT" --out "$tmp_dir/invalid.json" --decision MAYBE 2>&1)"
invalid_rc=$?
set -e
[[ "$invalid_rc" -ne 0 ]] || fail "invalid decision should fail"
printf '%s\n' "$invalid_output" | grep -Fq "invalid decision" \
  || fail "invalid decision diagnostic missing"

echo "PASS: contract_review_emit"
