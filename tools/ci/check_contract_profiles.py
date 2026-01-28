#!/usr/bin/env python3
import argparse
import json
import re
import sys
from pathlib import Path


CANONICAL_MARKER = "This is the canonical contract path. Do not edit other copies."
VERSION_MARKER = "Version: 5.2"
PROFILE_RE = re.compile(r"^Profile:\s+(CSP|GOP|FULL)\s*$")
AT_RE = re.compile(r"^\s*(AT-\d+)\s*$")


def find_contract_path() -> Path:
    default = Path("specs/CONTRACT.md")
    if default.exists():
        return default
    for path in Path(".").rglob("*.md"):
        try:
            text = path.read_text()
        except OSError:
            continue
        if CANONICAL_MARKER in text and VERSION_MARKER in text:
            return path
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate AT profile inheritance.")
    parser.add_argument(
        "--contract",
        default=None,
        help="Path to the canonical contract file (default: specs/CONTRACT.md if present).",
    )
    args = parser.parse_args()

    contract_path = Path(args.contract) if args.contract else find_contract_path()
    if not contract_path or not contract_path.exists():
        print("ERROR: contract path not found.", file=sys.stderr)
        return 1

    current_profile = None
    at_profiles = {}
    errors = []
    counts = {"CSP": 0, "GOP": 0}

    for lineno, line in enumerate(contract_path.read_text().splitlines(), start=1):
        profile_match = PROFILE_RE.match(line)
        if profile_match:
            profile = profile_match.group(1)
            # FULL is not allowed for AT inheritance; use CSP or GOP tags.
            if profile == "FULL":
                errors.append(f"{contract_path}:{lineno}: Profile: FULL is not allowed for AT inheritance.")
                continue
            current_profile = profile
            continue

        at_match = AT_RE.match(line)
        if at_match:
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

    if errors:
        print("Profile validation failed:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    artifacts_dir = Path("artifacts")
    try:
        artifacts_dir.mkdir(parents=True, exist_ok=True)
        (artifacts_dir / "contract_at_profiles.json").write_text(
            json.dumps(at_profiles, indent=2, sort_keys=True)
        )
    except OSError:
        pass

    total = sum(counts.values())
    print(f"OK: {total} AT definitions tagged (CSP={counts['CSP']}, GOP={counts['GOP']}).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
