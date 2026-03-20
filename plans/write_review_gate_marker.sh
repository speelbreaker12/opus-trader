#!/usr/bin/env bash
set -euo pipefail

# Write review gate markers.
# Called after review-stack completes or manually after code review.
#
# Usage: ./plans/write_review_gate_marker.sh            (write commit-time attestation)
#        ./plans/write_review_gate_marker.sh --check     (verify commit-time marker is current)
#        ./plans/write_review_gate_marker.sh --pr-gate   (write PR gate marker for pr-review-gate-hook.sh)

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# PR gate marker — required by pr-review-gate-hook.sh before gh pr create
if [[ "${1:-}" == "--pr-gate" ]]; then
  branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  head_commit="$(git rev-parse HEAD 2>/dev/null || echo unknown)"
  marker_dir="artifacts/pr-review-gate"
  mkdir -p "$marker_dir"
  cat > "$marker_dir/${branch}.json" <<PREOF
{
  "verdict": "PASS",
  "head_commit": "$head_commit",
  "review_tool": "code-review-expert",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
PREOF
  echo "OK: PR gate marker written for $branch at $head_commit"
  echo "  file: $marker_dir/${branch}.json"
  exit 0
fi

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
