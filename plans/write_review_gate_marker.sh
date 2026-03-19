#!/usr/bin/env bash
set -euo pipefail

# Write the code-review-expert attestation marker.
# Called after review-stack completes or manually after code review.
#
# Usage: ./plans/write_review_gate_marker.sh
#        ./plans/write_review_gate_marker.sh --check  (verify marker is current)

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

git_dir="$(git rev-parse --git-dir 2>/dev/null || echo .git)"
attest_file="$git_dir/code_review_expert.attest"

if [[ "${1:-}" == "--check" ]]; then
  current_tree="$(git write-tree 2>/dev/null || true)"
  if [[ -f "$attest_file" ]]; then
    cached_tree="$(grep '^tree=' "$attest_file" | head -1 | cut -d= -f2-)"
    if [[ "$cached_tree" == "$current_tree" ]]; then
      echo "OK: attestation is current (tree=$current_tree)"
      exit 0
    else
      echo "STALE: attestation tree=$cached_tree, current tree=$current_tree" >&2
      exit 1
    fi
  else
    echo "MISSING: no attestation file" >&2
    exit 1
  fi
fi

current_tree="$(git write-tree)"
cat > "$attest_file" <<EOF
tree=$current_tree
timestamp=$(date -u +%Y-%m-%dT%H:%M:%SZ)
branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
EOF

echo "OK: code-review-expert attestation written (tree=$current_tree)"
