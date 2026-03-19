#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT"

# --- Hotfix branch exemption ---
# Hotfix branches are exempt from obsidian ceremony.
current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
case "$current_branch" in
  hotfix/*|hot-fix/*|fix/*)
    exit 0
    ;;
esac

# --- Review-fix mode ---
# On an already-reviewed branch, relax ceremony for follow-up commits.
# Set OBSIDIAN_REVIEW_FIX=1 or detect automatically if the branch has
# a code_review_expert attestation from a prior commit.
review_fix_mode="${OBSIDIAN_REVIEW_FIX:-0}"

# --- Amend detection ---
# When amending, the parent commit's obsidian state counts.
is_amend=0
if [[ "${GIT_REFLOG_ACTION:-}" == *"amend"* ]] || [[ "${OBSIDIAN_AMEND:-0}" == "1" ]]; then
  is_amend=1
fi

# --- Diff-size tier ---
# Computed by pre-commit and passed via env; default to full gauntlet.
# Tiers: trivial (<10 lines, formatting/docs only), light (<50 lines, no crates/),
#         full (everything else).
commit_tier="${OBSIDIAN_COMMIT_TIER:-full}"

# Trivial tier: skip obsidian gate entirely
if [[ "$commit_tier" == "trivial" ]]; then
  exit 0
fi

# --- Collect staged obsidian files ---
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

# --- Helper: check if recent commits on this branch already have obsidian files ---
recent_has_obsidian() {
  local kind="$1"  # "Projects" or "Debriefs"
  local lookback="${2:-3}"
  local base_ref=""

  # Find merge-base with origin/main to avoid searching past branch point
  base_ref="$(git merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -z "$base_ref" ]]; then
    base_ref="HEAD~${lookback}"
  fi

  local count=0
  while IFS= read -r sha; do
    if git diff-tree --no-commit-id --name-only -r "$sha" -- "obsidian/${kind}" 2>/dev/null | grep -q "\.md$"; then
      return 0
    fi
    count=$((count + 1))
    [[ $count -lt $lookback ]] || break
  done < <(git log --format='%H' "${base_ref}..HEAD" 2>/dev/null)

  return 1
}

# --- Project note check ---
if [[ ${#project_files[@]} -eq 0 ]]; then
  # Amend: parent commit already has project note → pass
  if [[ $is_amend -eq 1 ]]; then
    if git diff-tree --no-commit-id --name-only -r HEAD -- obsidian/Projects 2>/dev/null | grep -q '\.md$'; then
      # Inherit project file from parent commit for downstream checks
      while IFS= read -r path; do
        project_files+=("$path")
      done < <(git diff-tree --no-commit-id --name-only -r HEAD -- obsidian/Projects 2>/dev/null | grep '\.md$')
    fi
  fi

  # Review-fix mode: recent commit on this branch has project note → pass
  if [[ ${#project_files[@]} -eq 0 && "$review_fix_mode" == "1" ]]; then
    if recent_has_obsidian "Projects" 3; then
      # Use the most recent project file from git log
      recent_project="$(git log --diff-filter=ACMR --name-only --format='' -3 -- 'obsidian/Projects/*.md' 2>/dev/null | head -1 || true)"
      if [[ -n "$recent_project" ]]; then
        project_files+=("$recent_project")
      fi
    fi
  fi

  # Light tier: recent project note within 5 commits → pass
  if [[ ${#project_files[@]} -eq 0 && "$commit_tier" == "light" ]]; then
    if recent_has_obsidian "Projects" 5; then
      recent_project="$(git log --diff-filter=ACMR --name-only --format='' -5 -- 'obsidian/Projects/*.md' 2>/dev/null | head -1 || true)"
      if [[ -n "$recent_project" ]]; then
        project_files+=("$recent_project")
      fi
    fi
  fi
fi

if [[ ${#project_files[@]} -eq 0 ]]; then
  cat >&2 <<'EOF'
ERROR: No staged Obsidian project note.

Before committing, stage an update to the relevant file under `obsidian/Projects/`.
Only include the changes you made in this commit.

Bypass for follow-up commits on a reviewed branch:
  OBSIDIAN_REVIEW_FIX=1 git commit ...
EOF
  exit 1
fi

# --- Debrief check ---
if [[ ${#debrief_files[@]} -eq 0 ]]; then
  skip_debrief=0

  # Amend: parent commit already has debrief → pass
  if [[ $is_amend -eq 1 ]]; then
    if git diff-tree --no-commit-id --name-only -r HEAD -- obsidian/Debriefs 2>/dev/null | grep -q '\.md$'; then
      skip_debrief=1
    fi
  fi

  # Review-fix mode: recent commit has debrief → pass
  if [[ $skip_debrief -eq 0 && "$review_fix_mode" == "1" ]]; then
    if recent_has_obsidian "Debriefs" 3; then
      skip_debrief=1
    fi
  fi

  # Light tier: recent debrief within 5 commits → pass
  if [[ $skip_debrief -eq 0 && "$commit_tier" == "light" ]]; then
    if recent_has_obsidian "Debriefs" 5; then
      skip_debrief=1
    fi
  fi

  if [[ $skip_debrief -eq 0 ]]; then
    cat >&2 <<'EOF'
ERROR: No staged Obsidian debrief.

Before committing, stage a debrief under `obsidian/Debriefs/` and link it from the project's `## Debriefs` section.
Only include the changes you made in this commit.

Bypass for follow-up commits on a reviewed branch:
  OBSIDIAN_REVIEW_FIX=1 git commit ...
EOF
    exit 1
  fi
fi

# --- Single project check (only when project files are freshly staged) ---
staged_project_count=0
while IFS= read -r -d '' path; do
  case "$path" in
    obsidian/Projects/*.md) staged_project_count=$((staged_project_count + 1)) ;;
  esac
done < <(git diff --cached --name-only -z --diff-filter=ACMR -- obsidian/Projects)

if [[ $staged_project_count -gt 1 ]]; then
  cat >&2 <<EOF
ERROR: Stage Obsidian files for exactly one project note per commit.

Staged project notes:
$(git diff --cached --name-only --diff-filter=ACMR -- obsidian/Projects | sed 's/^/  - /')
Only include the changes you made in this commit.
EOF
  exit 1
fi

# --- Cross-reference checks (only when both are freshly staged) ---
if [[ $staged_project_count -gt 0 && ${#debrief_files[@]} -gt 0 ]]; then
  expected_project_name="$(basename "${project_files[0]}" .md)"

  for debrief_file in "${debrief_files[@]}"; do
    debrief_content="$(git show ":$debrief_file")"
    debrief_project_ref="$(printf '%s\n' "$debrief_content" | sed -n 's/^project:[[:space:]]*//p' | head -1)"
    debrief_project_ref="${debrief_project_ref#\"}"
    debrief_project_ref="${debrief_project_ref%\"}"
    debrief_project_name=""

    case "$debrief_project_ref" in
      \[\[*\]\])
        debrief_project_name="${debrief_project_ref#\[\[}"
        debrief_project_name="${debrief_project_name%\]\]}"
        ;;
    esac

    if [[ -z "$debrief_project_name" ]]; then
      cat >&2 <<EOF
ERROR: Each staged Obsidian debrief must declare its project in frontmatter.

Missing or invalid project frontmatter:
  - $debrief_file
Only include the changes you made in this commit.
EOF
      exit 1
    fi

    if [[ "$debrief_project_name" != "$expected_project_name" ]]; then
      cat >&2 <<EOF
ERROR: A staged Obsidian debrief belongs to a different project than ${project_files[0]}.

Expected project: $expected_project_name
Mismatched staged debrief:
  - $debrief_file -> $debrief_project_name
Only include the changes you made in this commit.
EOF
      exit 1
    fi
  done

  # Verify debrief is linked from project note
  for pf in "${project_files[@]}"; do
    project_content="$(git show ":$pf" 2>/dev/null || cat "$pf")"
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
ERROR: $pf must link at least one staged debrief.

Add a reference under \`## Debriefs\` to one of:
$(printf '  - %s\n' "${debrief_files[@]}")
Only include the changes you made in this commit.
EOF
      exit 1
    fi
  done
fi
