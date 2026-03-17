#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

project_files=()
debrief_files=()

while IFS= read -r -d '' path; do
  case "$path" in
    obsidian/Projects/*.md)
      project_files+=("$path")
      ;;
    obsidian/Debriefs/*.md)
      debrief_files+=("$path")
      ;;
  esac
done < <(git diff --cached --name-only -z --diff-filter=ACMR -- obsidian/Projects obsidian/Debriefs)

if [[ ${#project_files[@]} -eq 0 ]]; then
  cat >&2 <<'EOF'
ERROR: No staged Obsidian project note.

Before committing, stage an update to the relevant file under `obsidian/Projects/`.
EOF
  exit 1
fi

if [[ ${#debrief_files[@]} -eq 0 ]]; then
  cat >&2 <<'EOF'
ERROR: No staged Obsidian debrief.

Before committing, stage a debrief under `obsidian/Debriefs/` and link it from the project's `## Debriefs` section.
EOF
  exit 1
fi

for project_file in "${project_files[@]}"; do
  project_content="$(git show ":$project_file")"
  debrief_section="$(printf '%s\n' "$project_content" | awk '
    /^## Debriefs[[:space:]]*$/ { in_section=1; next }
    /^## / { if (in_section) exit }
    in_section { print }
  ')"
  linked=0

  for debrief_file in "${debrief_files[@]}"; do
    debrief_name="$(basename "$debrief_file" .md)"
    if printf '%s\n' "$debrief_section" | grep -Fq "$debrief_name"; then
      linked=1
      break
    fi
  done

  if [[ $linked -ne 1 ]]; then
    cat >&2 <<EOF
ERROR: $project_file must link at least one staged debrief.

Add a reference under \`## Debriefs\` to one of:
$(printf '  - %s\n' "${debrief_files[@]}")
EOF
    exit 1
  fi
done
