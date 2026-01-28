#!/usr/bin/env python3
"""
CSP Clause Traceability Validator.

Validates:
1. Every CSP-### in CONTRACT.md has entry in TRACE.yaml
2. Every TRACE entry has at least one of: plan, code, or tests
3. AT references in TRACE resolve in CONTRACT.md
4. Coverage % doesn't decrease from baseline (when --baseline provided)

Exit codes:
0 = pass (no errors)
2 = errors found
"""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional, Set

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(2)


@dataclass(frozen=True)
class Finding:
    severity: str  # "ERROR" | "WARN"
    code: str
    message: str


# Regex to find CSP-### comments in CONTRACT.md
CSP_ID_RE = re.compile(r'<!--\s*(CSP-\d{3})\s*-->')
# Regex to find AT-### references
AT_ID_RE = re.compile(r'\bAT-(\d{1,4})\b')


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def extract_csp_ids_from_contract(contract_text: str) -> Set[str]:
    """Extract all CSP-### IDs from CONTRACT.md."""
    return set(CSP_ID_RE.findall(contract_text))


def extract_at_ids_from_contract(contract_text: str) -> Set[str]:
    """Extract all AT-### IDs defined in CONTRACT.md."""
    return set(f"AT-{m}" for m in AT_ID_RE.findall(contract_text))


def load_trace(trace_path: Path) -> Optional[dict]:
    """Load and parse TRACE.yaml."""
    try:
        return yaml.safe_load(read_text(trace_path))
    except yaml.YAMLError as e:
        print(f"ERROR: Failed to parse {trace_path}: {e}", file=sys.stderr)
        return None


def validate_trace(
    trace: dict,
    contract_csp_ids: Set[str],
    contract_at_ids: Set[str],
    strict: bool = False,
) -> List[Finding]:
    """Validate TRACE.yaml against CONTRACT.md."""
    findings: List[Finding] = []
    clauses = trace.get("clauses", {})
    trace_csp_ids = set(clauses.keys())

    # Check 1: Every CSP-### in CONTRACT.md has entry in TRACE.yaml
    missing_in_trace = contract_csp_ids - trace_csp_ids
    for csp_id in sorted(missing_in_trace):
        findings.append(Finding(
            severity="ERROR",
            code="MISSING_TRACE_ENTRY",
            message=f"{csp_id} found in CONTRACT.md but missing from TRACE.yaml",
        ))

    # Check 2: Every TRACE entry has at least one of: plan, code, or tests
    for csp_id, clause in clauses.items():
        plan = clause.get("plan", []) or []
        code = clause.get("code", []) or []
        tests = clause.get("tests", []) or []

        if not plan and not code and not tests:
            findings.append(Finding(
                severity="WARN" if not strict else "ERROR",
                code="UNMAPPED_CLAUSE",
                message=f"{csp_id} has no plan, code, or test mappings",
            ))

        # Check 3: AT references in TRACE resolve in CONTRACT.md
        for at_ref in tests:
            if at_ref.startswith("AT-") and at_ref not in contract_at_ids:
                findings.append(Finding(
                    severity="WARN",
                    code="UNRESOLVED_AT_REF",
                    message=f"{csp_id} references {at_ref} which is not defined in CONTRACT.md",
                ))

    # Check for orphan entries in TRACE that aren't in CONTRACT
    orphan_entries = trace_csp_ids - contract_csp_ids
    for csp_id in sorted(orphan_entries):
        findings.append(Finding(
            severity="WARN",
            code="ORPHAN_TRACE_ENTRY",
            message=f"{csp_id} in TRACE.yaml but not found in CONTRACT.md",
        ))

    return findings


def compute_coverage(trace: dict) -> Dict[str, any]:
    """Compute coverage statistics."""
    clauses = trace.get("clauses", {})
    total = len(clauses)
    if total == 0:
        return {"total": 0, "mapped": 0, "partial": 0, "unmapped": 0, "pct": 0.0}

    mapped = 0
    partial = 0
    unmapped = 0

    for clause in clauses.values():
        plan = clause.get("plan", []) or []
        code = clause.get("code", []) or []
        tests = clause.get("tests", []) or []

        has_plan = len(plan) > 0
        has_code = len(code) > 0
        has_tests = len(tests) > 0

        if has_plan and has_code and has_tests:
            mapped += 1
        elif has_plan or has_code or has_tests:
            partial += 1
        else:
            unmapped += 1

    pct = ((mapped + partial) / total) * 100 if total > 0 else 0.0

    return {
        "total": total,
        "mapped": mapped,
        "partial": partial,
        "unmapped": unmapped,
        "pct": round(pct, 1),
    }


def check_coverage_regression(
    current_pct: float,
    baseline_pct: float,
) -> Optional[Finding]:
    """Check if coverage has regressed from baseline."""
    if current_pct < baseline_pct:
        return Finding(
            severity="ERROR",
            code="COVERAGE_REGRESSION",
            message=f"Coverage decreased from {baseline_pct}% to {current_pct}%",
        )
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Validate CSP clause traceability"
    )
    parser.add_argument(
        "--contract",
        type=Path,
        default=Path("specs/CONTRACT.md"),
        help="Path to CONTRACT.md (default: specs/CONTRACT.md)",
    )
    parser.add_argument(
        "--trace",
        type=Path,
        default=Path("specs/TRACE.yaml"),
        help="Path to TRACE.yaml (default: specs/TRACE.yaml)",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Treat UNMAPPED clauses as errors (not warnings)",
    )
    parser.add_argument(
        "--baseline",
        type=float,
        default=None,
        help="Baseline coverage %% - fail if current coverage is lower",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output results as JSON",
    )
    args = parser.parse_args()

    # Validate paths exist
    if not args.contract.exists():
        print(f"ERROR: Contract file not found: {args.contract}", file=sys.stderr)
        return 2

    if not args.trace.exists():
        print(f"ERROR: Trace file not found: {args.trace}", file=sys.stderr)
        return 2

    # Load files
    contract_text = read_text(args.contract)
    trace = load_trace(args.trace)
    if trace is None:
        return 2

    # Extract IDs from contract
    contract_csp_ids = extract_csp_ids_from_contract(contract_text)
    contract_at_ids = extract_at_ids_from_contract(contract_text)

    # Validate
    findings = validate_trace(trace, contract_csp_ids, contract_at_ids, args.strict)

    # Compute coverage
    coverage = compute_coverage(trace)

    # Check coverage regression
    if args.baseline is not None:
        regression = check_coverage_regression(coverage["pct"], args.baseline)
        if regression:
            findings.append(regression)

    # Output results
    errors = [f for f in findings if f.severity == "ERROR"]
    warnings = [f for f in findings if f.severity == "WARN"]

    if args.json:
        import json
        result = {
            "coverage": coverage,
            "errors": [{"code": f.code, "message": f.message} for f in errors],
            "warnings": [{"code": f.code, "message": f.message} for f in warnings],
        }
        print(json.dumps(result, indent=2))
    else:
        print(f"CSP Trace Validation")
        print(f"====================")
        print(f"Contract: {args.contract}")
        print(f"Trace: {args.trace}")
        print()
        print(f"Coverage: {coverage['pct']}%")
        print(f"  Total clauses: {coverage['total']}")
        print(f"  Fully mapped: {coverage['mapped']}")
        print(f"  Partial: {coverage['partial']}")
        print(f"  Unmapped: {coverage['unmapped']}")
        print()

        if errors:
            print(f"ERRORS ({len(errors)}):")
            for f in errors:
                print(f"  [{f.code}] {f.message}")
            print()

        if warnings:
            print(f"WARNINGS ({len(warnings)}):")
            for f in warnings:
                print(f"  [{f.code}] {f.message}")
            print()

        if not errors:
            print("PASS: No errors found")
        else:
            print(f"FAIL: {len(errors)} error(s) found")

    return 2 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
