#!/usr/bin/env bash
# UserPromptSubmit hook: Read active Obsidian project files to give agent context
# Reads all .md files in obsidian/Projects/ (skips archive/)

PROJECTS_DIR="obsidian/Projects"

if [ ! -d "$PROJECTS_DIR" ]; then
    exit 0
fi

# Find active project files (not in archive)
FILES=$(find "$PROJECTS_DIR" -maxdepth 1 -name '*.md' -type f 2>/dev/null | sort)

if [ -z "$FILES" ]; then
    exit 0
fi

echo "OBSIDIAN PROJECT CONTEXT — Active projects:"
echo ""

while IFS= read -r f; do
    NAME=$(basename "$f" .md)
    # Extract frontmatter fields
    STATUS=$(sed -n 's/^status: *//p' "$f" | head -1)
    PRIORITY=$(sed -n 's/^priority: *//p' "$f" | head -1)
    BRANCH=$(sed -n 's/^branch: *//p' "$f" | head -1)
    # Extract Current State section (first paragraph after ## Current State)
    STATE=$(awk '/^## Current State/{found=1; next} found && /^##/{exit} found && NF{print; exit}' "$f")

    echo "- [$PRIORITY] $NAME ($STATUS) — $STATE"
done <<< "$FILES"

DEBRIEFS_DIR="obsidian/Debriefs"
RECENT=$(find "$DEBRIEFS_DIR" -maxdepth 1 -name '*.md' -type f -mtime -3 2>/dev/null | sort -r | head -3)
if [ -n "$RECENT" ]; then
    echo ""
    echo "Recent debriefs (last 3 days):"
    while IFS= read -r d; do
        DNAME=$(basename "$d" .md)
        CONSTRAINT=$(awk '/^## 1\) Constraint/{found=1; next} found && /^##/{exit} found && /^- How it manifested/{print; exit}' "$d")
        echo "  - $DNAME${CONSTRAINT:+ — $CONSTRAINT}"
    done <<< "$RECENT"
fi

echo ""
echo "Full project files: obsidian/Projects/*.md"
echo "Update the relevant project file when making progress on any of these."
