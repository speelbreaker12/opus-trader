#!/usr/bin/env bash
# UserPromptSubmit hook: route the first prompt in a session to the most likely
# Obsidian project note, inject the matched note into context, and require the
# assistant to acknowledge it before proceeding.

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

python3 - "$input_file" "$PROJECTS_DIR" "$STATE_DIR" "$ROOT" <<'PY'
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


def suggest_project_name(message_text: str) -> str:
    title_tokens = [token.capitalize() for token in tokenize(message_text)]
    if not title_tokens:
        return "New Project.md"
    limited = title_tokens[:6]
    return " ".join(limited) + ".md"


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
projects_dir = Path(sys.argv[2])
state_dir = Path(sys.argv[3])
repo_root = Path(sys.argv[4])

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
if not project_paths:
    if marker_path is not None:
        marker_path.write_text("seen\n", encoding="utf-8")
    sys.exit(0)

message_tokens = tokenize(message)
projects: list[dict] = []
for path in project_paths:
    content = path.read_text(encoding="utf-8")
    frontmatter, body = parse_frontmatter(content)
    project = {
        "path": path,
        "rel_path": str(path.relative_to(projects_dir.parent.parent)),
        "name": path.stem,
        "content": content,
        "current_state": section_text(body, "## Current State"),
        "key_files": section_text(body, "## Key Files"),
        "log": section_text(body, "## Log"),
        "message_text": message.lower(),
        "branch": clean_scalar(frontmatter.get("branch", "")),
        "aliases": frontmatter_list(frontmatter, "aliases"),
        "keywords": frontmatter_list(frontmatter, "keywords"),
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
top = projects[0]
second = projects[1] if len(projects) > 1 else None

try:
    current_branch = subprocess.check_output(
        ["git", "-C", str(repo_root), "rev-parse", "--abbrev-ref", "HEAD"],
        stderr=subprocess.DEVNULL,
        text=True,
    ).strip()
except Exception:
    current_branch = ""

branch_owners = [project for project in projects if project["branch"] == current_branch]
current_branch_owner = branch_owners[0] if len(branch_owners) == 1 else None

confidence_threshold = 10
ambiguity_gap = 2

output_lines = [
    "OBSIDIAN PROJECT ROUTER",
    f"Obsidian folder: {projects_dir.relative_to(projects_dir.parent.parent)}",
    "Companion skill: /obsidian-workflow",
]
should_mark_seen = False

if top["score"] < confidence_threshold:
    output_lines.extend(
        [
            "No related Obsidian project note matched the first prompt.",
            "MANDATORY FIRST RESPONSE:",
            "- Consult /obsidian-workflow for the project-note and debrief checklist.",
            "- Tell the user no related project note was found in obsidian/Projects and propose a new one.",
            f"- Suggested new project note: {suggest_project_name(message)}",
            "- Mention that you checked obsidian/Projects before responding.",
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
    should_mark_seen = True
    output_lines.extend(
        [
            f"Matched Obsidian project: {top['rel_path']}",
            f"Matched terms: {', '.join(top['matched_terms']) or 'none'}",
            "MANDATORY FIRST RESPONSE:",
            "- Consult /obsidian-workflow for the project-note and debrief checklist.",
            f"- Confirm you found and read {top['rel_path']} before proceeding.",
            f"- Name the matched Obsidian project note explicitly: {top['name']}.",
            "- Mention that you checked obsidian/Projects before responding.",
            render_project_block(top),
        ]
    )
    if current_branch_owner is not None and top["branch"] and top["branch"] != current_branch:
        should_mark_seen = False
        output_lines.extend(
            [
                "BRANCH/WORKTREE MISMATCH",
                f"Current branch: {current_branch}",
                f"Matched project branch: {top['branch']}",
                f"Current branch owner: {current_branch_owner['rel_path']}",
                "Switch or create the matched project's worktree before editing.",
            ]
        )

print("\n".join(output_lines))

if marker_path is not None and should_mark_seen:
    marker_path.write_text("seen\n", encoding="utf-8")
PY
