#!/usr/bin/env bash
# PreToolUse hook: enforce review-stack gate before gh pr create
# Exit 2 blocks the tool call with the error message shown to Claude.

INPUT=$(cat)

matches_pr_create_segment() {
    local segment="$1"

    python3 - "$segment" <<'PY'
import re
import shlex
import sys

segment = sys.argv[1]

try:
    lexer = shlex.shlex(segment, posix=True)
    lexer.whitespace_split = True
    lexer.commenters = ''
    tokens = list(lexer)
except Exception:
    print('0')
    raise SystemExit(0)

if not tokens:
    print('0')
    raise SystemExit(0)

index = 0
while index < len(tokens) and re.match(r'^[A-Za-z_][A-Za-z0-9_]*=.*$', tokens[index]):
    index += 1

if index >= len(tokens) or tokens[index] != 'gh':
    print('0')
    raise SystemExit(0)

index += 1
flags_with_values = {'-R', '--repo', '-h', '--hostname'}

while index < len(tokens):
    token = tokens[index]
    if token == 'pr':
        break
    if not token.startswith('-'):
        print('0')
        raise SystemExit(0)
    if token in flags_with_values:
        index += 2
        continue
    if token.startswith('-R') and token != '-R':
        index += 1
        continue
    if token.startswith('--repo=') or token.startswith('--hostname='):
        index += 1
        continue
    index += 1

if index + 1 < len(tokens) and tokens[index] == 'pr' and tokens[index + 1] == 'create':
    print('1')
else:
    print('0')
PY
}

read_marker_field() {
    local marker_path="$1"
    local field_name="$2"

    python3 - "$marker_path" "$field_name" <<'PY'
import json
import sys

path, field = sys.argv[1:3]

try:
    data = json.load(open(path))
except Exception:
    print('')
    raise SystemExit(0)

value = data.get(field, '')
if value is None:
    value = ''
print(str(value))
PY
}

COMMAND=$(python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('command', ''))
except Exception:
    print('')
" <<< "$INPUT" 2>/dev/null || echo "")

# Only fire on gh pr create as an actual command invocation.
# Split on shell separators and check if any segment invokes gh pr create.
TRIGGERED=0
while IFS= read -r segment; do
    # Strip leading whitespace
    segment="${segment#"${segment%%[![:space:]]*}"}"
    if [ "$(matches_pr_create_segment "$segment")" = "1" ]; then
        TRIGGERED=1
        break
    fi
done < <(printf '%s\n' "$COMMAND" | tr ';&|' '\n')
[ "$TRIGGERED" -eq 1 ] || exit 0

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")

# Can't determine branch — don't block
if [ -z "$BRANCH" ] || [ "$BRANCH" = "HEAD" ]; then
    exit 0
fi

if [ -z "$HEAD_SHA" ]; then
    cat >&2 <<EOF
GATE BLOCKED: unable to determine current HEAD for branch '${BRANCH}'.
Re-run from a valid git checkout before creating the PR.
EOF
    exit 2
fi

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

VERDICT="$(read_marker_field "$MARKER" verdict)"
MARKER_HEAD="$(read_marker_field "$MARKER" head_commit)"

[ -n "$VERDICT" ] || VERDICT="UNKNOWN"

if [ "$VERDICT" != "PASS" ] && [ "$VERDICT" != "CONDITIONAL_PASS" ]; then
    cat >&2 <<EOF
GATE BLOCKED: review-stack verdict for '${BRANCH}' is '${VERDICT}'.
Must be PASS or CONDITIONAL_PASS. Re-run /review-stack and fix all findings.
EOF
    exit 2
fi

if [ -z "$MARKER_HEAD" ]; then
    cat >&2 <<EOF
GATE BLOCKED: review-stack marker for '${BRANCH}' is missing head_commit.
Re-run /review-stack for the current branch head ${HEAD_SHA}.
EOF
    exit 2
fi

if [ "$MARKER_HEAD" != "$HEAD_SHA" ]; then
    cat >&2 <<EOF
GATE BLOCKED: review-stack marker for '${BRANCH}' targets HEAD '${MARKER_HEAD}' but current HEAD is '${HEAD_SHA}'.
Re-run /review-stack for the current branch head before creating the PR.
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
