#!/usr/bin/env python3
"""
Dangerous Command Blocker Hook
Adapted from davila7/claude-code-templates (MIT)
Customized for opus-trader: adds Cargo.lock, .wf/, specs/, plans/ protection
"""

import json
import os
import sys
import re

data = json.load(sys.stdin)
cmd = data.get("tool_input", {}).get("command", "")

# === LEVEL 0: CONTEXT-AWARE ALLOWLISTS ===

# Allow --force-with-lease on non-main branches (normal post-rebase workflow).
# Still block bare --force (without -with-lease) and any force to main/master.
if re.search(r"\bgit\s+push\s+.*--force-with-lease", cmd, re.IGNORECASE):
    if re.search(r"\bgit\s+push\s+(\S+\s+)?(main|master)\b", cmd, re.IGNORECASE):
        print("BLOCKED: --force-with-lease to main/master is never allowed", file=sys.stderr)
        sys.exit(2)
    # Allow on feature branches
    sys.exit(0)

# Allow git reset --hard during main recovery (env var set by /main-recovery skill).
if re.search(r"\bgit\s+reset\s+--hard", cmd, re.IGNORECASE):
    if os.environ.get("MAIN_RECOVERY", "") == "1":
        print("ALLOWED: git reset --hard (MAIN_RECOVERY=1)", file=sys.stderr)
        sys.exit(0)

# === LEVEL 1: CATASTROPHIC COMMANDS (ALWAYS BLOCK) ===
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
    (r"\bgit\s+push\s+(\S+\s+)?(main|master)\b", "git push to main/master (use a feature branch)"),
    (r"\bgit\s+reset\s+--hard(\s|$)", "git reset --hard (set MAIN_RECOVERY=1 for recovery)"),
]

for pattern, desc in catastrophic_patterns:
    if re.search(pattern, cmd, re.IGNORECASE):
        print(f"BLOCKED: Catastrophic command detected!", file=sys.stderr)
        print(f"Reason: {desc}", file=sys.stderr)
        print(f"Command: {cmd[:100]}", file=sys.stderr)
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
