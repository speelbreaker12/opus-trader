#!/usr/bin/env python3
"""Shared CONTRACT AT/profile parser.

This module is the single source of truth for extracting AT profile inheritance
from CONTRACT.md. Consumers should import this instead of duplicating regexes.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List

PROFILE_LIKE_RE = re.compile(r"^\s*profile\s*:", re.IGNORECASE)
PROFILE_ALLOWED_LINES = {"Profile: CSP": "CSP", "Profile: GOP": "GOP"}
FENCE_LINE_RE = re.compile(r"^\s*([`~]{3,})(.*)$")
AT_RE = re.compile(r"^\s*(AT-\d+)\b")


@dataclass
class ParseResult:
    at_profile_map: Dict[str, str]
    counts: Dict[str, int]
    errors: List[str]


def parse_contract_profiles(contract_path: Path) -> ParseResult:
    lines = contract_path.read_text(encoding="utf-8").splitlines()

    current_profile: str | None = None
    at_profiles: Dict[str, str] = {}
    counts: Dict[str, int] = {"CSP": 0, "GOP": 0}
    errors: List[str] = []

    in_fence = False
    fence_char: str | None = None
    fence_len = 0
    fence_open_line = 0

    for lineno, line in enumerate(lines, start=1):
        fence_match = FENCE_LINE_RE.match(line)
        if fence_match:
            fence_run = fence_match.group(1)
            fence_rest = fence_match.group(2)
            run_char = fence_run[0]
            run_len = len(fence_run)

            if not in_fence:
                in_fence = True
                fence_char = run_char
                fence_len = run_len
                fence_open_line = lineno
                continue

            is_matching_close = (
                run_char == fence_char
                and run_len >= fence_len
                and fence_rest.strip() == ""
            )
            if is_matching_close:
                in_fence = False
                fence_char = None
                fence_len = 0
                fence_open_line = 0
                continue

        if in_fence:
            continue

        if PROFILE_LIKE_RE.match(line):
            normalized = line.strip()
            profile = PROFILE_ALLOWED_LINES.get(normalized)
            if not profile:
                errors.append(
                    f"{contract_path}:{lineno}: malformed Profile tag; expected exactly one of: "
                    f"Profile: CSP | Profile: GOP (got {line!r})."
                )
                # Fail closed: malformed profile tags clear inheritance scope so
                # subsequent AT lines are reported as unscoped.
                current_profile = None
                continue
            current_profile = profile
            continue

        at_match = AT_RE.match(line)
        if not at_match:
            continue

        at_id = at_match.group(1)
        if not current_profile:
            errors.append(f"{contract_path}:{lineno}: {at_id} has no Profile tag in scope.")
            continue

        existing = at_profiles.get(at_id)
        if existing and existing != current_profile:
            errors.append(
                f"{contract_path}:{lineno}: {at_id} profile conflict ({existing} vs {current_profile})."
            )

        at_profiles[at_id] = current_profile
        counts[current_profile] += 1

    if in_fence:
        open_delim = (fence_char or "`") * fence_len
        errors.append(
            f"{contract_path}:{fence_open_line}: unterminated code fence "
            f"(expected closing delimiter matching {open_delim!r})."
        )

    return ParseResult(at_profile_map=at_profiles, counts=counts, errors=errors)
