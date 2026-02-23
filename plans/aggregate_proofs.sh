#!/usr/bin/env bash
set -euo pipefail

# Aggregate reviewer proof graphs into a merged base graph.
#
# Discovers per-reviewer proof_graph.json files under
# artifacts/story/<STORY_ID>/<tool>/, merges them via aggregate.py
# (fail-closed, strictest verdict wins), then validates the result.
#
# Usage:
#   plans/aggregate_proofs.sh <STORY_ID>

STORY_ID="${1:?Usage: aggregate_proofs.sh <STORY_ID>}"
# SCRIPT_ROOT: always the real repo root (for python scripts, specs, plans)
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# AGGREGATE_ROOT: overridable for tests (artifact paths only)
ROOT="${AGGREGATE_ROOT:-$SCRIPT_ROOT}"
BASE="$ROOT/artifacts/story/$STORY_ID/proof_graph.json"

# Guard: base must exist (init.py must have been run)
if [[ ! -f "$BASE" ]]; then
  echo "ERROR: Base proof_graph.json not found at $BASE" >&2
  echo "Run: python3 python/proof_graph/init.py $STORY_ID" >&2
  exit 1
fi

# Discover reviewer graphs (full ProofGraph format from init.py, not fragments)
REVIEWS=()
LABELS=()
for dir in "$ROOT"/artifacts/story/"$STORY_ID"/*/; do
  [[ -d "$dir" ]] || continue
  tool="$(basename "$dir")"
  pg="$dir/proof_graph.json"
  if [[ -f "$pg" ]]; then
    REVIEWS+=("$pg")
    LABELS+=("$tool")
  fi
done

if [[ ${#REVIEWS[@]} -eq 0 ]]; then
  echo "WARN: No reviewer proof_graph.json files found. Skipping aggregation." >&2
  echo "Base graph at $BASE is unchanged." >&2
  exit 0  # Not an error — reviews may not have used --proof-graph
fi

if [[ ${#REVIEWS[@]} -eq 1 ]]; then
  echo "WARN: Only 1 reviewer graph found (${LABELS[0]}). Single-reviewer aggregation has no corroboration." >&2
fi

# Aggregate: strictest verdict wins (fail-closed)
python3 "$SCRIPT_ROOT/python/proof_graph/aggregate.py" \
  --base "$BASE" \
  --reviews "${REVIEWS[@]}" \
  --labels "${LABELS[@]}" \
  --output "$BASE"  # Overwrites base with merged result

echo "Aggregated ${#REVIEWS[@]} reviewer graphs into $BASE"

# Validate merged result
echo "Running validate.py --strict on merged graph..."
set +e
python3 "$SCRIPT_ROOT/python/proof_graph/validate.py" "$BASE" \
  --contract-path "$ROOT/specs/CONTRACT.md" \
  --prd-path "$ROOT/plans/prd.json" \
  --strict
rc=$?
set -e

if [[ $rc -eq 20 ]]; then
  echo "CRITICAL: Trading halt triggered on $STORY_ID" >&2
elif [[ $rc -ne 0 ]]; then
  echo "ERROR: Proof graph validation failed (exit $rc)" >&2
fi
exit $rc
