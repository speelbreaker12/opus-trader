#!/usr/bin/env bash
# UserPromptSubmit hook: check for new/unreviewed GitHub PR & issue comments.
# Outputs JSON with additionalContext when new comments are found.
# Requires: gh CLI authenticated.

set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
STATE_FILE="$REPO_ROOT/.claude/.github-comment-review-state"
REPO_NWO="$(gh repo view --json nameWithOwner -q '.nameWithOwner' 2>/dev/null || echo "")"

if [ -z "$REPO_NWO" ]; then
    exit 0  # gh not available or not in a GitHub repo — silent skip
fi

# Timestamp of last check (ISO 8601). Default: 1 hour ago.
LAST_CHECK=""
if [ -f "$STATE_FILE" ]; then
    LAST_CHECK="$(cat "$STATE_FILE" 2>/dev/null || echo "")"
fi
if [ -z "$LAST_CHECK" ]; then
    LAST_CHECK="$(date -u -d '1 hour ago' '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
                  || date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
                  || echo "2000-01-01T00:00:00Z")"
fi

# Update state file with current time
mkdir -p "$(dirname "$STATE_FILE")"
date -u '+%Y-%m-%dT%H:%M:%SZ' > "$STATE_FILE" 2>/dev/null || true

# Use temp files for API responses (avoids shell quoting issues with JSON)
TMPDIR_HOOK="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_HOOK"' EXIT

# Fetch recent PR review comments
gh api "repos/$REPO_NWO/pulls/comments?since=$LAST_CHECK&sort=updated&direction=desc&per_page=30" \
    > "$TMPDIR_HOOK/pr_comments.json" 2>/dev/null || echo "[]" > "$TMPDIR_HOOK/pr_comments.json"

# Fetch recent issue/PR conversation comments
gh api "repos/$REPO_NWO/issues/comments?since=$LAST_CHECK&sort=updated&direction=desc&per_page=30" \
    > "$TMPDIR_HOOK/issue_comments.json" 2>/dev/null || echo "[]" > "$TMPDIR_HOOK/issue_comments.json"

# Fetch open PRs
gh pr list --repo "$REPO_NWO" --state open --json number,title,author,updatedAt,url --limit 10 \
    > "$TMPDIR_HOOK/open_prs.json" 2>/dev/null || echo "[]" > "$TMPDIR_HOOK/open_prs.json"

# Build summary and output JSON — all in one Python script using temp files
python3 - "$TMPDIR_HOOK" "$REPO_NWO" <<'PYEOF'
import json
import sys
import os

tmpdir = sys.argv[1]
repo_nwo = sys.argv[2]

def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except Exception:
        return []

pr_comments = load_json(os.path.join(tmpdir, "pr_comments.json"))
issue_comments = load_json(os.path.join(tmpdir, "issue_comments.json"))
open_prs = load_json(os.path.join(tmpdir, "open_prs.json"))

if not pr_comments and not issue_comments and not open_prs:
    sys.exit(0)

lines = []
lines.append(f"## GitHub Activity Report for {repo_nwo}")
lines.append("")

if open_prs:
    lines.append(f"### Open PRs ({len(open_prs)})")
    for pr in open_prs:
        author = pr.get("author", {}).get("login", "unknown")
        lines.append(f"- PR #{pr.get('number')}: {pr.get('title')} by {author} — {pr.get('url', '')}")
    lines.append("")

if pr_comments:
    lines.append(f"### New PR Review Comments ({len(pr_comments)})")
    for c in pr_comments:
        user = c.get("user", {}).get("login", "unknown")
        body = c.get("body", "")[:500]
        pr_url = c.get("pull_request_url", "")
        pr_num = pr_url.rstrip("/").split("/")[-1] if pr_url else "?"
        path = c.get("path", "")
        line_num = c.get("original_line", c.get("line", "?"))
        lines.append(f"- **PR #{pr_num}** | `{path}:{line_num}` | @{user}:")
        lines.append(f"  > {body}")
        lines.append("")

if issue_comments:
    lines.append(f"### New Issue/PR Comments ({len(issue_comments)})")
    for c in issue_comments:
        user = c.get("user", {}).get("login", "unknown")
        body = c.get("body", "")[:500]
        issue_url = c.get("issue_url", c.get("html_url", ""))
        lines.append(f"- {issue_url} | @{user}:")
        lines.append(f"  > {body}")
        lines.append("")

summary = "\n".join(lines)

output = {
    "hookSpecificOutput": {
        "hookEventName": "UserPromptSubmit",
        "additionalContext": (
            "GITHUB COMMENT REVIEW REQUIRED:\n\n"
            + summary
            + "\n\nTRIAGE INSTRUCTIONS:\n"
            "1. Review each comment for validity and relevance.\n"
            "2. Classify severity:\n"
            "   - P0: Production down, data loss risk, security vulnerability → ESCALATE to human immediately\n"
            "   - P1: Major bug, broken functionality, contract violation → ESCALATE to human\n"
            "   - P2: Minor bug, non-critical issue, test gap → AUTO-FIX (create branch, fix, push)\n"
            "   - P3: Style, docs, minor improvement → AUTO-FIX (create branch, fix, push)\n"
            "3. For P2/P3: fix the issue on a new branch, commit, push, and reply to the comment.\n"
            "4. For P0/P1: summarize the issue and recommended fix, then ask the human for approval before acting.\n"
            "5. Always respond to the GitHub comment with your triage assessment using gh.\n"
        )
    }
}
print(json.dumps(output))
PYEOF
