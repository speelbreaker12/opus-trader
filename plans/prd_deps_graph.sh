#!/usr/bin/env bash
# =============================================================================
# plans/prd_deps_graph.sh
# Purpose: Generate a DOT graph visualization of PRD item dependencies
# Usage: ./plans/prd_deps_graph.sh [prd.json] [output.dot]
# =============================================================================

set -euo pipefail

PRD_FILE="${1:-plans/prd.json}"
OUTPUT_FILE="${2:-.ralph/deps_graph.dot}"

if [[ ! -f "$PRD_FILE" ]]; then
  echo "ERROR: PRD file not found: $PRD_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR: jq is required but not found" >&2
  exit 1
fi

mkdir -p "$(dirname "$OUTPUT_FILE")"

# Generate DOT graph
jq -r '
  # Header
  "digraph PRD_Dependencies {",
  "  rankdir=TB;",
  "  node [shape=box, style=filled];",
  "",
  # Group nodes by slice
  (.items | group_by(.slice) | .[] |
    "  subgraph cluster_slice_\(.[0].slice) {" ,
    "    label=\"Slice \(.[0].slice)\";",
    "    style=dashed;",
    (.[] |
      if .passes == true then
        "    \"\(.id)\" [fillcolor=lightgreen, label=\"\(.id)\\n\(.description | .[0:30])...\"];"
      elif .needs_human_decision == true then
        "    \"\(.id)\" [fillcolor=yellow, label=\"\(.id)\\n[BLOCKED]\"];"
      else
        "    \"\(.id)\" [fillcolor=lightblue, label=\"\(.id)\\n\(.description | .[0:30])...\"];"
      end
    ),
    "  }",
    ""
  ),
  # Edges for dependencies
  (.items[] |
    .id as $id |
    (.dependencies // [])[] |
    "  \"\(.)\" -> \"\($id)\";"
  ),
  "",
  # Legend
  "  subgraph cluster_legend {",
  "    label=\"Legend\";",
  "    style=solid;",
  "    legend_pass [fillcolor=lightgreen, label=\"Passed\"];",
  "    legend_pending [fillcolor=lightblue, label=\"Pending\"];",
  "    legend_blocked [fillcolor=yellow, label=\"Blocked\"];",
  "  }",
  "}"
' "$PRD_FILE" > "$OUTPUT_FILE"

echo "Generated dependency graph: $OUTPUT_FILE"
echo ""
echo "To render as PNG (requires graphviz):"
echo "  dot -Tpng $OUTPUT_FILE -o ${OUTPUT_FILE%.dot}.png"
echo ""
echo "To render as SVG:"
echo "  dot -Tsvg $OUTPUT_FILE -o ${OUTPUT_FILE%.dot}.svg"
