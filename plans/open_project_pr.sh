#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$ROOT" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT"

[[ -x "$ROOT/plans/project_scope_guard.sh" ]] || {
  echo "ERROR: missing executable scope guard: $ROOT/plans/project_scope_guard.sh" >&2
  exit 1
}

command -v gh >/dev/null 2>&1 || {
  echo "ERROR: gh CLI is required" >&2
  exit 1
}

metadata_json="$("$ROOT/plans/project_scope_guard.sh" metadata)"
eval "$(
  python3 -c '
import json
import shlex
import sys

data = json.loads(sys.argv[1])
for key in ("path", "rel_path", "name", "branch", "base", "pr"):
    value = data.get(key, "")
    print(f"PROJECT_{key.upper()}={shlex.quote(str(value))}")
' "$metadata_json"
)"

"$ROOT/plans/project_scope_guard.sh" pr-create

base_flag_present=0
for arg in "$@"; do
  case "$arg" in
    --base|--base=*)
      base_flag_present=1
      ;;
  esac
done

gh_args=("$@")
if [[ $base_flag_present -eq 0 && -n "$PROJECT_BASE" ]]; then
  gh_args=(--base "$PROJECT_BASE" "${gh_args[@]}")
fi

create_output="$(gh pr create "${gh_args[@]}")"
printf '%s\n' "$create_output"

pr_json="$(gh pr view --json number,headRefName,baseRefName,state)"
eval "$(
  python3 -c '
import json
import shlex
import sys

data = json.loads(sys.argv[1])
pr_number = data.get("number", "")
head_ref = data.get("headRefName", "")
base_ref = data.get("baseRefName", "")
print(f"PR_NUMBER={shlex.quote(str(pr_number))}")
print(f"PR_HEAD_REF={shlex.quote(str(head_ref))}")
print(f"PR_BASE_REF={shlex.quote(str(base_ref))}")
' "$pr_json"
)"

[[ -n "$PR_NUMBER" ]] || {
  echo "ERROR: unable to determine PR number after gh pr create" >&2
  exit 1
}
[[ "$PR_HEAD_REF" == "$PROJECT_BRANCH" ]] || {
  echo "ERROR: created PR head branch '$PR_HEAD_REF' does not match project branch '$PROJECT_BRANCH'" >&2
  exit 1
}

python3 - "$PROJECT_PATH" "$PR_NUMBER" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
pr_number = sys.argv[2]
content = path.read_text(encoding="utf-8")
lines = content.splitlines()
if not lines or lines[0].strip() != "---":
    raise SystemExit("project note is missing frontmatter")

updated = False
for index in range(1, len(lines)):
    if lines[index].strip() == "---":
        break
    if re.match(r"^pr:\s*", lines[index]):
        lines[index] = f"pr: {pr_number}"
        updated = True
        break

if not updated:
    raise SystemExit("project note frontmatter is missing pr:")

path.write_text("\n".join(lines) + "\n", encoding="utf-8")
PY

echo "Updated $PROJECT_REL_PATH with pr: $PR_NUMBER"
