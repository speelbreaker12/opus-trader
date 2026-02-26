#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required for code-review-expert attestation" >&2
  exit 2
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -z "$git_dir" ]]; then
  echo "ERROR: code-review-expert attestation requires a git repository" >&2
  exit 2
fi

head_sha="$(git rev-parse HEAD 2>/dev/null || echo "NO_HEAD")"
tree_sha="$(git write-tree)"
timestamp_utc="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
attest_file="$git_dir/code_review_expert.attest"

cat > "$attest_file" <<EOF
schema_version=1
head=$head_sha
tree=$tree_sha
attested_at_utc=$timestamp_utc
EOF

echo "OK: code-review-expert attestation updated"
echo "  file: $attest_file"
echo "  head: $head_sha"
echo "  tree: $tree_sha"
