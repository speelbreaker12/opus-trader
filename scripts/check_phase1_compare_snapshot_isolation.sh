#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [[ $# -lt 1 ]]; then
  cat <<'EOF'
Usage:
  check_phase1_compare_snapshot_isolation.sh [phase1_compare args...]

Example:
  ./scripts/check_phase1_compare_snapshot_isolation.sh \
    --opus /Users/admin/Desktop/opus-trader \
    --ralph /Users/admin/Desktop/ralph \
    --opus-ref phase1-compare-explicit-20260214-003126-opus \
    --ralph-ref phase1-compare-explicit-20260214-003126-ralph \
    --output artifacts/phase1_compare/smoke_ref_isolation/report.md \
    --skip-meta-test
EOF
  exit 1
fi

OUTPUT_ARG=""
FILTERED_ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      OUTPUT_ARG="$2"
      shift 2
      ;;
    -h|--help)
      cat <<'EOF'
Usage:
  check_phase1_compare_snapshot_isolation.sh [phase1_compare args...]

Example:
  ./scripts/check_phase1_compare_snapshot_isolation.sh \
    --opus /Users/admin/Desktop/opus-trader \
    --ralph /Users/admin/Desktop/ralph \
    --opus-ref phase1-compare-explicit-20260214-003126-opus \
    --ralph-ref phase1-compare-explicit-20260214-003126-ralph \
    --output artifacts/phase1_compare/smoke_ref_isolation/report.md \
    --skip-meta-test
EOF
      exit 0
      ;;
    *)
      FILTERED_ARGS+=("$1")
      shift
      ;;
  esac
done

if [[ -z "${OUTPUT_ARG}" ]]; then
  OUTPUT_DIR="$(mktemp -d -t phase1-compare-snapshot-smoke.XXXXXX)"
  OUTPUT_ARG="${OUTPUT_DIR}/report.md"
else
  OUTPUT_DIR="$(dirname "${OUTPUT_ARG}")"
fi

python3 "${REPO_ROOT}/tools/phase1_compare.py" "${FILTERED_ARGS[@]}" --output "${OUTPUT_ARG}"

REPORT_JSON="${OUTPUT_DIR}/report.json"
if [[ ! -f "${REPORT_JSON}" ]]; then
  echo "[snapshot_smoke] ERROR: expected report JSON at ${REPORT_JSON}" >&2
  exit 1
fi

python3 - "${OUTPUT_ARG}" "${REPORT_JSON}" <<'PY'
import json
import re
import sys

md_path, json_path = sys.argv[1], sys.argv[2]

with open(json_path, "r", encoding="utf-8") as fp:
    report = json.load(fp)

for repo in ("opus", "ralph"):
    repo_obj = report[repo]
    if repo_obj.get("is_ref_head"):
        continue
    if repo_obj.get("path") == repo_obj.get("analysis_path"):
        raise SystemExit(
            f"{repo} expected detached snapshot for non-HEAD ref but path and analysis_path are identical: {repo_obj.get('path')}"
        )

run_id = re.sub(r".*/", "", re.sub(r"/report\\.md$", "", md_path))
print(f"[snapshot_smoke] PASS: non-HEAD repos used detached snapshots for run_id={run_id}")
PY
