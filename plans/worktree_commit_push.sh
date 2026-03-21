#!/usr/bin/env bash
set -euo pipefail

# CWD-resilient worktree commit+push
# Runs the full stage → attest → commit → push flow in a single process
# inside the specified worktree, immune to shell CWD resets between commands.
#
# Usage:
#   ./plans/worktree_commit_push.sh <worktree_path> \
#     --files "file1 file2 ..." \
#     --message "commit message" \
#     [--push]                    # also push after commit
#     [--skip-review]             # skip code-review-expert attestation
#     [--review-fix]              # enable review-fix mode (relaxed obsidian)

usage() {
  cat <<'EOF'
Usage: ./plans/worktree_commit_push.sh <worktree_path> [options]

Options:
  --files "f1 f2 ..."     Files to stage (space-separated, relative to worktree)
  --message "msg"          Commit message
  --push                   Push after commit
  --skip-review            Skip code-review-expert attestation
  --review-fix             Enable review-fix mode (relaxed obsidian gates)
  --all                    Stage all modified files (git add -A)
EOF
}

worktree_path="${1:?missing worktree path}"
shift

files=""
message=""
do_push=0
skip_review=0
review_fix=0
stage_all=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --files) files="${2:?missing files}"; shift 2 ;;
    --message) message="${2:?missing message}"; shift 2 ;;
    --push) do_push=1; shift ;;
    --skip-review) skip_review=1; shift ;;
    --review-fix) review_fix=1; shift ;;
    --all) stage_all=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown arg: $1" >&2; exit 2 ;;
  esac
done

[[ -n "$message" ]] || { echo "ERROR: --message is required" >&2; exit 2; }
[[ -n "$files" || "$stage_all" -eq 1 ]] || { echo "ERROR: --files or --all is required" >&2; exit 2; }

# Lock into worktree
cd "$worktree_path" || { echo "ERROR: cannot cd to $worktree_path" >&2; exit 1; }
echo "Worktree: $(pwd)"
echo "Branch: $(git rev-parse --abbrev-ref HEAD)"

# Stage
if [[ "$stage_all" -eq 1 ]]; then
  git add -A
else
  # shellcheck disable=SC2086
  git add $files
fi

echo "Staged $(git diff --cached --stat | tail -1)"

# Attest (if not skipping)
if [[ "$skip_review" -eq 1 ]]; then
  export SKIP_CODE_REVIEW_EXPERT_HOOK=1
fi

if [[ "$review_fix" -eq 1 ]]; then
  export OBSIDIAN_REVIEW_FIX=1
fi

# Commit (pre-commit hook runs inside this process, in the correct CWD)
git commit -m "$message"

echo "Committed: $(git log --oneline -1)"

# Push
if [[ "$do_push" -eq 1 ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD)"
  git push origin "$branch"
  echo "Pushed to origin/$branch"
fi
