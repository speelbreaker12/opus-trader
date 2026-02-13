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
PROFILE_ALLOWED_LINES = {"Profile: CSP", "Profile: GOP"}
FENCE_START_RE = re.compile(r"^\s*(```|~~~)")
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
    fence_delim: str | None = None

    for lineno, line in enumerate(lines, start=1):
        fence_match = FENCE_START_RE.match(line)
        if fence_match:
            delim = fence_match.group(1)
            if not in_fence:
                in_fence = True
                fence_delim = delim
            elif fence_delim == delim:
                in_fence = False
                fence_delim = None
            continue

        if in_fence:
            continue

        if PROFILE_LIKE_RE.match(line):
            normalized = line.strip()
            if normalized not in PROFILE_ALLOWED_LINES:
                errors.append(
                    f"{contract_path}:{lineno}: malformed Profile tag; expected exactly one of: "
                    f"Profile: CSP | Profile: GOP (got {line!r})."
                )
                # Fail closed: malformed profile tags clear inheritance scope so
                # subsequent AT lines are reported as unscoped.
                current_profile = None
                continue
            current_profile = "CSP" if normalized.endswith("CSP") else "GOP"
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

    return ParseResult(at_profile_map=at_profiles, counts=counts, errors=errors)
