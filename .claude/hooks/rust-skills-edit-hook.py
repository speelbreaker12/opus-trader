#!/usr/bin/env python3
"""
Rust Skills PreToolUse Hook (Edit/Write)
Reminds agent to use rust skills when editing Rust source files.
"""
import json
import sys


def main() -> None:
    try:
        data = json.load(sys.stdin)
        file_path = data.get("tool_input", {}).get("file_path", "")
    except Exception:
        sys.exit(0)

    if not (file_path.endswith(".rs") or file_path.endswith("Cargo.toml")):
        sys.exit(0)

    print(
        "RUST SKILLS HOOK: Editing a Rust file.\n"
        "Have you already invoked Skill(rust-router) + the appropriate skill (m01-m15 / domain-*)?\n"
        "If not, invoke them before writing code."
    )


if __name__ == "__main__":
    main()
