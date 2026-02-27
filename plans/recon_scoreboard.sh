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
BASE_OUT_DIR="$ROOT/reviews/reconciliations"
OUT_DIR="$BASE_OUT_DIR/$SLICE_ID"
RESOLVED_OUT_DIR="$(
  python3 - "$BASE_OUT_DIR" "$OUT_DIR" <<'PY'
from pathlib import Path
import sys

base = Path(sys.argv[1]).resolve()
out = Path(sys.argv[2]).resolve()
try:
    out.relative_to(base)
except ValueError:
    raise SystemExit(1)
print(out)
PY
)" || {
  echo "ERROR: resolved output dir escapes reviews/reconciliations: $OUT_DIR" >&2
  exit 2
}
OUT_DIR="$RESOLVED_OUT_DIR"
OUT_MD="$OUT_DIR/SCOREBOARD.md"
OUT_JSON="$OUT_DIR/SCOREBOARD.json"

mkdir -p "$OUT_DIR"

python3 "$ROOT/plans/recon_scoreboard.py" \
  --slice "$SLICE_ID" \
  --out-md "$OUT_MD" \
  --out-json "$OUT_JSON" \
  "$@"
