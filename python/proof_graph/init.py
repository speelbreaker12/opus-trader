#!/usr/bin/env python3
"""V2 skeleton builder for proof_graph.json.

Replaces scaffold.py for V2 graphs. Emits schema_version=2 with
structured evidence stubs, empty caller chains, and premortem
cross-check fields parsed from premortem.md.

Usage:
  python3 python/proof_graph/init.py S1-007 \
      [--prd-path plans/prd.json] \
      [--contract-path specs/CONTRACT.md] \
      [--premortem-path reviews/premortems/S1-007_premortem.md] \
      [--output-dir artifacts/story/S1-007/]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

INIT_TOOL_VERSION = "2.0.0"


def _git_head_sha() -> str:
    try:
        result = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        )
        return result.stdout.strip()
    except (subprocess.CalledProcessError, FileNotFoundError):
        return "0" * 40


def _load_prd_item(prd_path: Path, story_id: str) -> dict[str, Any] | None:
    if not prd_path.is_file():
        return None
    data = json.loads(prd_path.read_text(encoding="utf-8"))
    for item in data.get("items", []):
        if item.get("id") == story_id:
            return item
    return None


def _parse_premortem(premortem_path: Path) -> dict[str, str | None]:
    """Extract section5/section4/section2 from a premortem file if present.

    Returns dict with keys:
      section5_wrong_impl_blocked: "ALL" | "PARTIAL" | "NONE" | None
      section4_decision_match: "YES" | "NO" | "PARTIAL" | None
      section2_assumptions: "ALL_VALIDATED" | "PARTIAL" | "NONE" | None
    """
    result: dict[str, str | None] = {
        "section5_wrong_impl_blocked": None,
        "section4_decision_match": None,
        "section2_assumptions": None,
    }

    if not premortem_path.is_file():
        return result

    try:
        text = premortem_path.read_text(encoding="utf-8")
    except OSError:
        return result

    # Look for stoplight values in premortem sections
    # Section 5: wrong impl blocked
    m = re.search(
        r'(?:section\s*5|wrong.impl).*?:\s*(ALL|PARTIAL|NONE)',
        text, re.IGNORECASE,
    )
    if m:
        result["section5_wrong_impl_blocked"] = m.group(1).upper()

    # Section 4: decision match
    m = re.search(
        r'(?:section\s*4|decision.match).*?:\s*(YES|NO|PARTIAL)',
        text, re.IGNORECASE,
    )
    if m:
        result["section4_decision_match"] = m.group(1).upper()

    # Section 2: assumptions
    m = re.search(
        r'(?:section\s*2|assumptions?).*?:\s*(ALL_VALIDATED|PARTIAL|NONE)',
        text, re.IGNORECASE,
    )
    if m:
        result["section2_assumptions"] = m.group(1).upper()

    return result


def init_v2(
    story_id: str,
    prd_path: Path,
    contract_path: Path,
    output_dir: Path,
    premortem_path: Path | None = None,
) -> Path:
    """Generate a V2 skeleton proof_graph.json and return its path."""
    output_dir.mkdir(parents=True, exist_ok=True)

    item = _load_prd_item(prd_path, story_id)
    category = item.get("category", "<FILL>") if item else "<FILL>"
    enforcement_point = item.get("enforcement_point", "<FILL>") if item else "<FILL>"
    scope_touch = item.get("scope", {}).get("touch", []) if item else []
    loss_mode_raw = item.get("loss_mode", {}) if item else {}

    # Determine safety_critical based on category/loss_mode
    safety_critical = category not in ("policy", "certification", "<FILL>")

    resolved_premortem_path = (
        premortem_path
        if premortem_path is not None
        else Path("reviews/premortems") / f"{story_id}_premortem.md"
    )

    # Parse premortem sections
    premortem_vals: dict[str, str | None] = {
        "section5_wrong_impl_blocked": None,
        "section4_decision_match": None,
        "section2_assumptions": None,
    }
    if resolved_premortem_path:
        premortem_vals = _parse_premortem(resolved_premortem_path)

    # Pre-populate ATs from enforcing_contract_ats
    eca = item.get("enforcing_contract_ats", []) if item else []
    at_entries: list[dict[str, Any]] = []
    head_sha = _git_head_sha()

    for at_id in eca:
        # Build evidence_entries stubs from scope_touch
        evidence_entries = [
            {"file": f, "line_start": 1, "line_end": 1, "symbol": "<FILL>"}
            for f in scope_touch
        ]

        premortem_checks: dict[str, Any] = {
            "stoplight": "<FILL>",
            "sections_filled": 0,
        }
        if premortem_vals["section5_wrong_impl_blocked"] is not None:
            premortem_checks["section5_wrong_impl_blocked"] = premortem_vals[
                "section5_wrong_impl_blocked"
            ]
        if premortem_vals["section4_decision_match"] is not None:
            premortem_checks["section4_decision_match"] = premortem_vals[
                "section4_decision_match"
            ]
        if premortem_vals["section2_assumptions"] is not None:
            premortem_checks["section2_assumptions"] = premortem_vals[
                "section2_assumptions"
            ]

        at_entries.append({
            "at_id": at_id,
            "enforcement": {
                "status": "<FILL>",
                "evidence": [],
                "evidence_entries": evidence_entries,
            },
            "tests": [],
            "wiring": {
                "status": "<FILL>",
                "evidence": "<FILL>",
                "caller_chain": [],
                "entrypoint": "",
                "proof_type": "",
            },
            "observability": {
                "metric": "<FILL>",
                "alert": "<FILL>",
            },
            "premortem_checks": premortem_checks,
            "at_verdict": {
                "verdict": "<FILL>",
                "severity": "<FILL>",
                "rationale": "<FILL>",
            },
            "extra_discovered": False,
        })

    # Build hints per AT
    hints: dict[str, dict[str, Any]] = {}
    loss_level = loss_mode_raw.get("level", "<FILL>")
    for at_id in eca:
        hints[at_id] = {
            "safety_critical": safety_critical,
            "loss_mode_level": loss_level,
        }

    graph: dict[str, Any] = {
        "schema_version": 2,
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
                "level": loss_level,
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
            "trading_halt_trigger": False,
        },
        "debt_register": [],
        "meta": {
            "hints": hints,
            "init_tool_version": INIT_TOOL_VERSION,
            "init_timestamp": datetime.now(timezone.utc).isoformat(),
        },
    }

    out_path = output_dir / "proof_graph.json"
    out_path.write_text(json.dumps(graph, indent=2) + "\n", encoding="utf-8")
    return out_path


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Initialize a V2 skeleton proof_graph.json."
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
        "--premortem-path", default=None,
        help=(
            "Canonical premortem file path "
            "(default: reviews/premortems/<ID>_premortem.md)"
        ),
    )
    parser.add_argument(
        "--output-dir", default=None,
        help="Output directory (default: artifacts/story/<ID>/)",
    )
    args = parser.parse_args(argv)

    output_dir = (
        Path(args.output_dir) if args.output_dir
        else Path(f"artifacts/story/{args.story_id}")
    )
    premortem_path = Path(args.premortem_path) if args.premortem_path else None

    out_path = init_v2(
        story_id=args.story_id,
        prd_path=Path(args.prd_path),
        contract_path=Path(args.contract_path),
        output_dir=output_dir,
        premortem_path=premortem_path,
    )
    print(f"Initialized V2: {out_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
