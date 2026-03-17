#!/usr/bin/env bash
# UserPromptSubmit hook: route the first prompt in a session to the most likely
# Obsidian project note, inject the matched note into context, and direct the
# agent into the project's dedicated worktree.

set -euo pipefail

input_file="$(mktemp)"
trap 'rm -f "$input_file"' EXIT
cat >"$input_file"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
PROJECTS_DIR="$ROOT/obsidian/Projects"

if [[ ! -d "$PROJECTS_DIR" ]]; then
  exit 0
fi

STATE_DIR="${OBSIDIAN_CONTEXT_STATE_DIR:-${TMPDIR:-/tmp}/obsidian-context-router}"
mkdir -p "$STATE_DIR"

python3 - "$input_file" "$ROOT" "$PROJECTS_DIR" "$STATE_DIR" <<'PY'
from datetime import date
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path


def read_payload(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


def normalize_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.strip())


def clean_scalar(value: str) -> str:
    value = value.strip()
    if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
        return value[1:-1].strip()
    return value


def parse_frontmatter(content: str) -> tuple[dict, str]:
    lines = content.splitlines()
    if not lines or lines[0].strip() != "---":
        return {}, content

    frontmatter: dict = {}
    i = 1
    while i < len(lines):
        line = lines[i]
        stripped = line.strip()
        if stripped == "---":
            return frontmatter, "\n".join(lines[i + 1 :])
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

        items: list[str] = []
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

    return frontmatter, content


def frontmatter_list(frontmatter: dict, key: str) -> list[str]:
    value = frontmatter.get(key, [])
    if isinstance(value, list):
        return [normalize_text(str(item)) for item in value if str(item).strip()]
    if isinstance(value, str) and value.strip():
        return [normalize_text(value)]
    return []


def frontmatter_scalar(frontmatter: dict, key: str) -> str:
    value = frontmatter.get(key, "")
    if isinstance(value, list):
        return ""
    return normalize_text(str(value)) if str(value).strip() else ""


def tokenize(value: str) -> set[str]:
    return {
        token
        for token in re.findall(r"[a-z0-9]+", value.lower())
        if len(token) >= 3 and token not in STOPWORDS
    }


def section_text(content: str, heading: str) -> str:
    lines = content.splitlines()
    capture = False
    selected: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if capture:
                break
            capture = line.strip() == heading
            continue
        if capture:
            selected.append(line)
    return "\n".join(selected).strip()


def score_project(message_tokens: set[str], project: dict) -> tuple[int, list[str]]:
    score = 0
    matched: set[str] = set()

    def add_weight(tokens: set[str], weight: int) -> None:
        nonlocal score
        hits = message_tokens & tokens
        if not hits:
            return
        matched.update(hits)
        score += len(hits) * weight

    add_weight(project["name_tokens"], 8)
    add_weight(project["alias_tokens"], 7)
    add_weight(project["state_tokens"], 6)
    add_weight(project["keyword_tokens"], 6)
    add_weight(project["key_tokens"], 5)
    add_weight(project["log_tokens"], 3)

    name_phrase = project["name"].lower()
    if name_phrase and name_phrase in project["message_text"]:
        score += 12

    for alias in project["aliases"]:
        alias_phrase = alias.lower()
        if alias_phrase and alias_phrase in project["message_text"]:
            score += 10
            matched.update(tokenize(alias_phrase))

    for keyword in project["keywords"]:
        keyword_phrase = keyword.lower()
        if keyword_phrase and keyword_phrase in project["message_text"]:
            score += 8
            matched.update(tokenize(keyword_phrase))

    return score, sorted(matched)


def render_project_block(project: dict) -> str:
    return (
        f"--- BEGIN PROJECT NOTE: {project['rel_path']} ---\n"
        f"{project['content'].rstrip()}\n"
        f"--- END PROJECT NOTE: {project['rel_path']} ---"
    )


def suggest_project_stem(message_text: str) -> str:
    title_tokens = [token.capitalize() for token in tokenize(message_text)]
    if not title_tokens:
        return "New Project"
    limited = title_tokens[:6]
    return " ".join(limited)


def slugify(value: str) -> str:
    tokens = re.findall(r"[a-z0-9]+", value.lower())
    return "-".join(tokens[:8]) or "new-project"


def default_project_branch(project_name: str) -> str:
    return f"project/{slugify(project_name)}"


def default_worktree_rel(project_name: str) -> str:
    return f".worktrees/{slugify(project_name)}"


def write_project_note(path: Path, frontmatter: dict, body: str) -> None:
    preferred_order = [
        "status",
        "priority",
        "branch",
        "pr",
        "started",
        "aliases",
        "keywords",
        "worktree",
    ]
    lines = ["---"]
    emitted: set[str] = set()

    def append_key(key: str) -> None:
        if key in emitted or key not in frontmatter:
            return
        emitted.add(key)
        value = frontmatter[key]
        if isinstance(value, list):
            if value:
                lines.append(f"{key}:")
                for item in value:
                    lines.append(f"- {item}")
            else:
                lines.append(f"{key}: []")
            return
        if value == "":
            lines.append(f"{key}:")
        else:
            lines.append(f"{key}: {value}")

    for key in preferred_order:
        append_key(key)
    for key in frontmatter:
        append_key(key)

    lines.append("---")
    lines.append("")
    lines.append(body.strip())
    lines.append("")
    path.write_text("\n".join(lines), encoding="utf-8")


def repo_worktree_path(root: Path, rel_or_abs: str) -> Path:
    candidate = Path(rel_or_abs)
    if candidate.is_absolute():
        return candidate
    return root / candidate


def run_git(root: Path, *args: str, cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", *args],
        cwd=str(cwd or root),
        text=True,
        capture_output=True,
    )


def branch_exists(root: Path, branch: str) -> bool:
    return run_git(root, "show-ref", "--verify", "--quiet", f"refs/heads/{branch}").returncode == 0


def is_repo_worktree(root: Path, path: Path) -> bool:
    result = run_git(root, "rev-parse", "--show-toplevel", cwd=path)
    if result.returncode != 0:
        return False
    try:
        return Path(result.stdout.strip()).resolve() == root.resolve()
    except Exception:
        return False


def unique_worktree_rel(root: Path, base_rel: str) -> str:
    base_path = repo_worktree_path(root, base_rel)
    if not base_path.exists() or is_repo_worktree(root, base_path):
        return base_rel
    suffix = 2
    while True:
        candidate_rel = f"{base_rel}-{suffix}"
        candidate_path = repo_worktree_path(root, candidate_rel)
        if not candidate_path.exists() or is_repo_worktree(root, candidate_path):
            return candidate_rel
        suffix += 1


def ensure_project_worktree(root: Path, project_path: Path, project_name: str, frontmatter: dict, body: str) -> dict:
    branch = frontmatter_scalar(frontmatter, "branch")
    if not branch or branch in {"main", "master", "develop", "dev"}:
        branch = default_project_branch(project_name)

    worktree_rel = frontmatter_scalar(frontmatter, "worktree") or default_worktree_rel(project_name)
    worktree_rel = unique_worktree_rel(root, worktree_rel)
    worktree_path = repo_worktree_path(root, worktree_rel)

    if worktree_path.exists() and not is_repo_worktree(root, worktree_path):
        if any(worktree_path.iterdir()):
            raise RuntimeError(f"Configured worktree path exists but is not a git worktree: {worktree_rel}")

    created = False
    if not worktree_path.exists() or not is_repo_worktree(root, worktree_path):
        worktree_path.parent.mkdir(parents=True, exist_ok=True)
        if branch_exists(root, branch):
            result = run_git(root, "worktree", "add", str(worktree_path), branch)
        else:
            result = run_git(root, "worktree", "add", str(worktree_path), "-b", branch, "HEAD")
        if result.returncode != 0:
            raise RuntimeError(result.stderr.strip() or result.stdout.strip() or f"git worktree add failed for {worktree_rel}")
        created = True

    updated = False
    if frontmatter_scalar(frontmatter, "branch") != branch:
        frontmatter["branch"] = branch
        updated = True
    if frontmatter_scalar(frontmatter, "worktree") != worktree_rel:
        frontmatter["worktree"] = worktree_rel
        updated = True
    if updated:
        write_project_note(project_path, frontmatter, body)

    return {
        "branch": branch,
        "rel_path": worktree_rel,
        "abs_path": str(worktree_path.resolve()),
        "created": created,
    }


def create_project_note(root: Path, projects_dir: Path, project_name: str, message_text: str) -> dict:
    today = date.today().isoformat()
    note_path = projects_dir / f"{project_name}.md"
    if note_path.exists():
        suffix = 2
        while True:
            candidate = projects_dir / f"{project_name} {suffix}.md"
            if not candidate.exists():
                note_path = candidate
                break
            suffix += 1

    branch = default_project_branch(project_name)
    worktree_rel = default_worktree_rel(project_name)
    content = "\n".join(
        [
            "---",
            "status: in-progress",
            "priority: P1",
            f"branch: {branch}",
            "pr:",
            f"started: \"{today}\"",
            "aliases: []",
            "keywords: []",
            f"worktree: {worktree_rel}",
            "---",
            "",
            "## Current State",
            "Auto-created from the first-session router. Refine the scope before commit.",
            "",
            "## Commits",
            f"- `pending` — {today} — Auto-created project note from the first-session router.",
            "",
            "## Key Files",
            "-",
            "",
            "## Debriefs",
            "-",
            "",
            "## Handoffs",
            "- None active.",
            "",
            "## Log",
            f"### {today}",
            f"- Auto-created the project note and dedicated worktree from the first-session prompt: {message_text}",
            "",
        ]
    )
    note_path.write_text(content, encoding="utf-8")
    return {
        "path": note_path,
        "rel_path": str(note_path.relative_to(root)),
        "name": note_path.stem,
        "content": content,
    }


STOPWORDS = {
    "about",
    "after",
    "agent",
    "already",
    "also",
    "before",
    "being",
    "between",
    "confirm",
    "continue",
    "first",
    "folder",
    "found",
    "from",
    "have",
    "help",
    "into",
    "just",
    "like",
    "message",
    "need",
    "note",
    "only",
    "open",
    "please",
    "project",
    "projects",
    "read",
    "related",
    "respond",
    "response",
    "same",
    "send",
    "session",
    "should",
    "that",
    "then",
    "this",
    "user",
    "want",
    "with",
    "work",
    "would",
}


payload_path = Path(sys.argv[1])
root = Path(sys.argv[2]).resolve()
projects_dir = Path(sys.argv[3])
state_dir = Path(sys.argv[4])

payload = read_payload(payload_path)
message = normalize_text(str(payload.get("message", "")))
if not message:
    sys.exit(0)

session_id = str(
    payload.get("session_id")
    or payload.get("conversation_id")
    or payload.get("transcript_path")
    or ""
).strip()

marker_path = None
if session_id:
    marker_name = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    marker_path = state_dir / f"{marker_name}.seen"
    if marker_path.exists():
        sys.exit(0)

project_paths = sorted(projects_dir.glob("*.md"))
message_tokens = tokenize(message)
projects: list[dict] = []
for path in project_paths:
    content = path.read_text(encoding="utf-8")
    frontmatter, body = parse_frontmatter(content)
    project = {
        "path": path,
        "rel_path": str(path.relative_to(root)),
        "name": path.stem,
        "content": content,
        "current_state": section_text(body, "## Current State"),
        "key_files": section_text(body, "## Key Files"),
        "log": section_text(body, "## Log"),
        "message_text": message.lower(),
        "aliases": frontmatter_list(frontmatter, "aliases"),
        "keywords": frontmatter_list(frontmatter, "keywords"),
        "frontmatter": frontmatter,
        "body": body,
    }
    project["name_tokens"] = tokenize(project["name"])
    project["alias_tokens"] = tokenize(" ".join(project["aliases"]))
    project["state_tokens"] = tokenize(project["current_state"])
    project["keyword_tokens"] = tokenize(" ".join(project["keywords"]))
    project["key_tokens"] = tokenize(project["key_files"])
    project["log_tokens"] = tokenize(project["log"])
    project["score"], project["matched_terms"] = score_project(message_tokens, project)
    projects.append(project)

projects.sort(key=lambda item: (-item["score"], item["name"].lower()))
top = projects[0] if projects else None
second = projects[1] if len(projects) > 1 else None

confidence_threshold = 10
ambiguity_gap = 2

output_lines = [
    "OBSIDIAN PROJECT ROUTER",
    f"Obsidian folder: {projects_dir.relative_to(root)}",
    "Companion skill: /obsidian-workflow",
]
should_mark_seen = False

if top is None or top["score"] < confidence_threshold:
    project_name = suggest_project_stem(message)
    created_project = create_project_note(root, projects_dir, project_name, message)
    created_frontmatter, created_body = parse_frontmatter(created_project["path"].read_text(encoding="utf-8"))
    try:
        created_worktree = ensure_project_worktree(
            root,
            created_project["path"],
            created_project["name"],
            created_frontmatter,
            created_body,
        )
    except RuntimeError as exc:
        output_lines.extend(
            [
                "No related Obsidian project note matched the first prompt, but worktree bootstrap failed.",
                f"Created Obsidian project: {created_project['rel_path']}",
                f"Worktree bootstrap error: {exc}",
                "MANDATORY FIRST RESPONSE:",
                "- Consult /obsidian-workflow for the project-note and debrief checklist.",
                f"- Tell the user you created {created_project['rel_path']} but the dedicated worktree failed to bootstrap.",
                "- Ask the user whether to continue in the root checkout or fix the worktree setup first.",
                "- Mention that you checked obsidian/Projects before responding.",
                render_project_block(created_project),
            ]
        )
    else:
        should_mark_seen = True
        output_lines.extend(
            [
                "No related Obsidian project note matched the first prompt. Created a new project note and dedicated worktree.",
                f"Created Obsidian project: {created_project['rel_path']}",
                f"Project worktree: {created_worktree['rel_path']}",
                f"Project worktree absolute path: {created_worktree['abs_path']}",
                f"Project branch: {created_worktree['branch']}",
                "MANDATORY FIRST RESPONSE:",
                "- Consult /obsidian-workflow for the project-note and debrief checklist.",
                f"- Tell the user you created {created_project['rel_path']} because no related project note existed yet.",
                f"- Confirm you found and read {created_project['rel_path']} before proceeding.",
                f"- Tell the user you created and will use the project worktree at {created_worktree['abs_path']}.",
                "- Mention that you checked obsidian/Projects before responding.",
                render_project_block(
                    {
                        "rel_path": created_project["rel_path"],
                        "content": created_project["path"].read_text(encoding="utf-8"),
                    }
                ),
            ]
        )
elif second is not None and second["score"] >= confidence_threshold and (top["score"] - second["score"]) <= ambiguity_gap:
    output_lines.extend(
        [
            "Ambiguous Obsidian project match for first prompt.",
            f"- Candidate 1: {top['rel_path']} (score={top['score']}, matched={', '.join(top['matched_terms']) or 'none'})",
            f"- Candidate 2: {second['rel_path']} (score={second['score']}, matched={', '.join(second['matched_terms']) or 'none'})",
            "MANDATORY FIRST RESPONSE:",
            "- Consult /obsidian-workflow for the project-note and debrief checklist.",
            "- Tell the user you found multiple likely Obsidian project notes and ask them to choose one before proceeding.",
            "- Do not claim a single project was selected yet.",
            "- Mention that you checked obsidian/Projects before responding.",
            render_project_block(top),
            render_project_block(second),
        ]
    )
else:
    try:
        worktree = ensure_project_worktree(
            root,
            top["path"],
            top["name"],
            top["frontmatter"],
            top["body"],
        )
    except RuntimeError as exc:
        output_lines.extend(
            [
                f"Matched Obsidian project: {top['rel_path']}",
                f"Matched terms: {', '.join(top['matched_terms']) or 'none'}",
                f"Project worktree bootstrap error: {exc}",
                "MANDATORY FIRST RESPONSE:",
                "- Consult /obsidian-workflow for the project-note and debrief checklist.",
                f"- Confirm you found and read {top['rel_path']} before proceeding.",
                "- Tell the user the project worktree could not be prepared automatically.",
                "- Ask whether to continue in the root checkout or repair the project worktree first.",
                "- Mention that you checked obsidian/Projects before responding.",
                render_project_block(
                    {
                        "rel_path": top["rel_path"],
                        "content": top["path"].read_text(encoding="utf-8"),
                    }
                ),
            ]
        )
    else:
        should_mark_seen = True
        output_lines.extend(
            [
                f"Matched Obsidian project: {top['rel_path']}",
                f"Matched terms: {', '.join(top['matched_terms']) or 'none'}",
                f"Project worktree: {worktree['rel_path']}",
                f"Project worktree absolute path: {worktree['abs_path']}",
                f"Project branch: {worktree['branch']}",
                f"Project worktree status: {'created' if worktree['created'] else 'existing'}",
                "MANDATORY FIRST RESPONSE:",
                "- Consult /obsidian-workflow for the project-note and debrief checklist.",
                f"- Confirm you found and read {top['rel_path']} before proceeding.",
                f"- Name the matched Obsidian project note explicitly: {top['name']}.",
                f"- Tell the user you will use the project worktree at {worktree['abs_path']} for commands and edits in this session.",
                "- Mention that you checked obsidian/Projects before responding.",
                render_project_block(
                    {
                        "rel_path": top["rel_path"],
                        "content": top["path"].read_text(encoding="utf-8"),
                    }
                ),
            ]
        )

print("\n".join(output_lines))

if marker_path is not None and should_mark_seen:
    marker_path.write_text("seen\n", encoding="utf-8")
PY
