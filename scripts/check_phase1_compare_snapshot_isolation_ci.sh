#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OUTPUT_DIR="${REPO_ROOT}/artifacts/phase1_compare/ci_snapshot_isolation"

mkdir -p "${OUTPUT_DIR}"

if ! git -C "${REPO_ROOT}" rev-parse HEAD~1 >/dev/null 2>&1; then
  echo "[snapshot_smoke_ci] WARN: repository has no parent commit; skipping snapshot-isolation smoke check." >&2
  exit 0
fi

./scripts/check_phase1_compare_snapshot_isolation.sh \
  --opus "${REPO_ROOT}" \
  --ralph "${REPO_ROOT}" \
  --opus-ref HEAD \
  --ralph-ref HEAD~1 \
  --skip-meta-test \
  --output "${OUTPUT_DIR}/report.md"
