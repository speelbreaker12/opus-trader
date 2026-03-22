#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_hooks="$repo_root/.githooks"
source "$repo_root/plans/lib/obsidian_vault.sh"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found." >&2
  exit 1
fi

if [ ! -d "$repo_hooks" ]; then
  echo "ERROR: missing hook directory: $repo_hooks" >&2
  exit 1
fi

git -C "$repo_root" config core.hooksPath "$repo_hooks"

if paths="$(git -C "$repo_root" worktree list --porcelain 2>/dev/null | awk '/^worktree / {print $2}')" && [ -n "$paths" ]; then
  while IFS= read -r worktree; do
    if [ -z "$worktree" ]; then
      continue
    fi
    if git -C "$worktree" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$worktree" config core.hooksPath "$repo_hooks"
    fi
  done <<< "$paths"
fi

if [ -d "$repo_hooks" ]; then
  chmod +x "$repo_hooks"/* || true
fi

vault_root="$(obsidian_vault_configured_path)"
mkdir -p "$vault_root/Projects" "$vault_root/Debriefs" "$vault_root/Templates"

echo "Hooks installed to $repo_hooks"
echo "Obsidian vault ready at $vault_root"
echo "Run this again after moving the repository or creating detached verification worktrees."
