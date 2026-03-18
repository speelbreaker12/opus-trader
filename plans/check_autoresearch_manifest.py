#!/usr/bin/env python3
"""CI gate: verify autoresearch context_manifest.json is fresh against live CONTRACT.md.

Fails with exit code 2 if the manifest hash does not match the current CONTRACT.md,
prompting the developer to run:
  autoresearch/skills/harness.sh contract refresh-common
"""
from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str, exit_code: int = 2) -> None:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    manifest_path = repo_root / "autoresearch" / "contract" / "common" / "context_manifest.json"
    contract_path = repo_root / "specs" / "CONTRACT.md"

    if not manifest_path.exists():
        fail(f"context_manifest.json not found: {manifest_path}")

    if not contract_path.exists():
        fail(f"CONTRACT.md not found: {contract_path}")

    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in context_manifest.json: {exc}")
        return 1

    if not isinstance(manifest, dict):
        fail("context_manifest.json must be a JSON object")

    legacy_hash = manifest.get("contract_content_hash", "")
    recorded_hash = manifest.get("common_contract_hash", legacy_hash)

    if not isinstance(recorded_hash, str) or len(recorded_hash) != 64:
        fail(
            "context_manifest.json missing valid common_contract_hash — "
            "run: autoresearch/skills/harness.sh contract refresh-common"
        )

    current_hash = sha256_file(contract_path)
    if current_hash != recorded_hash:
        fail(
            f"context_manifest.json is stale: recorded hash {recorded_hash[:12]}… "
            f"does not match live CONTRACT.md {current_hash[:12]}… — "
            "run: autoresearch/skills/harness.sh contract refresh-common"
        )

    print(f"OK: context_manifest.json matches live CONTRACT.md ({current_hash[:12]}…)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
