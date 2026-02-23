#!/usr/bin/env python3
"""CLI entry point for proof graph validation.

Exit codes:
  0 = pass (no errors)
  1 = fail (errors found)
  2 = usage/schema error (unsupported version, bad args)
  3 = file/parse error (missing file, invalid JSON)
  20 = trading halt (BLOCKING findings + recomputed halt condition is true)
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

# Allow running as `python3 python/proof_graph/validate.py` from repo root
if __name__ == "__main__":
    _this = Path(__file__).resolve()
    _pkg_parent = str(_this.parent.parent.parent)
    # Remove script directory to avoid shadowing stdlib modules
    _script_dir = str(_this.parent)
    if _script_dir in sys.path:
        sys.path.remove(_script_dir)
    if _pkg_parent not in sys.path:
        sys.path.insert(0, _pkg_parent)

from python.proof_graph.contract_ats import extract_contract_ats
from python.proof_graph.rules import (
    Finding, ValidationContext, validate, compute_trading_halt,
)
from python.proof_graph.schema import ProofGraph, ProofGraphParseError
from python.proof_graph.enums import Severity


def _load_prd_items(prd_path: Path) -> dict[str, Any]:
    """Return dict mapping story_id → prd item."""
    data = json.loads(prd_path.read_text(encoding="utf-8"))
    return {item["id"]: item for item in data.get("items", [])}


def _count_findings(
    findings: list[Finding], strict: bool,
) -> tuple[int, int]:
    """Return (errors, warnings) counts."""
    errors = 0
    warnings = 0
    for f in findings:
        if f.severity == Severity.BLOCKING:
            errors += 1
        elif f.severity == Severity.HARDENING:
            if strict:
                errors += 1
            else:
                warnings += 1
        else:
            warnings += 1
    return errors, warnings


def _compute_exit_code(
    errors: int, ctx: ValidationContext,
) -> int:
    """Determine exit code: 20 for trading halt, 1 for errors, 0 for clean.

    Exit 20 fires when:
      - There are BLOCKING findings (errors > 0), AND
      - schema_version >= 2, AND
      - The *recomputed* halt condition is true (not the stored value)

    Note: --strict promotes HARDENING to errors, which can trigger exit 20
    if the halt condition is also met. A graph with trading_halt_trigger=true
    but no BLOCKING findings exits 0 (the stored flag alone is not enough).
    """
    if errors == 0:
        return 0
    if ctx.graph.schema_version >= 2 and compute_trading_halt(ctx):
        return 20
    return 1


def _findings_to_json(
    findings: list[Finding], strict: bool, ctx: ValidationContext,
) -> dict[str, Any]:
    errors, warnings = _count_findings(findings, strict)
    exit_code = _compute_exit_code(errors, ctx)
    return {
        "findings": [
            {
                "severity": f.severity.value,
                "rule": f.rule,
                "at_id": f.at_id,
                "message": f.message,
                "field_path": f.field_path,
            }
            for f in findings
        ],
        "summary": {"errors": errors, "warnings": warnings},
        "trading_halt": exit_code == 20,
        "exit_code": exit_code,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Validate a proof_graph.json file."
    )
    parser.add_argument("proof_graph", help="Path to proof_graph.json")
    parser.add_argument(
        "--contract-path", default="specs/CONTRACT.md",
        help="Path to CONTRACT.md (default: specs/CONTRACT.md)",
    )
    parser.add_argument(
        "--prd-path", default="plans/prd.json",
        help="Path to prd.json (default: plans/prd.json)",
    )
    parser.add_argument(
        "--strict", action="store_true",
        help="Promote WARN to ERROR (exit 1 on warnings)",
    )
    parser.add_argument(
        "--json-output", action="store_true",
        help="Output findings as JSON",
    )
    args = parser.parse_args(argv)

    pg_path = Path(args.proof_graph)
    if not pg_path.is_file():
        print(f"ERROR: proof_graph.json not found: {pg_path}", file=sys.stderr)
        return 3

    try:
        raw = json.loads(pg_path.read_text(encoding="utf-8"))
    except (json.JSONDecodeError, OSError) as e:
        print(f"ERROR: failed to read/parse {pg_path}: {e}", file=sys.stderr)
        return 3

    try:
        graph = ProofGraph.from_dict(raw)
    except ProofGraphParseError as e:
        if "unsupported schema_version" in str(e):
            print(f"ERROR: {e}", file=sys.stderr)
            return 2
        print(f"ERROR: schema parse error: {e}", file=sys.stderr)
        return 3

    # Build context
    contract_path = Path(args.contract_path)
    contract_ats: set[str] = set()
    if contract_path.is_file():
        contract_ats = extract_contract_ats(contract_path)
    else:
        print(
            f"ERROR: CONTRACT.md not found at {contract_path} (fail-closed)",
            file=sys.stderr,
        )
        return 3

    prd_path = Path(args.prd_path)
    prd_items: dict[str, Any] = {}
    if prd_path.is_file():
        prd_items = _load_prd_items(prd_path)
    else:
        print(
            f"WARN: prd.json not found at {prd_path} (R-014 skipped)",
            file=sys.stderr,
        )

    ctx = ValidationContext(
        graph=graph,
        contract_ats=contract_ats,
        prd_items=prd_items,
    )

    findings = validate(ctx)

    if args.json_output:
        result = _findings_to_json(findings, args.strict, ctx)
        print(json.dumps(result, indent=2))
        return result["exit_code"]

    # Human-readable output
    errors, warnings = _count_findings(findings, args.strict)
    for f in findings:
        if f.severity == Severity.BLOCKING:
            label = "ERROR"
        elif f.severity == Severity.HARDENING:
            if args.strict:
                label = "ERROR (--strict)"
            else:
                label = "WARN"
        else:
            label = "INFO"
        at_part = f" [{f.at_id}]" if f.at_id else ""
        print(f"  {label} {f.rule}{at_part}: {f.message}")

    exit_code = _compute_exit_code(errors, ctx)
    if exit_code == 0:
        print(f"OK: proof graph valid for {graph.story_meta.story_id}")
    else:
        print(f"\nSummary: {errors} error(s), {warnings} warning(s)")
        if exit_code == 20:
            print("CRITICAL: TRADING HALT condition detected", file=sys.stderr)

    return exit_code


if __name__ == "__main__":
    sys.exit(main())
