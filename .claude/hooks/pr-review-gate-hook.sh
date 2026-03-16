#!/usr/bin/env bash
# PreToolUse hook: enforce review-stack gate before gh pr create
# Exit 2 blocks the tool call with the error message shown to Claude.

INPUT=$(cat)

inspect_pr_create_command() {
    local command_text="$1"
    local default_cwd="$2"

    python3 - "$command_text" "$default_cwd" <<'PY'
import os
import re
import shlex
import sys

command_text = sys.argv[1]
workdir = sys.argv[2]


def emit(matched: bool) -> None:
    print('1' if matched else '0')
    print(workdir)
    raise SystemExit(0)

def apply_chdir(path: str, current_workdir: str) -> str:
    if os.path.isabs(path):
        return os.path.abspath(path)
    return os.path.abspath(os.path.join(current_workdir, path))


def matches_tokens(tokens: list[str], default_workdir: str) -> tuple[bool, str]:
    assign_re = re.compile(r'^[A-Za-z_][A-Za-z0-9_]*=.*$')
    index = 0
    current_workdir = default_workdir

    while index < len(tokens):
        token = tokens[index]
        if assign_re.match(token):
            index += 1
            continue
        if token == 'env':
            index += 1
            while index < len(tokens):
                env_token = tokens[index]
                if env_token == '--':
                    index += 1
                    break
                if assign_re.match(env_token):
                    index += 1
                    continue
                if env_token in {'-u', '--unset'}:
                    index += 2
                    continue
                if env_token in {'-C', '--chdir'}:
                    if index + 1 >= len(tokens):
                        return False, default_workdir
                    current_workdir = apply_chdir(tokens[index + 1], current_workdir)
                    index += 2
                    continue
                if env_token in {'-S', '--split-string'}:
                    if index + 1 >= len(tokens):
                        return False, default_workdir
                    try:
                        split_tokens = shlex.split(tokens[index + 1], posix=True)
                    except Exception:
                        return False, default_workdir
                    tokens[index:index + 2] = split_tokens
                    continue
                if env_token.startswith('--unset='):
                    index += 1
                    continue
                if env_token.startswith('--chdir='):
                    current_workdir = apply_chdir(env_token.split('=', 1)[1], current_workdir)
                    index += 1
                    continue
                if env_token.startswith('--split-string='):
                    try:
                        split_tokens = shlex.split(env_token.split('=', 1)[1], posix=True)
                    except Exception:
                        return False, default_workdir
                    tokens[index:index + 1] = split_tokens
                    continue
                if env_token.startswith('-'):
                    index += 1
                    continue
                break
            continue
        if token == 'command':
            index += 1
            while index < len(tokens) and tokens[index].startswith('-'):
                index += 1
            continue
        break

    if index >= len(tokens) or tokens[index] != 'gh':
        return False, default_workdir

    index += 1
    flags_with_values = {'-R', '--repo', '-h', '--hostname'}
    help_like = {'help', 'version', '--help', '--version'}

    while index < len(tokens):
        token = tokens[index]
        if token in help_like:
            return False, default_workdir
        if token == 'pr':
            break
        if not token.startswith('-'):
            return False, default_workdir
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

    if index + 1 >= len(tokens) or tokens[index] != 'pr' or tokens[index + 1] != 'create':
        return False, default_workdir

    remaining = tokens[index + 2 :]
    if remaining and remaining[0] in {'help', 'version', '--help', '--version', '-h'}:
        return False, default_workdir

    return True, current_workdir


try:
    lexer = shlex.shlex(command_text, posix=True, punctuation_chars=';&|')
    lexer.whitespace_split = True
    lexer.commenters = ''
    tokens = list(lexer)
except Exception:
    emit(False)

if not tokens:
    emit(False)

segment = []
for token in tokens:
    if token and set(token) <= {';', '&', '|'}:
        matched, derived_workdir = matches_tokens(segment[:], workdir)
        if matched:
            workdir = derived_workdir
            emit(True)
        segment = []
        continue
    segment.append(token)

matched, derived_workdir = matches_tokens(segment[:], workdir)
if matched:
    workdir = derived_workdir
    emit(True)

emit(False)
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
    with open(path) as f:
        data = json.load(f)
except Exception:
    print('')
    raise SystemExit(0)

value = data.get(field, '')
if value is None:
    value = ''
print(str(value))
PY
}

read_marker_head() {
    local marker_path="$1"
    local marker_head=""

    marker_head="$(read_marker_field "$marker_path" head_commit)"
    if [ -z "$marker_head" ]; then
        marker_head="$(read_marker_field "$marker_path" head)"
    fi

    printf '%s\n' "$marker_head"
}

marker_head_matches_current() {
    local marker_head="$1"
    local head_sha="$2"
    local marker_norm=""
    local head_norm=""

    marker_norm=$(printf '%s' "$marker_head" | tr '[:upper:]' '[:lower:]')
    head_norm=$(printf '%s' "$head_sha" | tr '[:upper:]' '[:lower:]')

    case "$marker_norm" in
        *[!0-9a-f]*)
            return 1
            ;;
    esac

    if [[ ${#marker_norm} -lt 1 || ${#marker_norm} -gt 40 ]]; then
        return 1
    fi

    if [[ ${#marker_norm} -eq 40 ]]; then
        [[ "$marker_norm" == "$head_norm" ]]
        return $?
    fi

    [[ "$head_norm" == "$marker_norm"* ]]
}

resolve_marker_path() {
    local marker_name="$1"
    local repo_root="$2"
    local command_cwd="$3"
    local head_sha="$4"
    local require_verdict="$5"
    local cwd_path="$command_cwd/artifacts/pr-review-gate/$marker_name"
    local repo_path="$repo_root/artifacts/pr-review-gate/$marker_name"

    if marker_path_is_current "$repo_path" "$head_sha" "$require_verdict"; then
        printf '%s\n' "$repo_path"
        return 0
    fi

    if marker_path_is_current "$cwd_path" "$head_sha" "$require_verdict"; then
        printf '%s\n' "$cwd_path"
        return 0
    fi

    if [ -f "$repo_path" ]; then
        printf '%s\n' "$repo_path"
        return 0
    fi

    if [ -f "$cwd_path" ]; then
        printf '%s\n' "$cwd_path"
        return 0
    fi

    printf '%s\n' "$repo_path"
}

marker_path_is_current() {
    local marker_path="$1"
    local head_sha="$2"
    local require_verdict="$3"
    local verdict=""
    local marker_head=""

    if [ ! -f "$marker_path" ]; then
        return 1
    fi

    if [ "$require_verdict" = "1" ]; then
        verdict="$(read_marker_field "$marker_path" verdict)"
        if [ "$verdict" != "PASS" ] && [ "$verdict" != "CONDITIONAL_PASS" ]; then
            return 1
        fi
    fi

    marker_head="$(read_marker_head "$marker_path")"
    if [ -z "$marker_head" ]; then
        return 1
    fi

    marker_head_matches_current "$marker_head" "$head_sha"
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
COMMAND_CWD="$PWD"
segment_inspection="$(inspect_pr_create_command "$COMMAND" "$PWD")"
if [ "$(printf '%s\n' "$segment_inspection" | sed -n '1p')" = "1" ]; then
    TRIGGERED=1
    COMMAND_CWD="$(printf '%s\n' "$segment_inspection" | sed -n '2p')"
fi
[ "$TRIGGERED" -eq 1 ] || exit 0

BRANCH=$(git -C "$COMMAND_CWD" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")
HEAD_SHA=$(git -C "$COMMAND_CWD" rev-parse HEAD 2>/dev/null || echo "")
REPO_ROOT=$(git -C "$COMMAND_CWD" rev-parse --show-toplevel 2>/dev/null || echo "")

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

if [ -z "$REPO_ROOT" ]; then
    cat >&2 <<EOF
GATE BLOCKED: unable to determine repo root for branch '${BRANCH}'.
Re-run from a valid git checkout before creating the PR.
EOF
    exit 2
fi

SAFE_BRANCH="${BRANCH//\//_}"
MARKER="$(resolve_marker_path "${SAFE_BRANCH}.json" "$REPO_ROOT" "$COMMAND_CWD" "$HEAD_SHA" 1)"
EXT_MARKER="$(resolve_marker_path "${SAFE_BRANCH}.external.json" "$REPO_ROOT" "$COMMAND_CWD" "$HEAD_SHA" 0)"

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
MARKER_HEAD="$(read_marker_head "$MARKER")"

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
GATE BLOCKED: review-stack marker for '${BRANCH}' is missing head/head_commit.
Re-run /review-stack for the current branch head ${HEAD_SHA}.
EOF
    exit 2
fi

if ! marker_head_matches_current "$MARKER_HEAD" "$HEAD_SHA"; then
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
else
    EXT_MARKER_HEAD="$(read_marker_head "$EXT_MARKER")"
    if [ -z "$EXT_MARKER_HEAD" ]; then
        cat >&2 <<EOF
WARNING: /external-review marker for branch '${BRANCH}' is missing head/head_commit.
Re-run /external-review for the current branch head ${HEAD_SHA} if review coverage matters for this PR.
EOF
    elif ! marker_head_matches_current "$EXT_MARKER_HEAD" "$HEAD_SHA"; then
        cat >&2 <<EOF
WARNING: /external-review marker for branch '${BRANCH}' targets HEAD '${EXT_MARKER_HEAD}' but current HEAD is '${HEAD_SHA}'.
Re-run /external-review for the current branch head if review coverage matters for this PR.
EOF
    fi
fi

exit 0
