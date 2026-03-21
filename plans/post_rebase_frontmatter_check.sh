#!/usr/bin/env bash
set -euo pipefail

# Post-rebase frontmatter check
# Verifies that the project note's branch/base/scope_paths weren't clobbered
# by a rebase that resolved conflicts using main's version.
#
# Usage: ./plans/post_rebase_frontmatter_check.sh [--branch <name>]
# Called by /push-pr skill after rebase completes.

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

branch_name=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch) branch_name="${2:?missing branch name}"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -z "$branch_name" ]]; then
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -n "$branch_name" && "$branch_name" != "HEAD" ]] || {
  echo "ERROR: unable to determine current branch" >&2
  exit 1
}

# Find the project note that declares this branch
project_file=""
while IFS= read -r path; do
  pf_branch="$(python3 -c "
import sys; sys.path.insert(0, '$ROOT/plans/lib')
from obsidian_frontmatter import parse_frontmatter, frontmatter_scalar
fm = parse_frontmatter(open('$path').read())
print(frontmatter_scalar(fm, 'branch'))
" 2>/dev/null || true)"
  if [[ "$pf_branch" == "$branch_name" ]]; then
    project_file="$path"
    break
  fi
done < <(find obsidian/Projects -name '*.md' -type f 2>/dev/null)

if [[ -z "$project_file" ]]; then
  echo "WARN: No project note declares branch '$branch_name' — skipping frontmatter check"
  exit 0
fi

echo "Checking post-rebase frontmatter in $project_file..."

# Extract all needed fields via the shared Python parser in one call
eval "$(python3 -c "
import sys, shlex
sys.path.insert(0, '$ROOT/plans/lib')
from obsidian_frontmatter import parse_frontmatter, frontmatter_scalar, frontmatter_list

fm = parse_frontmatter(open('$project_file').read())

branch = frontmatter_scalar(fm, 'branch')
base = frontmatter_scalar(fm, 'base')
status = frontmatter_scalar(fm, 'status')
scope_paths = frontmatter_list(fm, 'scope_paths')

print(f'fm_branch={shlex.quote(branch)}')
print(f'fm_base={shlex.quote(base)}')
print(f'fm_status={shlex.quote(status)}')
print(f'fm_scope_count={len(scope_paths)}')
")"

errors=0

# Check branch: field matches current branch
if [[ "$fm_branch" != "$branch_name" ]]; then
  echo "ERROR: branch: is '$fm_branch' but current branch is '$branch_name'" >&2
  echo "  This was likely clobbered by rebase conflict resolution." >&2
  errors=$((errors + 1))
fi

# Check base: field is non-empty
if [[ -z "$fm_base" ]]; then
  echo "WARNING: base: is empty in $project_file" >&2
  echo "  Verify this is intentional after rebase." >&2
fi

# Check scope_paths: has at least one entry
if [[ "$fm_scope_count" -eq 0 ]]; then
  echo "WARNING: scope_paths is empty in $project_file" >&2
  echo "  The project scope guard will fail on commit and PR-create." >&2
fi

# Check status: isn't "done" (rebase may have pulled main's version)
if [[ "$fm_status" == "done" ]]; then
  echo "WARNING: status: is 'done' in $project_file" >&2
  echo "  If this branch is still active, the status was likely clobbered by rebase." >&2
fi

if [[ $errors -gt 0 ]]; then
  echo ""
  echo "FAILED: $errors frontmatter field(s) appear clobbered by rebase."
  echo "Edit $project_file to restore the correct values before pushing."
  exit 1
fi

echo "OK: post-rebase frontmatter check passed for $project_file"
