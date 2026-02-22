#!/usr/bin/env python3
"""Scaffold a skeleton proof_graph.json from prd.json + CONTRACT.md.

Usage:
  python3 python/proof_graph/scaffold.py <STORY_ID> \
      [--prd-path plans/prd.json] \
      [--contract-path specs/CONTRACT.md] \
      [--output-dir artifacts/story/<ID>/]
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path


def _git_head_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "0" * 40


def _load_prd_item(prd_path: Path, story_id: str) -> dict | None:
    if not prd_path.is_file():
        return None
    data = json.loads(prd_path.read_text(encoding="utf-8"))
    for item in data.get("items", []):
        if item.get("id") == story_id:
            return item
    return None


def scaffold(
    story_id: str,
    prd_path: Path,
    contract_path: Path,
    output_dir: Path,
) -> Path:
    """Generate a skeleton proof_graph.json and return its path."""
    output_dir.mkdir(parents=True, exist_ok=True)

    item = _load_prd_item(prd_path, story_id)
    category = item.get("category", "<FILL>") if item else "<FILL>"
    enforcement_point = item.get("enforcement_point", "<FILL>") if item else "<FILL>"
    scope_touch = item.get("scope", {}).get("touch", []) if item else []
    loss_mode_raw = item.get("loss_mode", {}) if item else {}

    # Pre-populate ATs from enforcing_contract_ats
    eca = item.get("enforcing_contract_ats", []) if item else []
    at_entries = []
    head_sha = _git_head_sha()

    for at_id in eca:
        at_entries.append({
            "at_id": at_id,
            "enforcement": {
                "status": "<FILL>",
                "evidence": [],
            },
            "tests": [],
            "wiring": {
                "status": "<FILL>",
                "evidence": "<FILL>",
            },
            "observability": {
                "metric": "<FILL>",
                "alert": "<FILL>",
            },
            "premortem_checks": {
                "stoplight": "<FILL>",
                "sections_filled": 0,
            },
            "at_verdict": {
                "verdict": "<FILL>",
                "severity": "<FILL>",
                "rationale": "<FILL>",
            },
        })

    # Determine safety_critical based on category/loss_mode
    safety_critical = category not in ("policy", "certification", "<FILL>")

    graph = {
        "schema_version": 1,
        "head_sha": head_sha,
        "generated_at": datetime.now(timezone.utc).isoformat(),
        "story_meta": {
            "story_id": story_id,
            "category": category,
            "enforcement_point": enforcement_point,
            "loss_mode": {
                "worst_case": loss_mode_raw.get("worst_case", "<FILL>"),
                "fail_closed_cap": loss_mode_raw.get("fail_closed_cap", "<FILL>"),
                "drift_metric": loss_mode_raw.get("drift_metric", "<FILL>"),
                "level": "<FILL>",
            },
            "safety_critical": safety_critical,
            "scope_touch": scope_touch,
        },
        "ats": at_entries,
        "story_verdict": {
            "reconciliation_status": "<FILL>",
            "blocking_count": 0,
            "hardening_count": 0,
            "summary": "<FILL>",
        },
        "debt_register": [],
    }

    out_path = output_dir / "proof_graph.json"
    out_path.write_text(json.dumps(graph, indent=2) + "\n", encoding="utf-8")
    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scaffold a skeleton proof_graph.json."
    )
    parser.add_argument("story_id", help="Story ID (e.g. S1-007)")
    parser.add_argument(
        "--prd-path", default="plans/prd.json",
        help="Path to prd.json",
    )
    parser.add_argument(
        "--contract-path", default="specs/CONTRACT.md",
        help="Path to CONTRACT.md",
    )
    parser.add_argument(
        "--output-dir", default=None,
        help="Output directory (default: artifacts/story/<ID>/)",
    )
    args = parser.parse_args(argv)

    output_dir = Path(args.output_dir) if args.output_dir else Path(f"artifacts/story/{args.story_id}")

    out_path = scaffold(
        story_id=args.story_id,
        prd_path=Path(args.prd_path),
        contract_path=Path(args.contract_path),
        output_dir=output_dir,
    )
    print(f"Scaffolded: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
