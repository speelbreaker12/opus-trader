#!/usr/bin/env python3
"""Shared CONTRACT AT/profile parser.

This module is the single source of truth for extracting AT profile inheritance
from CONTRACT.md. Consumers should import this instead of duplicating regexes.
"""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Dict, List

PROFILE_RE = re.compile(r"^Profile:\s+(CSP|GOP|FULL)\s*$")
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

    for lineno, line in enumerate(lines, start=1):
        profile_match = PROFILE_RE.match(line)
        if profile_match:
            profile = profile_match.group(1)
            # FULL is not valid for AT inheritance.
            if profile == "FULL":
                errors.append(
                    f"{contract_path}:{lineno}: Profile: FULL is not allowed for AT inheritance."
                )
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

    return ParseResult(at_profile_map=at_profiles, counts=counts, errors=errors)
