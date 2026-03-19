#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./plans/project_scope_guard.sh metadata [--branch <name>]
  ./plans/project_scope_guard.sh commit [--branch <name>]
  ./plans/project_scope_guard.sh push [--branch <name>] [--head <sha>]
  ./plans/project_scope_guard.sh pr-create [--branch <name>] [--head <sha>]
  ./plans/project_scope_guard.sh pr-create --dry-run [--branch <name>] [--head <sha>]

Modes:
  metadata   Print JSON metadata for the branch-owned project note.
  commit     Validate staged files against the active project note scope.
             Also warns if prior commits on the branch touch files outside scope.
  push       Validate the full branch diff (<base>...<head>) against scope.
  pr-create  Validate the full branch diff before opening a PR.
             --dry-run: report scope violations without blocking.
EOF
}

die() {
  echo "ERROR: $*" >&2
  exit 1
}

mode="${1:-}"
[[ -n "$mode" ]] || {
  usage >&2
  exit 2
}
shift || true

branch_name=""
head_ref="HEAD"
dry_run=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --branch)
      branch_name="${2:?missing branch name}"
      shift 2
      ;;
    --head)
      head_ref="${2:?missing head ref}"
      shift 2
      ;;
    --dry-run)
      dry_run=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      die "unknown arg: $1"
      ;;
  esac
done

case "$mode" in
  metadata|commit|push|pr-create) ;;
  *)
    usage >&2
    die "unknown mode: $mode"
    ;;
esac

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[[ -n "$ROOT" ]] || die "project scope guard must run inside a git worktree"
cd "$ROOT"

if [[ -z "$branch_name" ]]; then
  branch_name="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi
[[ -n "$branch_name" && "$branch_name" != "HEAD" ]] || die "unable to determine current branch"

# --- Hotfix branch exemption ---
# Hotfix branches touch shared code across projects and are exempt from
# scope enforcement. They still need an Obsidian project note but the
# scope_paths check is skipped.
case "$branch_name" in
  hotfix/*|hot-fix/*|fix/*)
    echo "OK: hotfix branch '$branch_name' is exempt from scope guard"
    exit 0
    ;;
esac

metadata_json="$(
  python3 - "$branch_name" "$ROOT" <<'PY'
import json
import re
import sys
from pathlib import Path


def clean_scalar(value):
    if isinstance(value, list):
        return [clean_scalar(item) for item in value]
    value = str(value).strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
        return value[1:-1].strip()
    return value


def parse_frontmatter(content: str):
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    frontmatter = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped == "---":
            break
        if not stripped:
            i += 1
            continue

        match = re.match(r"^([A-Za-z0-9_-]+):(?:\s*(.*))?$", line)
        if not match:
            i += 1
            continue

        key = match.group(1)
        raw_value = (match.group(2) or "").strip()
        if raw_value.startswith("[") and raw_value.endswith("]"):
            items = [
                clean_scalar(part)
                for part in raw_value[1:-1].split(",")
                if clean_scalar(part)
            ]
            frontmatter[key] = items
            i += 1
            continue

        if raw_value:
            frontmatter[key] = clean_scalar(raw_value)
            i += 1
            continue

        items = []
        j = i + 1
        while j < len(lines):
            next_line = lines[j]
            next_stripped = next_line.strip()
            if next_stripped == "---":
                break
            if re.match(r"^[A-Za-z0-9_-]+:\s*", next_line):
                break
            if next_stripped.startswith("- "):
                items.append(clean_scalar(next_stripped[2:]))
                j += 1
                continue
            if next_stripped:
                break
            j += 1

        frontmatter[key] = items
        i = j

    return frontmatter


def frontmatter_scalar(frontmatter, key: str) -> str:
    value = frontmatter.get(key, "")
    if isinstance(value, list):
        return clean_scalar(value[0]) if value else ""
    return clean_scalar(value)


branch_name = sys.argv[1]
repo_root = Path(sys.argv[2])
projects_dir = repo_root / "obsidian" / "Projects"
if not projects_dir.is_dir():
    print("ERROR: missing obsidian/Projects directory", file=sys.stderr)
    raise SystemExit(1)

notes = []
for path in sorted(projects_dir.glob("*.md")):
    content = path.read_text(encoding="utf-8")
    frontmatter = parse_frontmatter(content)
    scope_paths = frontmatter.get("scope_paths", [])
    if isinstance(scope_paths, str):
        scope_paths = [scope_paths] if scope_paths else []
    notes.append(
        {
            "name": path.stem,
            "path": str(path),
            "rel_path": str(path.relative_to(repo_root)),
            "branch": frontmatter_scalar(frontmatter, "branch"),
            "base": frontmatter_scalar(frontmatter, "base"),
            "pr": frontmatter_scalar(frontmatter, "pr"),
            "scope_paths": [clean_scalar(item) for item in scope_paths if str(item).strip()],
        }
    )

owners = [note for note in notes if note["branch"] == branch_name]
if not owners:
    print(
        f"ERROR: no Obsidian project note declares branch '{branch_name}'. "
        "Update or create a note under obsidian/Projects before continuing.",
        file=sys.stderr,
    )
    raise SystemExit(1)
if len(owners) > 1:
    print(
        f"ERROR: multiple Obsidian project notes declare branch '{branch_name}':",
        file=sys.stderr,
    )
    for note in owners:
        print(f"  - {note['rel_path']}", file=sys.stderr)
    raise SystemExit(1)

print(json.dumps(owners[0]))
PY
)" || exit $?

if [[ "$mode" == "metadata" ]]; then
  printf '%s\n' "$metadata_json"
  exit 0
fi

eval "$(
  python3 -c '
import json
import shlex
import sys

data = json.loads(sys.argv[1])
for key in ("name", "rel_path", "branch", "base", "pr"):
    value = data.get(key, "")
    print(f"PROJECT_{key.upper()}={shlex.quote(str(value))}")
scope_count = len(data.get("scope_paths", []))
print(f"PROJECT_SCOPE_COUNT={scope_count}")
' "$metadata_json"
)"

resolve_base_ref() {
  local declared_base="$1"

  [[ -n "$declared_base" ]] || return 1

  if [[ "$declared_base" != origin/* ]] && git rev-parse --verify "origin/${declared_base}^{commit}" >/dev/null 2>&1; then
    printf 'origin/%s\n' "$declared_base"
    return 0
  fi

  if git rev-parse --verify "${declared_base}^{commit}" >/dev/null 2>&1; then
    printf '%s\n' "$declared_base"
    return 0
  fi

  return 1
}

base_ref=""
if [[ "$mode" == "push" || "$mode" == "pr-create" ]]; then
  [[ -n "$PROJECT_BASE" ]] || die "$PROJECT_REL_PATH declares no base."
  base_ref="$(resolve_base_ref "$PROJECT_BASE" || true)"
  [[ -n "$base_ref" ]] || die "unable to resolve base ref '$PROJECT_BASE' for $PROJECT_REL_PATH"
fi

files_file="$(mktemp)"
metadata_file="$(mktemp)"
trap 'rm -f "$files_file" "$metadata_file"' EXIT
printf '%s\n' "$metadata_json" >"$metadata_file"

case "$mode" in
  commit)
    git diff --cached --name-only --diff-filter=ACMR >"$files_file"
    ;;
  push|pr-create)
    git diff --name-only "${base_ref}...${head_ref}" >"$files_file"
    ;;
esac

# Pass dry-run flag to python via env
if [[ "$dry_run" -eq 1 ]]; then
  export SCOPE_DRY_RUN=1
fi

python3 - "$mode" "$ROOT" "$metadata_file" "$files_file" <<'PY'
import fnmatch
import json
import os
import subprocess
import sys
from pathlib import Path


def parse_frontmatter(content: str):
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}

    frontmatter = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped == "---":
            break
        if not stripped:
            i += 1
            continue

        if ":" not in line:
            i += 1
            continue

        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip()
        if value:
            if len(value) >= 2 and value[0] == value[-1] and value[0] in {"'", '"'}:
                value = value[1:-1].strip()
            frontmatter[key] = value
            i += 1
            continue

        items = []
        j = i + 1
        while j < len(lines):
            next_line = lines[j]
            next_stripped = next_line.strip()
            if next_stripped == "---":
                break
            if ":" in next_line and not next_stripped.startswith("- "):
                break
            if next_stripped.startswith("- "):
                item = next_stripped[2:].strip()
                if len(item) >= 2 and item[0] == item[-1] and item[0] in {"'", '"'}:
                    item = item[1:-1].strip()
                items.append(item)
                j += 1
                continue
            if next_stripped:
                break
            j += 1
        frontmatter[key] = items
        i = j

    return frontmatter


def path_in_scope(path: str, patterns):
    for pattern in patterns:
        if pattern.endswith("/**"):
            prefix = pattern[:-3].rstrip("/")
            if path == prefix or path.startswith(prefix + "/"):
                return True
        elif pattern.endswith("/"):
            prefix = pattern.rstrip("/")
            if path == prefix or path.startswith(prefix + "/"):
                return True
        if fnmatch.fnmatchcase(path, pattern):
            return True
    return False


mode = sys.argv[1]
repo_root = Path(sys.argv[2])
metadata = json.loads(Path(sys.argv[3]).read_text(encoding="utf-8"))
paths = [
    line.strip()
    for line in Path(sys.argv[4]).read_text(encoding="utf-8").splitlines()
    if line.strip()
]
scope_paths = metadata.get("scope_paths", [])

dry_run = (mode == "pr-create" and os.environ.get("SCOPE_DRY_RUN", "0") == "1")

if not scope_paths:
    if dry_run:
        print(f"DRY-RUN WARNING: {metadata['rel_path']} declares no scope_paths.", file=sys.stderr)
        print("A real PR-create would fail here.", file=sys.stderr)
        raise SystemExit(0)
    print(f"ERROR: {metadata['rel_path']} declares no scope_paths.", file=sys.stderr)
    raise SystemExit(1)

if mode == "commit":
    foreign_project_notes = [
        path
        for path in paths
        if path.startswith("obsidian/Projects/") and path != metadata["rel_path"]
    ]
    if foreign_project_notes:
        print(
            "ERROR: staged Obsidian project note belongs to a different branch-owned project.",
            file=sys.stderr,
        )
        print(f"Expected project note: {metadata['rel_path']}", file=sys.stderr)
        print("Unexpected staged project notes:", file=sys.stderr)
        for path in foreign_project_notes:
            print(f"  - {path}", file=sys.stderr)
        raise SystemExit(1)

    for debrief_path in [path for path in paths if path.startswith("obsidian/Debriefs/")]:
        try:
            staged_content = subprocess.check_output(
                ["git", "-C", str(repo_root), "show", f":{debrief_path}"],
                text=True,
            )
        except subprocess.CalledProcessError:
            print(f"ERROR: unable to read staged debrief {debrief_path}", file=sys.stderr)
            raise SystemExit(1)

        frontmatter = parse_frontmatter(staged_content)
        project_ref = str(frontmatter.get("project", "")).strip()
        if project_ref.startswith("[[") and project_ref.endswith("]]"):
            project_name = project_ref[2:-2].strip()
        else:
            project_name = ""
        if not project_name:
            print(
                f"ERROR: staged Obsidian debrief {debrief_path} is missing project frontmatter.",
                file=sys.stderr,
            )
            raise SystemExit(1)
        if project_name != metadata["name"]:
            print(
                "ERROR: staged Obsidian debrief belongs to a different branch-owned project.",
                file=sys.stderr,
            )
            print(f"Expected project: {metadata['name']}", file=sys.stderr)
            print(f"Debrief: {debrief_path} -> {project_name}", file=sys.stderr)
            raise SystemExit(1)

outside = [path for path in paths if not path_in_scope(path, scope_paths)]
if outside:
    if dry_run:
        print("DRY-RUN WARNING: OUTSIDE PROJECT SCOPE", file=sys.stderr)
    else:
        print("ERROR: OUTSIDE PROJECT SCOPE", file=sys.stderr)
    print(f"Project: {metadata['name']}", file=sys.stderr)
    print(f"Project note: {metadata['rel_path']}", file=sys.stderr)
    print(f"Branch: {metadata['branch']}", file=sys.stderr)
    print("Files outside scope:", file=sys.stderr)
    for path in outside:
        print(f"  - {path}", file=sys.stderr)
    print("Allowed scope_paths:", file=sys.stderr)
    for pattern in scope_paths:
        print(f"  - {pattern}", file=sys.stderr)
    if dry_run:
        print("", file=sys.stderr)
        print("A real PR-create would be BLOCKED.", file=sys.stderr)
        print("Consider cherry-picking to a clean branch.", file=sys.stderr)
        raise SystemExit(0)
    raise SystemExit(1)
PY

normalize_base_name() {
  local raw="$1"

  raw="${raw#refs/heads/}"
  raw="${raw#refs/remotes/}"
  raw="${raw#origin/}"
  printf '%s\n' "$raw"
}

verify_recorded_pr_binding() {
  local pr_number="$1"
  local expected_branch="$2"
  local expected_base="$3"

  command -v gh >/dev/null 2>&1 || die "project note records PR #$pr_number but gh is unavailable; cannot validate PR binding"

  local pr_json=""
  pr_json="$(gh pr view "$pr_number" --json number,headRefName,baseRefName,state 2>/dev/null || true)"
  [[ -n "$pr_json" ]] || die "project note records PR #$pr_number but gh could not resolve it"

  eval "$(
    python3 -c '
import json
import shlex
import sys

data = json.loads(sys.argv[1])
head_ref = data.get("headRefName", "")
base_ref = data.get("baseRefName", "")
state = data.get("state", "")
print(f"PR_HEAD_REF={shlex.quote(str(head_ref))}")
print(f"PR_BASE_REF={shlex.quote(str(base_ref))}")
print(f"PR_STATE={shlex.quote(str(state))}")
    ' "$pr_json"
  )"

  [[ "$PR_STATE" == "OPEN" ]] || die "project note records PR #$pr_number with state '$PR_STATE'; clear or update pr before pushing"
  [[ "$PR_HEAD_REF" == "$expected_branch" ]] || die "project note PR #$pr_number points to branch '$PR_HEAD_REF', not '$expected_branch'"
  [[ "$(normalize_base_name "$PR_BASE_REF")" == "$(normalize_base_name "$expected_base")" ]] || die "project note PR #$pr_number targets base '$PR_BASE_REF', not '$expected_base'"
}

if [[ "$mode" == "push" ]]; then
  if [[ -n "$PROJECT_PR" ]]; then
    verify_recorded_pr_binding "$PROJECT_PR" "$PROJECT_BRANCH" "$PROJECT_BASE"
  fi
fi

if [[ "$mode" == "pr-create" ]]; then
  if [[ -n "$PROJECT_PR" ]]; then
    die "$PROJECT_REL_PATH already records PR #$PROJECT_PR. Clear or update pr before opening another PR."
  fi
fi

echo "OK: project scope guard passed for $PROJECT_NAME on branch $PROJECT_BRANCH"
if [[ -n "$base_ref" ]]; then
  echo "  base: $base_ref"
fi

# --- Mixed-project branch warning (commit mode only) ---
# Check if prior commits on this branch touch files outside scope.
# This is a soft warning, not a blocker — catches problems before PR time.
if [[ "$mode" == "commit" && "$PROJECT_SCOPE_COUNT" -gt 0 ]]; then
  branch_base="$(git merge-base origin/main HEAD 2>/dev/null || true)"
  if [[ -n "$branch_base" ]]; then
    prior_files="$(git diff --name-only "${branch_base}...HEAD" 2>/dev/null || true)"
    if [[ -n "$prior_files" ]]; then
      outside_prior="$(
        echo "$prior_files" | python3 -c "
import fnmatch, json, sys
metadata = json.loads(sys.argv[1])
scope = metadata.get('scope_paths', [])
outside = []
for line in sys.stdin:
    path = line.strip()
    if not path:
        continue
    matched = False
    for pattern in scope:
        if pattern.endswith('/**'):
            prefix = pattern[:-3].rstrip('/')
            if path == prefix or path.startswith(prefix + '/'):
                matched = True
                break
        elif pattern.endswith('/'):
            prefix = pattern.rstrip('/')
            if path == prefix or path.startswith(prefix + '/'):
                matched = True
                break
        if fnmatch.fnmatchcase(path, pattern):
            matched = True
            break
    if not matched:
        outside.append(path)
if outside:
    print(f'{len(outside)} file(s) outside scope')
    for p in outside[:5]:
        print(f'  - {p}')
    if len(outside) > 5:
        print(f'  ... and {len(outside) - 5} more')
" "$metadata_json" 2>/dev/null || true
      )"
      if [[ -n "$outside_prior" ]]; then
        echo ""
        echo "WARNING: Prior commits on this branch touch files outside project scope:"
        echo "$outside_prior"
        echo "Consider cherry-picking to a clean branch before PR."
        echo "Run: ./plans/project_scope_guard.sh pr-create --dry-run --branch $PROJECT_BRANCH"
        echo ""
      fi
    fi
  fi
fi
