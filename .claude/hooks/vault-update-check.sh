#!/usr/bin/env bash
# Block commit or push if the external Obsidian vault project page is stale.
# Hard gate — exit 2 blocks the tool call.

INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//' 2>/dev/null || true)"
if [[ -z "$COMMAND" ]]; then
  COMMAND="$(echo "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("command",""))' 2>/dev/null || true)"
fi

# Only check on git commit or git push
IS_COMMIT=false
IS_PUSH=false
echo "$COMMAND" | grep -qE '\bgit\s+commit\b' && IS_COMMIT=true
echo "$COMMAND" | grep -qE '\bgit\s+push\b' && IS_PUSH=true
$IS_COMMIT || $IS_PUSH || exit 0

VAULT="${OBSIDIAN_VAULT_PATH:-$HOME/Desktop/obsidian}"
ACTIVE_FILE="$VAULT/index/ACTIVE_PROJECT.md"

# If no active project pointer, skip (no project to enforce)
[ -f "$ACTIVE_FILE" ] || exit 0

# Extract project name from wikilink: [[projects/Foo Bar]] -> Foo Bar
PROJECT_NAME="$(sed -n 's/.*\[\[projects\/\(.*\)\]\].*/\1/p' "$ACTIVE_FILE" | head -1)"
[ -n "$PROJECT_NAME" ] || exit 0

PROJECT_FILE="$VAULT/projects/${PROJECT_NAME}.md"
[ -f "$PROJECT_FILE" ] || exit 0

# Check if project file was modified today
TODAY="$(date +%Y-%m-%d)"
FILE_DATE="$(stat -f '%Sm' -t '%Y-%m-%d' "$PROJECT_FILE" 2>/dev/null || stat -c '%y' "$PROJECT_FILE" 2>/dev/null | cut -d' ' -f1)"

if [[ "$FILE_DATE" != "$TODAY" ]]; then
  if $IS_COMMIT; then
    ACTION="committing"
    HINT="Update ## Log and ## Commits in the project page, then retry."
  else
    ACTION="pushing"
    HINT="Update ## Log, ## Commits, and ## Current State in the project page, then retry."
  fi
  echo ""
  echo "BLOCKED: Obsidian project page not updated today."
  echo "  Project: $PROJECT_NAME"
  echo "  File:    $PROJECT_FILE"
  echo "  Last modified: $FILE_DATE"
  echo ""
  echo "  You are $ACTION but the project page is stale."
  echo "  $HINT"
  echo ""
  exit 2
fi

exit 0
