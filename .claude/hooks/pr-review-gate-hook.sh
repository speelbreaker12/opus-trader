#!/usr/bin/env bash
# PreToolUse hook: enforce review-stack gate before gh pr create
# Exit 2 blocks the tool call with the error message shown to Claude.

INPUT=$(cat)

COMMAND=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

# Only fire on gh pr create as an actual command invocation.
# Split on shell separators and check if any segment starts with 'gh pr create'.
TRIGGERED=0
while IFS= read -r segment; do
    # Strip leading whitespace
    segment="${segment#"${segment%%[![:space:]]*}"}"
    if echo "$segment" | grep -qE '^gh pr create( |$)'; then
        TRIGGERED=1
        break
    fi
done < <(printf '%s' "$COMMAND" | tr ';&|' '\n')
[ "$TRIGGERED" -eq 1 ] || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")

# Can't determine branch — don't block
[ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ] && exit 0

SAFE_BRANCH="${BRANCH//\//_}"
MARKER="artifacts/pr-review-gate/${SAFE_BRANCH}.json"
EXT_MARKER="artifacts/pr-review-gate/${SAFE_BRANCH}.external.json"

# ── review-stack gate (BLOCKING) ──────────────────────────────────────────
if [ ! -f "$MARKER" ]; then
    cat >&2 <<EOF
GATE BLOCKED: No review-stack result for branch '${BRANCH}'.
Run /review-stack first. It must complete with PASS or CONDITIONAL_PASS.
Expected marker: ${MARKER}
EOF
    exit 2
fi

VERDICT=$(python3 -c "
import json
try:
    print(json.load(open('$MARKER')).get('verdict', 'UNKNOWN'))
except Exception:
    print('UNKNOWN')
" 2>/dev/null || echo "UNKNOWN")

if [ "$VERDICT" != "PASS" ] && [ "$VERDICT" != "CONDITIONAL_PASS" ]; then
    cat >&2 <<EOF
GATE BLOCKED: review-stack verdict for '${BRANCH}' is '${VERDICT}'.
Must be PASS or CONDITIONAL_PASS. Re-run /review-stack and fix all findings.
EOF
    exit 2
fi

# ── external-review gate (WARNING only) ───────────────────────────────────
if [ ! -f "$EXT_MARKER" ]; then
    cat >&2 <<EOF
WARNING: /external-review has not been run for branch '${BRANCH}'.
Recommended for PRs touching crates/. Proceeding anyway.
EOF
fi

exit 0
