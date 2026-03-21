#!/usr/bin/env python3
"""
Dangerous Command Blocker Hook
Adapted from davila7/claude-code-templates (MIT)
Customized for opus-trader: adds Cargo.lock, .wf/, specs/, plans/ protection
"""

import json
import os
import subprocess
import sys
import re

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")


def _targets_main(command: str) -> bool:
    """Check if a git push targets main/master, including refspec forms like HEAD:main."""
    # Direct branch name: git push origin main (end of string or followed by whitespace)
    if re.search(r"\bgit\s+push\s+\S+\s+(main|master)\s*($|\s|;|&&|\|\|)", command, re.IGNORECASE):
        return True
    # Refspec form: git push origin HEAD:main, +HEAD:refs/heads/main
    if re.search(r"\bgit\s+push\b.*:(main|master|refs/heads/main|refs/heads/master)\b", command, re.IGNORECASE):
        return True
    return False


# === LEVEL 1: CATASTROPHIC COMMANDS (ALWAYS BLOCK — runs before any allowlist) ===
catastrophic_patterns = [
    (r"\brm\s+.*\s+/(\s|$)", "rm on root directory"),
    (r"\brm\s+.*\s+~(\s|$)", "rm on home directory"),
    (r"\brm\s+.*\s+\*(\s|$)", "rm with star wildcard"),
    (r"\brm\s+-[rfRF]*[rfRF]+.*\*", "rm -rf with wildcards"),
    (r"\b(dd\s+if=|dd\s+of=/dev)", "dd disk operations"),
    (r"\b(mkfs\.|mkswap\s|fdisk\s)", "filesystem formatting"),
    (r"\b:(\(\))?\s*\{\s*:\s*\|\s*:\s*&\s*\}", "fork bomb"),
    (r">\s*/dev/sd[a-z]", "direct disk write"),
    (r"\bchmod\s+(-R\s+)?777\s+/", "chmod 777 on root"),
    (r"\bchown\s+(-R\s+)?.*\s+/(\s|$)", "chown on root directory"),
    (r"\bgit\s+push\s+.*--force(?!-with-lease)(\s|$)", "git force push (use --force-with-lease)"),
    # main/master push: require main/master at end of push args or before shell operator.
    # Avoids false positives on hyphenated branch names like main-recovery-branch.
    (r"\bgit\s+push\s+\S+\s+(main|master)\s*($|;|&&|\|\|)", "git push to main/master (use a feature branch)"),
    (r"\bgit\s+reset\s+--hard(\s|$)", "git reset --hard (set MAIN_RECOVERY=1 for recovery)"),
]

for pattern, desc in catastrophic_patterns:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"BLOCKED: Catastrophic command detected!", file=sys.stderr)
        print(f"Reason: {desc}", file=sys.stderr)
        print(f"Command: {cmd[:100]}", file=sys.stderr)
        sys.exit(2)

# === LEVEL 0: CONTEXT-AWARE ALLOWLISTS (after Level 1 catastrophic checks) ===

# Allow --force-with-lease on non-main branches (normal post-rebase workflow).
# Still block bare --force (without -with-lease) and any force to main/master.
if re.search(r"\bgit\s+push\s+.*--force-with-lease", cmd, re.IGNORECASE):
    if _targets_main(cmd):
        print("BLOCKED: --force-with-lease to main/master is never allowed", file=sys.stderr)
        sys.exit(2)
    # Allow on feature branches
    sys.exit(0)

# Allow git reset --hard during main recovery — only on main/master branch.
if re.search(r"\bgit\s+reset\s+--hard", cmd, re.IGNORECASE):
    if os.environ.get("MAIN_RECOVERY", "") == "1":
        try:
            current_branch = subprocess.check_output(
                ["git", "rev-parse", "--abbrev-ref", "HEAD"],
                text=True, stderr=subprocess.DEVNULL
            ).strip()
        except (subprocess.CalledProcessError, FileNotFoundError):
            current_branch = ""
        if current_branch in ("main", "master"):
            print("ALLOWED: git reset --hard on main (MAIN_RECOVERY=1)", file=sys.stderr)
            sys.exit(0)
        else:
            print(f"BLOCKED: MAIN_RECOVERY=1 only allows git reset --hard on main/master, not '{current_branch}'", file=sys.stderr)
            sys.exit(2)

# === LEVEL 2: CRITICAL PATH PROTECTION ===
critical_paths = [
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?\.claude['\"]?(/|$|\s)", "Claude Code configuration"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?\.git['\"]?(/|$|\s)", "Git repository"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?[^\s'\"]*\.env['\"]?(\s|$)", "Environment variables"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?[^\s'\"]*Cargo\.toml['\"]?(\s|$)", "Rust manifest"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?[^\s'\"]*Cargo\.lock['\"]?(\s|$)", "Rust lock file"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?\.wf['\"]?(/|$|\s)", "Workflow receipt state"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?specs['\"]?(/|$|\s)", "Contract specs directory"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?specs/CONTRACT\.md['\"]?(\s|$)", "CONTRACT.md"),
    (r"\b(rm|mv)\s+(-[rfRF]+\s+)?['\"]?plans/prd\.json['\"]?(\s|$)", "PRD state file"),
]

for pattern, desc in critical_paths:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"BLOCKED: Critical path protection!", file=sys.stderr)
        print(f"Protected resource: {desc}", file=sys.stderr)
        print(f"Command: {cmd[:100]}", file=sys.stderr)
        sys.exit(2)

# === LEVEL 3: SUSPICIOUS PATTERNS (WARNING, no block) ===
suspicious_patterns = [
    (r"\brm\s+.*\s+&&", "chained rm commands"),
    (r"\brm\s+[^\s/]*\*", "rm with wildcards"),
    (r"\bfind\s+.*-delete", "find -delete operation"),
    (r"\bxargs\s+.*\brm", "xargs with rm"),
]

for pattern, desc in suspicious_patterns:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"WARNING: Suspicious pattern: {desc}", file=sys.stderr)
        print(f"Command: {cmd[:100]}", file=sys.stderr)
        sys.exit(0)  # warn only

sys.exit(0)
