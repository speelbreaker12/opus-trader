#!/usr/bin/env bash
set -euo pipefail

# Aggregate reviewer proof graphs into a merged base graph.
#
# Discovers per-reviewer proof_graph.json files under
# artifacts/story/<STORY_ID>/<tool>/, merges them via aggregate.py
# (fail-closed, strictest verdict wins), then validates the result.
# The base graph is overwritten only after successful validation (atomic),
# EXCEPT on trading halt (exit 20) where the merged graph is still written
# for forensic inspectability — the non-zero exit code is the fail-closed signal.
#
# NOTE: head_sha in the base graph is set by init.py at skeleton creation time.
# If the repo HEAD advances between init and aggregation, the graph's head_sha
# will be stale. This is acceptable: the graph captures evidence at review time,
# not at aggregation time. A future --refresh-sha flag could update it if needed.
#
# Usage:
#   plans/aggregate_proofs.sh <STORY_ID>

STORY_ID="${1:?Usage: aggregate_proofs.sh <STORY_ID>}"
# SCRIPT_ROOT: always the real repo root (for python scripts, specs, plans)
SCRIPT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# STORY_ARTIFACTS_ROOT: explicit story artifacts base override (used by review harnesses).
# AGGREGATE_ROOT: legacy repo-like root override for tests when artifacts live under artifacts/story/.
ARTIFACTS_ROOT="${STORY_ARTIFACTS_ROOT:-}"
if [[ -n "$ARTIFACTS_ROOT" ]]; then
  case "$ARTIFACTS_ROOT" in
    /*) ;;
    *) ARTIFACTS_ROOT="$SCRIPT_ROOT/$ARTIFACTS_ROOT" ;;
  esac
else
  ROOT="${AGGREGATE_ROOT:-$SCRIPT_ROOT}"
  case "$ROOT" in
    /*) ;;
    *) ROOT="$SCRIPT_ROOT/$ROOT" ;;
  esac
  ARTIFACTS_ROOT="$ROOT/artifacts/story"
fi
BASE="$ARTIFACTS_ROOT/$STORY_ID/proof_graph.json"

# Detect python binary (prefers python3; verify_utils.sh ensure_python prefers python)
if command -v python3 >/dev/null 2>&1; then
  PY=python3
elif command -v python >/dev/null 2>&1; then
  PY=python
else
  echo "ERROR: python3 or python not found" >&2; exit 1
fi

# Known reviewer tool names (prevents accidental aggregation of non-reviewer dirs).
# Keep in sync with the tool case-statement in review_logged.sh (~line 232).
KNOWN_TOOLS="codex opus kimi gemini"

# Guard: base must exist (init.py must have been run)
if [[ ! -f "$BASE" ]]; then
  echo "ERROR: Base proof_graph.json not found at $BASE" >&2
  echo "Run: python3 python/proof_graph/init.py $STORY_ID --output-dir $ARTIFACTS_ROOT/$STORY_ID/" >&2
  exit 1
fi

# Discover reviewer graphs (full ProofGraph format from init.py, not fragments)
# Only known tool directories are included to avoid merging stray proof_graph.json
# files from e.g. self_review/, premortem/, or other non-reviewer subdirectories.
REVIEWS=()
LABELS=()
for dir in "$ARTIFACTS_ROOT"/"$STORY_ID"/*/; do
  [[ -d "$dir" ]] || continue
  tool="$(basename "$dir")"
  # Filter to known reviewer tools
  if ! echo "$KNOWN_TOOLS" | grep -qw "$tool"; then
    continue
  fi
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
  # TODO: Add --require-min-reviewers N flag for CI enforcement when adoption matures.
fi

# Aggregate: strictest verdict wins (fail-closed)
# Write to temp file first to avoid corrupting the base on failure.
MERGED_TMP="${BASE}.merged.tmp"
trap 'rm -f "$MERGED_TMP"' EXIT

"$PY" "$SCRIPT_ROOT/python/proof_graph/aggregate.py" \
  --base "$BASE" \
  --reviews "${REVIEWS[@]}" \
  --labels "${LABELS[@]}" \
  --output "$MERGED_TMP"

# Validate merged result before committing the write
echo "Running validate.py --strict on merged graph..."
set +e
"$PY" "$SCRIPT_ROOT/python/proof_graph/validate.py" "$MERGED_TMP" \
  --contract-path "$SCRIPT_ROOT/specs/CONTRACT.md" \
  --prd-path "$SCRIPT_ROOT/plans/prd.json" \
  --strict
rc=$?
set -e

if [[ $rc -eq 0 ]]; then
  # Validation passed — atomically replace base with merged result
  mv "$MERGED_TMP" "$BASE"
  echo "Aggregated ${#REVIEWS[@]} reviewer graphs into $BASE"
elif [[ $rc -eq 20 ]]; then
  echo "CRITICAL: Trading halt triggered on $STORY_ID" >&2
  # Still commit the merge so the graph is inspectable (exit 20 is the fail signal)
  mv "$MERGED_TMP" "$BASE"
  echo "Aggregated ${#REVIEWS[@]} reviewer graphs into $BASE (TRADING HALT)"
else
  echo "ERROR: Proof graph validation failed (exit $rc). Base graph unchanged." >&2
  # MERGED_TMP is cleaned up by trap
fi
exit $rc
