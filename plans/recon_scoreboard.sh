#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: plans/recon_scoreboard.sh <SLICE_ID> [extra args]

Generates:
  reviews/reconciliations/<SLICE_ID>/SCOREBOARD.md
  reviews/reconciliations/<SLICE_ID>/SCOREBOARD.json
EOF
}

if [[ $# -lt 1 ]]; then
  usage >&2
  exit 2
fi

SLICE_ID="$1"
shift

if [[ ! "$SLICE_ID" =~ ^[Ss]?[0-9]+$ ]]; then
  echo "ERROR: invalid slice id '$SLICE_ID' (expected N or SN)" >&2
  exit 2
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT_DIR="$ROOT/reviews/reconciliations/$SLICE_ID"
OUT_MD="$OUT_DIR/SCOREBOARD.md"
OUT_JSON="$OUT_DIR/SCOREBOARD.json"

mkdir -p "$OUT_DIR"

python3 "$ROOT/plans/recon_scoreboard.py" \
  --slice "$SLICE_ID" \
  --out-md "$OUT_MD" \
  --out-json "$OUT_JSON" \
  "$@"
