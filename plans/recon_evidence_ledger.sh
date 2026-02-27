#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  plans/recon_evidence_ledger.sh STORY_ID [--check|--scaffold] [--output <path>]

Purpose:
  Check for or scaffold the evidence ledger artifact required before:
    WF_RECON_MODE=1 plans/wf_step.sh <STORY_ID> cycle1

Options:
  --check            Validate that at least one accepted ledger path exists (default)
  --scaffold         Create a starter markdown ledger when missing
  --output <path>    Override scaffold output path
  -h, --help         Show this help

Exit codes:
  0 = ready/found/scaffolded
  1 = missing (check mode)
  2 = usage error
USAGE
}

story_id="${1:-}"
[[ -n "$story_id" ]] || { usage >&2; exit 2; }
shift || true

mode="check"
output_path=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --check) mode="check"; shift ;;
    --scaffold) mode="scaffold"; shift ;;
    --output) output_path="${2:-}"; [[ -n "$output_path" ]] || { echo "ERROR: --output requires a path" >&2; exit 2; }; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown argument: $1" >&2; usage >&2; exit 2 ;;
  esac
done

if [[ ! "$story_id" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]]; then
  echo "ERROR: invalid STORY_ID '$story_id'" >&2
  exit 2
fi

repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "ERROR: not in a git repo" >&2
  exit 2
}
cd "$repo_root"

slice_id="${story_id%%-*}"
if [[ -z "$slice_id" || "$slice_id" == "$story_id" ]]; then
  if command -v jq >/dev/null 2>&1 && [[ -f "plans/prd.json" ]]; then
    slice_num="$(jq -r --arg sid "$story_id" '.items[] | select(.id == $sid) | .slice // empty' plans/prd.json 2>/dev/null | head -1 || true)"
    if [[ -n "$slice_num" ]]; then
      slice_id="S${slice_num}"
    fi
  fi
fi

candidate_paths=(
  "artifacts/story/${story_id}/${story_id}_reconciliation.md"
  "artifacts/story/${story_id}/${story_id}_reconciliation.json"
  "artifacts/story/${story_id}/evidence_ledger.json"
  "artifacts/story/${story_id}/evidence_ledger.md"
  "artifacts/story/${story_id}/preflight/audit.md"
  "reviews/reconciliations/${slice_id}/${story_id}_reconciliation.md"
  "reviews/reconciliations/${slice_id}/${story_id}_reconciliation.json"
)

found_path=""
for p in "${candidate_paths[@]}"; do
  if [[ -f "$p" ]]; then
    found_path="$p"
    break
  fi
done

if [[ "$mode" == "check" ]]; then
  if [[ -n "$found_path" ]]; then
    echo "OK: evidence ledger found for $story_id at $found_path"
    exit 0
  fi
  echo "FAIL: no evidence ledger found for $story_id" >&2
  echo "Expected one of:" >&2
  for p in "${candidate_paths[@]}"; do
    echo "  - $p" >&2
  done
  echo "Scaffold command:" >&2
  echo "  plans/recon_evidence_ledger.sh $story_id --scaffold" >&2
  exit 1
fi

# --scaffold mode
if [[ -n "$found_path" ]]; then
  echo "OK: evidence ledger already exists for $story_id at $found_path"
  exit 0
fi

if [[ -z "$output_path" ]]; then
  output_path="reviews/reconciliations/${slice_id}/${story_id}_reconciliation.md"
fi

mkdir -p "$(dirname "$output_path")"

cat > "$output_path" <<EOF
# ${story_id} Reconciliation Evidence Ledger

Review basis: STORY_SCOPE (Cycle 1)
Story: ${story_id}
Status: PARTIAL

## AT Verdicts

| AT | Verdict | Enforcement | Test | Notes |
|----|---------|-------------|------|-------|
| AT-UNKNOWN | CLAIMED_NOT_PROVEN | file:line::fn | file:line::test_fn | Replace with real evidence before cycle1 |

## Gaps

- GAP-${story_id}-1 (P1): Replace with evidence-backed gap list entry.
EOF

echo "OK: scaffolded evidence ledger at $output_path"
exit 0
