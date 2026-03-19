#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ "${CODE_REVIEW_EXPERT_GUARD:-1}" != "1" ]]; then
  exit 0
fi

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required for code-review-expert guard" >&2
  exit 2
fi

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -z "$git_dir" ]]; then
  echo "ERROR: code-review-expert guard requires a git repository" >&2
  exit 2
fi

staged_files="$(git diff --cached --name-only --diff-filter=ACMRTUXB)"
if [[ -z "$staged_files" ]]; then
  exit 0
fi

is_significant_path() {
  local path="$1"

  case "$path" in
    docs/*|reviews/*|artifacts/*|tests/*|plans/tests/*|*.md|*.txt|*.json)
      return 1
      ;;
  esac

  case "$path" in
    crates/*|python/*|dashboard/*|scripts/*|tools/*|.githooks/*|plans/*.sh|plans/lib/*.sh|plans/*.py)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

significant_files=()
while IFS= read -r path; do
  [[ -n "$path" ]] || continue
  if is_significant_path "$path"; then
    significant_files+=("$path")
  fi
done <<< "$staged_files"

if [[ "${#significant_files[@]}" -eq 0 ]]; then
  exit 0
fi

# Skip reasons for mechanical changes (advisory, not blocking)
skip_reason="${SKIP_CODE_REVIEW_REASON:-}"
if [[ -n "$skip_reason" ]]; then
  echo "INFO: code-review-expert guard skipped (reason: $skip_reason)" >&2
  exit 0
fi

if [[ "${SKIP_CODE_REVIEW_EXPERT_HOOK:-0}" == "1" ]]; then
  echo "WARN: SKIP_CODE_REVIEW_EXPERT_HOOK=1, bypassing code-review-expert guard" >&2
  exit 0
fi

# Auto-detect mechanical changes: all significant files are formatting-only
all_fmt_only=1
for path in "${significant_files[@]}"; do
  # Check if staged diff is whitespace/formatting only
  if git diff --cached --ignore-all-space --ignore-blank-lines "$path" | grep -qE '^[+-].*[a-zA-Z]'; then
    all_fmt_only=0
    break
  fi
done
if [[ "$all_fmt_only" -eq 1 && "${#significant_files[@]}" -gt 0 ]]; then
  echo "INFO: code-review-expert guard skipped (formatting-only changes)" >&2
  exit 0
fi

attest_file="$git_dir/code_review_expert.attest"
current_tree="$(git write-tree)"
attest_tree=""
if [[ -f "$attest_file" ]]; then
  attest_tree="$(grep '^tree=' "$attest_file" | head -n 1 | cut -d= -f2- || true)"
fi

if [[ -z "$attest_tree" || "$attest_tree" != "$current_tree" ]]; then
  echo "ERROR: missing or stale code-review-expert attestation for significant staged changes." >&2
  echo "Significant staged files:" >&2
  for path in "${significant_files[@]}"; do
    echo "  - $path" >&2
  done
  echo "Required: run code-review-expert review, then attest current index:" >&2
  echo "  ./plans/code_review_expert_attest.sh" >&2
  echo "Emergency bypass (one commit):" >&2
  echo "  SKIP_CODE_REVIEW_EXPERT_HOOK=1 git commit ..." >&2
  exit 1
fi

exit 0
