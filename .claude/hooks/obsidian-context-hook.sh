#!/usr/bin/env bash
# UserPromptSubmit hook: identify the active project from branch ownership,
# inject minimal context, and delegate full routing to /obsidian-workflow skill.
#
# This hook is intentionally slim. It does deterministic branch→project lookup,
# not scoring/tokenizing. The skill handles ambiguity, new-project proposals,
# and worktree routing.

set -euo pipefail

input_file="$(mktemp)"
trap 'rm -f "$input_file"' EXIT
cat >"$input_file"

ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
source "$ROOT/plans/lib/obsidian_vault.sh"

PROJECTS_DIR=""
if resolve_obsidian_vault_path advisory; then
  PROJECTS_DIR="${OBSIDIAN_VAULT_PATH_RESOLVED}/Projects"
else
  printf '%s\n' "$(obsidian_vault_missing_message advisory "$(obsidian_vault_configured_path)")"
  exit 0
fi

if [[ ! -d "$PROJECTS_DIR" ]]; then
  printf '%s\n' "$(obsidian_vault_missing_message advisory "$PROJECTS_DIR")"
  exit 0
fi

STATE_DIR="${OBSIDIAN_CONTEXT_STATE_DIR:-${TMPDIR:-/tmp}/obsidian-context-router}"
mkdir -p "$STATE_DIR"

python3 - "$input_file" "$PROJECTS_DIR" "$STATE_DIR" "$ROOT" <<'PYEOF'
import hashlib
import json
import subprocess
import sys
from pathlib import Path

# Use shared frontmatter parser
sys.path.insert(0, str(Path(sys.argv[4]) / "plans" / "lib"))
from obsidian_frontmatter import parse_frontmatter, clean_scalar


def read_payload(path: Path) -> dict:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return {}


# --- Args ---
payload_path = Path(sys.argv[1])
projects_dir = Path(sys.argv[2])
state_dir = Path(sys.argv[3])
repo_root = Path(sys.argv[4])

payload = read_payload(payload_path)
message = str(payload.get("message", "")).strip()
if not message:
    sys.exit(0)

# --- Session dedup ---
session_id = str(
    payload.get("session_id")
    or payload.get("conversation_id")
    or payload.get("transcript_path")
    or ""
).strip()

marker_path = None
if session_id:
    marker_name = hashlib.sha256(session_id.encode("utf-8")).hexdigest()[:12]
    marker_path = state_dir / f"{marker_name}.seen"
    if marker_path.exists():
        sys.exit(0)

# --- Scope file for downstream consumers ---
scope_dir = state_dir / "scope"
scope_dir.mkdir(parents=True, exist_ok=True)

# --- Load projects ---
project_paths = sorted(projects_dir.glob("*.md"))
if not project_paths:
    if marker_path is not None:
        marker_path.write_text("seen\n", encoding="utf-8")
    sys.exit(0)

projects = []
for path in project_paths:
    content = path.read_text(encoding="utf-8")
    fm = parse_frontmatter(content)
    projects.append({
        "name": path.stem,
        "rel_path": str(path.relative_to(projects_dir.parent.parent)),
        "branch": clean_scalar(fm.get("branch", "")),
        "status": clean_scalar(fm.get("status", "")),
        "worktree": clean_scalar(fm.get("worktree", "")),
        "pr": clean_scalar(fm.get("pr", "")),
    })

# --- Current branch ---
try:
    current_branch = subprocess.check_output(
        ["git", "-C", str(repo_root), "rev-parse", "--abbrev-ref", "HEAD"],
        stderr=subprocess.DEVNULL, text=True,
    ).strip()
except Exception:
    current_branch = ""

# --- Deterministic routing: branch ownership ---
active_projects = [p for p in projects if p["status"] not in ("done", "archived")]
branch_owners = [p for p in projects if p["branch"] == current_branch] if current_branch else []
matched = branch_owners[0] if len(branch_owners) == 1 else None

# --- Output ---
lines = ["OBSIDIAN PROJECT CONTEXT — Active projects:"]
lines.append("")
for p in projects:
    status_tag = p["status"] or "unknown"
    branch_tag = f" [branch:{p['branch']}]" if p["branch"] else ""
    wt_tag = f" [wt:{p['worktree']}]" if p.get("worktree") else ""
    lines.append(f"- [{p['name'].split()[0][0]}{len(p['name'])%9}] {p['name']} ({status_tag}){branch_tag}{wt_tag}")

lines.append("")
lines.append("Routing decision:")

if matched:
    lines.append(f"- Matched existing project: {matched['name']}")
    lines.append(f"- Branch: {matched['branch']}")
    lines.append(f"- Worktree: {matched.get('worktree') or 'not set'}")
    # Write scope file for downstream guards
    scope_file = scope_dir / f"{marker_name}.json" if session_id else scope_dir / "latest.json"
    scope_file.write_text(json.dumps({
        "project": matched["name"],
        "branch": matched["branch"],
        "worktree": matched.get("worktree", ""),
        "pr": matched.get("pr", ""),
    }, indent=2), encoding="utf-8")
    lines.append(f"- Project scope captured: {scope_file}")
    lines.append("- Continue in this project scope.")

    # --- Worktree path check ---
    # Verify CWD matches the project note's declared worktree.
    expected_wt = matched.get("worktree", "")
    if expected_wt:
        try:
            actual_toplevel = subprocess.check_output(
                ["git", "-C", str(repo_root), "rev-parse", "--show-toplevel"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
        except Exception:
            actual_toplevel = ""
        if actual_toplevel and not actual_toplevel.endswith(expected_wt.rstrip("/")):
            lines.append("")
            lines.append(f"WARNING: Worktree mismatch.")
            lines.append(f"  Expected: {expected_wt}")
            lines.append(f"  Actual:   {actual_toplevel}")
            lines.append(f"  Switch to the project's worktree before editing.")

    # --- Merged PR detection ---
    # If project note records a PR, check if it's already merged.
    pr_num = matched.get("pr", "")
    if pr_num:
        try:
            pr_json = subprocess.check_output(
                ["gh", "pr", "view", str(pr_num), "--json", "state"],
                stderr=subprocess.DEVNULL, text=True,
            ).strip()
            pr_state = json.loads(pr_json).get("state", "")
            if pr_state == "MERGED":
                lines.append("")
                lines.append(f"WARNING: PR #{pr_num} is MERGED.")
                lines.append(f"  This branch/worktree may be stale.")
                lines.append(f"  Consider post-merge cleanup per SKILLS/obsidian-workflow.md.")
        except Exception:
            pass  # gh not available or PR not found — skip silently

else:
    lines.append("- No branch-owned project matched.")
    lines.append("- Read SKILLS/obsidian-workflow.md to route this task.")

# --- Recent debriefs (last 3) ---
debriefs_dir = projects_dir.parent / "Debriefs"
if debriefs_dir.is_dir():
    debrief_files = sorted(debriefs_dir.glob("*.md"), key=lambda p: p.stat().st_mtime, reverse=True)[:3]
    if debrief_files:
        lines.append("")
        lines.append("Recent debriefs (last 3 files):")
        for df in debrief_files:
            lines.append(f"- {df.stem}")

print("\n".join(lines))

if marker_path is not None:
    marker_path.write_text("seen\n", encoding="utf-8")
PYEOF
