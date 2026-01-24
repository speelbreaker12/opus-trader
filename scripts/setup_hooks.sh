#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git not found." >&2
  exit 1
fi

git -C "$repo_root" config core.hooksPath .githooks

if [ -d "$repo_root/.githooks" ]; then
  chmod +x "$repo_root/.githooks"/* || true
fi

echo "Hooks installed to $repo_root/.githooks"
