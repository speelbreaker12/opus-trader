#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT_PATH=""
DECISION="BLOCKED"
STORY_ID="VERIFY_FULL"
CONFIDENCE="low"
REQUESTED_MARK_PASS_ID=""
ALLOW_PASS_DECISION=0

usage() {
  cat <<'USAGE'
Usage: plans/contract_review_emit.sh --out <path> [options]

Options:
  --out <path>                 Required output JSON path.
  --decision PASS|FAIL|BLOCKED Decision to emit (default: BLOCKED).
  --allow-pass-decision        Required when --decision PASS is used.
  --story-id <id>              selected_story_id value (default: VERIFY_FULL).
  --requested-pass-id <id>     pass_flip_check.requested_mark_pass_id
                               (default: same as --story-id).
  -h, --help                   Show this help.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      [[ $# -ge 2 ]] || { echo "FAIL: --out requires a path" >&2; exit 2; }
      OUT_PATH="$2"
      shift 2
      ;;
    --out=*)
      OUT_PATH="${1#*=}"
      shift
      ;;
    --decision)
      [[ $# -ge 2 ]] || { echo "FAIL: --decision requires PASS|FAIL|BLOCKED" >&2; exit 2; }
      DECISION="$2"
      shift 2
      ;;
    --decision=*)
      DECISION="${1#*=}"
      shift
      ;;
    --allow-pass-decision)
      ALLOW_PASS_DECISION=1
      shift
      ;;
    --story-id)
      [[ $# -ge 2 ]] || { echo "FAIL: --story-id requires a value" >&2; exit 2; }
      STORY_ID="$2"
      shift 2
      ;;
    --story-id=*)
      STORY_ID="${1#*=}"
      shift
      ;;
    --requested-pass-id)
      [[ $# -ge 2 ]] || { echo "FAIL: --requested-pass-id requires a value" >&2; exit 2; }
      REQUESTED_MARK_PASS_ID="$2"
      shift 2
      ;;
    --requested-pass-id=*)
      REQUESTED_MARK_PASS_ID="${1#*=}"
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "FAIL: unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUT_PATH" ]]; then
  echo "FAIL: missing required --out <path>" >&2
  usage >&2
  exit 2
fi

if [[ -z "$STORY_ID" ]]; then
  echo "FAIL: --story-id must be non-empty" >&2
  exit 2
fi

case "$DECISION" in
  PASS|FAIL|BLOCKED) ;;
  *)
    echo "FAIL: invalid decision '$DECISION' (expected PASS|FAIL|BLOCKED)" >&2
    exit 2
    ;;
esac

if [[ "$DECISION" == "PASS" && "$ALLOW_PASS_DECISION" -ne 1 ]]; then
  echo "FAIL: decision PASS requires --allow-pass-decision" >&2
  exit 2
fi

if [[ -z "$REQUESTED_MARK_PASS_ID" ]]; then
  REQUESTED_MARK_PASS_ID="$STORY_ID"
fi

if [[ -z "$REQUESTED_MARK_PASS_ID" ]]; then
  echo "FAIL: --requested-pass-id resolved to empty value" >&2
  exit 2
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "FAIL: jq is required but not found" >&2
  exit 2
fi

if [[ ! -x "./plans/contract_review_validate.sh" ]]; then
  echo "FAIL: missing executable validator: ./plans/contract_review_validate.sh" >&2
  exit 2
fi

PASS_FLIP_DECISION="BLOCKED"
VERIFY_POST_PRESENT="false"
VERIFY_POST_GREEN="false"
RATIONALE="Auto-seeded BLOCKED contract review artifact for verify full."
SCOPE_NOTE="Auto-seeded during verify full."
VERIFY_NOTE="Seed artifact generated before full gate completion."

case "$DECISION" in
  PASS)
    PASS_FLIP_DECISION="ALLOW"
    VERIFY_POST_PRESENT="true"
    VERIFY_POST_GREEN="true"
    RATIONALE="Contract review emitted with explicit PASS decision override."
    ;;
  FAIL)
    PASS_FLIP_DECISION="DENY"
    RATIONALE="Contract review emitted with explicit FAIL decision override."
    ;;
  BLOCKED)
    PASS_FLIP_DECISION="BLOCKED"
    ;;
esac

mkdir -p "$(dirname "$OUT_PATH")"
tmp_out="$(mktemp)"

jq -n \
  --arg story_id "$STORY_ID" \
  --arg decision "$DECISION" \
  --arg confidence "$CONFIDENCE" \
  --arg requested_mark_pass_id "$REQUESTED_MARK_PASS_ID" \
  --arg pass_flip_decision "$PASS_FLIP_DECISION" \
  --arg rationale "$RATIONALE" \
  --arg scope_note "$SCOPE_NOTE" \
  --arg verify_note "$VERIFY_NOTE" \
  --argjson verify_post_present "$VERIFY_POST_PRESENT" \
  --argjson verify_post_green "$VERIFY_POST_GREEN" \
  '
  {
    selected_story_id: $story_id,
    decision: $decision,
    confidence: $confidence,
    contract_refs_checked: ["WORKFLOW_CONTRACT:7.4", "WORKFLOW_CONTRACT:8.1"],
    scope_check: {
      changed_files: [],
      out_of_scope_files: [],
      notes: [$scope_note]
    },
    verify_check: {
      verify_post_present: $verify_post_present,
      verify_post_green: $verify_post_green,
      notes: [$verify_note]
    },
    pass_flip_check: {
      requested_mark_pass_id: $requested_mark_pass_id,
      prd_passes_before: false,
      prd_passes_after: false,
      evidence_required: [],
      evidence_found: [],
      evidence_missing: [],
      decision_on_pass_flip: $pass_flip_decision
    },
    violations: [],
    required_followups: (
      if $decision == "PASS" then
        []
      elif $decision == "FAIL" then
        ["Resolve contract issues before requesting pass flip."]
      else
        ["Replace seeded BLOCKED contract review with human-reviewed verdict before pass flip."]
      end
    ),
    rationale: [$rationale]
  }
  ' > "$tmp_out"

if ! ./plans/contract_review_validate.sh "$tmp_out" >/dev/null 2>&1; then
  rm -f "$tmp_out"
  echo "FAIL: emitted contract review failed validation" >&2
  exit 1
fi

mv "$tmp_out" "$OUT_PATH"
echo "OK: contract review emitted ($OUT_PATH decision=$DECISION story_id=$STORY_ID)"
