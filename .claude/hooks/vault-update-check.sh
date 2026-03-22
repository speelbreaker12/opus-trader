#!/usr/bin/env bash
# Warn if pushing without updating the external Obsidian vault project page.
# Soft gate — warns but does not block (exit 0 always).

# Only trigger on git push commands
INPUT="$(cat)"
COMMAND="$(echo "$INPUT" | grep -o '"command":"[^"]*"' | head -1 | sed 's/"command":"//;s/"$//' 2>/dev/null || true)"
if [[ -z "$COMMAND" ]]; then
  COMMAND="$(echo "$INPUT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("command",""))' 2>/dev/null || true)"
fi

# Only check on git push
echo "$COMMAND" | grep -qE '\bgit\s+push\b' || exit 0

VAULT="${OBSIDIAN_VAULT_PATH:-$HOME/Desktop/obsidian}"
ACTIVE_FILE="$VAULT/index/ACTIVE_PROJECT.md"

# If no active project pointer, skip
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
  echo ""
  echo "WARNING: Obsidian project page not updated today."
  echo "  Project: $PROJECT_NAME"
  echo "  File:    $PROJECT_FILE"
  echo "  Last modified: $FILE_DATE"
  echo ""
  echo "  Consider updating ## Log, ## Commits, and ## Current State before pushing."
  echo ""
fi

exit 0
