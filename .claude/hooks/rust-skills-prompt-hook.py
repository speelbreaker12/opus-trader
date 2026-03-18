#!/usr/bin/env python3
"""
Rust Skills UserPromptSubmit Hook
Detects Rust-related content in user messages and reminds agent to invoke rust-router.
"""
import json
import re
import sys

RUST_PATTERNS = [
    r"\brust\b",
    r"\.rs\b",
    r"\bcargo\b",
    r"\bcrate\b",
    r"\btokio\b",
    r"\bserde\b",
    r"\banyhow\b",
    r"\bthiserror\b",
    r"E0\d{3}",
    r"\bResult<",
    r"\bOption<",
    r"\bimpl\s+\w",
    r"\btrait\b",
    r"\blifetime\b",
    r"\bborrow",
    r"\bunwrap\b",
    r"\basync\s+fn",
    r"Cargo\.toml",
    r"\bclippy\b",
    r"\brustc\b",
    r"\bArc<",
    r"\bMutex<",
    r"\bRwLock<",
]


def is_rust_related(message: str) -> bool:
    for pattern in RUST_PATTERNS:
        if re.search(pattern, message, re.IGNORECASE):
            return True
    return False


def main() -> None:
    try:
        data = json.load(sys.stdin)
        message = data.get("message", "")
    except Exception:
        sys.exit(0)

    if not is_rust_related(message):
        sys.exit(0)

    print(
        "RUST SKILLS HOOK: Rust content detected.\n"
        "MANDATORY before answering:\n"
        "  1. Invoke Skill(rust-router) to get routing\n"
        "  2. Invoke the specific skill identified (m01-m15, domain-fintech, domain-web, etc.)\n"
        "Per .rust-skills/CLAUDE.md: rust-router is NON-NEGOTIABLE. "
        "Do NOT answer from memory or skip routing."
    )


if __name__ == "__main__":
    main()
