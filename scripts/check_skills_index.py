#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
INDEX_PATH = REPO_ROOT / "docs" / "skills" / "index.md"
PROMPT_PATH = REPO_ROOT / "plans" / "prompts" / "review-stack.md"


def main() -> int:
    errors: list[str] = []
    if not INDEX_PATH.exists():
        print(f"FAIL: missing {INDEX_PATH.relative_to(REPO_ROOT)}")
        return 1
    if not PROMPT_PATH.exists():
        print(f"FAIL: missing {PROMPT_PATH.relative_to(REPO_ROOT)}")
        return 1

    index_text = INDEX_PATH.read_text(encoding="utf-8")
    prompt_text = PROMPT_PATH.read_text(encoding="utf-8")

    expected_command = "- `python3 scripts/check_skills_index.py`"
    if expected_command not in index_text:
        errors.append("docs/skills/index.md must advertise the canonical validation command")

    indexed_paths = sorted(
        set(
            re.findall(
                r"`((?:SKILLS|plans/prompts|scripts)/[^`]+)`",
                index_text,
            )
        )
    )
    for rel_path in indexed_paths:
        path = REPO_ROOT / rel_path
        if not path.exists():
            errors.append(f"missing indexed path: {rel_path}")

    if "| 7-Skill Review Stack | `plans/prompts/review-stack.md` | All 7 review skills in sequence |" not in index_text:
        errors.append("docs/skills/index.md review-stack prompt entry must say 7-Skill Review Stack / All 7 review skills")

    if "| `/review-stack` | `SKILLS/review-stack.md` | Run 7 review skills in sequence" not in index_text:
        errors.append("docs/skills/index.md /review-stack summary must say Run 7 review skills in sequence")

    if "# 7-Skill Review Stack Prompt" not in prompt_text:
        errors.append("plans/prompts/review-stack.md title must say 7-Skill Review Stack Prompt")

    if "Run all 7 review skills in sequence" not in prompt_text:
        errors.append("plans/prompts/review-stack.md purpose must say Run all 7 review skills in sequence")

    if "The 7 skills, in order:" not in prompt_text:
        errors.append("plans/prompts/review-stack.md must enumerate 7 skills")

    if "7. **Loss-Risk Gate**" not in prompt_text:
        errors.append("plans/prompts/review-stack.md must include Loss-Risk Gate as skill 7")

    if errors:
        for error in errors:
            print(f"FAIL: {error}")
        return 1

    print(f"OK: validated {INDEX_PATH.relative_to(REPO_ROOT)} against tracked prompt and file paths")
    return 0


if __name__ == "__main__":
    sys.exit(main())
