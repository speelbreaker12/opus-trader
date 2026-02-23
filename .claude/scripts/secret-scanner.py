#!/usr/bin/env python3
"""
Secret Scanner Hook
Adapted from davila7/claude-code-templates (MIT)
Scans files referenced in git commit commands for hardcoded secrets.
"""

import json
import shlex
import sys
import re
import subprocess
import os

SECRET_PATTERNS = [
    # AWS
    (r"AKIA[0-9A-Z]{16}", "AWS Access Key ID", "critical"),
    (r"(?i)aws[_\-\s]*secret[_\-\s]*access[_\-\s]*key['\"\s]*[=:]['\"\s]*[A-Za-z0-9/+=]{40}", "AWS Secret Access Key", "critical"),
    # Anthropic
    (r"sk-ant-api\d{2}-[A-Za-z0-9\-_]{20,}", "Anthropic API Key", "critical"),
    # OpenAI
    (r"sk-[a-zA-Z0-9]{48,}", "OpenAI API Key", "high"),
    (r"sk-proj-[a-zA-Z0-9\-_]{32,}", "OpenAI Project API Key", "high"),
    # Google
    (r"AIza[0-9A-Za-z\-_]{35}", "Google API Key", "high"),
    # Stripe
    (r"sk_live_[0-9a-zA-Z]{24,}", "Stripe Live Secret Key", "critical"),
    (r"rk_live_[0-9a-zA-Z]{24,}", "Stripe Live Restricted Key", "critical"),
    # GitHub
    (r"ghp_[0-9a-zA-Z]{36}", "GitHub Personal Access Token", "high"),
    (r"gho_[0-9a-zA-Z]{36}", "GitHub OAuth Token", "high"),
    (r"ghs_[0-9a-zA-Z]{36}", "GitHub App Secret", "high"),
    (r"github_pat_[0-9a-zA-Z_]{22,}", "GitHub Fine-Grained PAT", "high"),
    # Exchange / trading API keys (opus-trader specific)
    (r"(?i)(api[_\-]?secret|api[_\-]?key|passphrase)['\"\s]*[=:]['\"\s]*['\"][0-9a-zA-Z\-_/+=]{16,}['\"]", "Exchange API Credential", "critical"),
    # Private keys
    (r"-----BEGIN (RSA |DSA |EC )?PRIVATE KEY-----", "Private Key", "critical"),
    (r"-----BEGIN OPENSSH PRIVATE KEY-----", "OpenSSH Private Key", "critical"),
    # Database connection strings
    (r"(?i)(mysql|postgresql|postgres|mongodb|redis)://[^\s'\"\)]+:[^\s'\"\)]+@", "Database Connection String", "critical"),
    # Generic secrets
    (r"(?i)(secret[_\-\s]*key|secretkey)['\"\s]*[=:]['\"\s]*['\"][0-9a-zA-Z\-_]{20,}['\"]", "Generic Secret Key", "high"),
    (r"(?i)password['\"\s]*[=:]['\"\s]*['\"][^'\"\s]{8,}['\"]", "Hardcoded Password", "high"),
    # JWT
    (r"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}", "JWT Token", "medium"),
    # Slack
    (r"xox[baprs]-[0-9a-zA-Z\-]{10,}", "Slack Token", "high"),
]

EXCLUDED_FILES = {
    ".env.example", ".env.sample", ".env.template",
    "package-lock.json", "yarn.lock", "Cargo.lock",
    "go.sum", "poetry.lock", ".gitignore",
}

EXCLUDED_DIRS = [
    "node_modules/", ".git/", ".claude/scripts/", "target/", "dist/", "build/",
    "__pycache__/", ".pytest_cache/", "venv/", "artifacts/",
]


def should_skip_file(file_path: str) -> bool:
    if not os.path.exists(file_path):
        return True
    if os.path.basename(file_path) in EXCLUDED_FILES:
        return True
    for d in EXCLUDED_DIRS:
        if d in file_path:
            return True
    try:
        with open(file_path, "rb") as f:
            if b"\0" in f.read(1024):
                return True
    except Exception:
        return True
    return False


def get_staged_files() -> list[str]:
    try:
        result = subprocess.run(
            ["git", "diff", "--cached", "--name-only", "--diff-filter=ACM"],
            capture_output=True, text=True, check=True,
        )
        return [f.strip() for f in result.stdout.split("\n") if f.strip()]
    except subprocess.CalledProcessError:
        return []


def scan_file(file_path: str) -> list[dict]:
    findings = []
    if should_skip_file(file_path):
        return findings
    try:
        with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
            content = f.read()
        for line_num, line in enumerate(content.split("\n"), 1):
            stripped = line.strip()
            # skip comments
            if stripped.startswith("#") or stripped.startswith("//"):
                if "example" in stripped.lower() or "placeholder" in stripped.lower():
                    continue
            for pattern, description, severity in SECRET_PATTERNS:
                for match in re.finditer(pattern, line):
                    findings.append({
                        "file": file_path,
                        "line": line_num,
                        "description": description,
                        "severity": severity,
                        "match": match.group(0)[:40] + "..." if len(match.group(0)) > 40 else match.group(0),
                    })
    except Exception:
        pass
    return findings


def main() -> None:
    try:
        input_data = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        sys.exit(0)

    command = input_data.get("tool_input", {}).get("command", "")
    if not re.search(r"git\s+commit", command):
        sys.exit(0)

    staged_files = get_staged_files()

    # Handle git commit -a (auto-stage tracked modified files)
    if not staged_files:
        commit_match = re.search(r"git\s+commit\s+(.+)", command)
        if commit_match and re.search(r"-\w*a", commit_match.group(1)):
            result = subprocess.run(
                ["git", "diff", "--name-only"],
                capture_output=True, text=True,
            )
            for f in result.stdout.strip().split("\n"):
                if f.strip() and os.path.isfile(f.strip()):
                    staged_files.append(f.strip())

        # Handle chained: git add ... && git commit
        for part in re.split(r"&&|;", command):
            part = part.strip()
            add_match = re.match(r"git\s+add\s+(.+)", part)
            if add_match:
                args = add_match.group(1).strip()
                if args in (".", "-A", "--all"):
                    result = subprocess.run(
                        ["git", "status", "--porcelain"],
                        capture_output=True, text=True,
                    )
                    for line in result.stdout.strip().split("\n"):
                        if line and len(line) > 3:
                            f = line[3:].strip()
                            if os.path.isfile(f):
                                staged_files.append(f)
                else:
                    try:
                        tokens = shlex.split(args)
                    except ValueError:
                        tokens = args.split()
                    for token in tokens:
                        if not token.startswith("-") and os.path.isfile(token):
                            staged_files.append(token)

    if not staged_files:
        sys.exit(0)

    all_findings = []
    for file_path in staged_files:
        all_findings.extend(scan_file(file_path))

    if all_findings:
        severity_order = {"critical": 0, "high": 1, "medium": 2, "low": 3}
        all_findings.sort(key=lambda x: (severity_order.get(x["severity"], 4), x["file"], x["line"]))

        print(f"SECRET SCANNER: {len(all_findings)} potential secret(s) detected!", file=sys.stderr)
        print("", file=sys.stderr)
        for f in all_findings:
            tag = {"critical": "CRITICAL", "high": "HIGH", "medium": "MEDIUM", "low": "LOW"}.get(f["severity"], "?")
            print(f"  [{tag}] {f['description']}", file=sys.stderr)
            print(f"    {f['file']}:{f['line']}  {f['match']}", file=sys.stderr)
        print("", file=sys.stderr)
        print("BLOCKED: Remove secrets before committing.", file=sys.stderr)
        print("Use environment variables or a secrets manager instead.", file=sys.stderr)
        sys.exit(2)

    sys.exit(0)


if __name__ == "__main__":
    main()
