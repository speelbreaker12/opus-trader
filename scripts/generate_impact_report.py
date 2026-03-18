#!/usr/bin/env python3
"""
Contract Change Impact Report Generator.

Detects CONTRACT.md changes, identifies affected clause IDs (CSP-###),
and generates a machine-readable Impact Report listing downstream artifacts
that need updates.

Usage:
  python scripts/generate_impact_report.py [--base origin/main] [--json]

Exit codes:
  0 = no impact (or all items resolved)
  1 = impact items require attention
  2 = error
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Set

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(2)


@dataclass
class ImpactItem:
    clause_id: str
    clause_name: str
    change_type: str  # "added" | "modified" | "removed"
    downstream: Dict[str, List[str]] = field(default_factory=dict)  # {plan: [...], code: [...], tests: [...]}
    resolved: bool = False


@dataclass
class ImpactReport:
    contract_changed: bool = False
    affected_clauses: List[str] = field(default_factory=list)
    items: List[ImpactItem] = field(default_factory=list)
    unresolved_count: int = 0


# Regex patterns
CSP_ID_RE = re.compile(r'<!--\s*(CSP-\d{3})\s*-->')
DIFF_ADD_RE = re.compile(r'^\+.*<!--\s*(CSP-\d{3})\s*-->')
DIFF_DEL_RE = re.compile(r'^-.*<!--\s*(CSP-\d{3})\s*-->')
DIFF_CONTEXT_RE = re.compile(r'^[@\s].*<!--\s*(CSP-\d{3})\s*-->')


def run_git_diff(base_ref: str, file_path: str) -> Optional[str]:
    """Get git diff for a specific file."""
    try:
        # Try two-dot first (works for uncommitted + committed changes)
        result = subprocess.run(
            ["git", "diff", base_ref, "--", file_path],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout

        # Try three-dot for branch comparisons
        result = subprocess.run(
            ["git", "diff", f"{base_ref}...HEAD", "--", file_path],
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode == 0 and result.stdout.strip():
            return result.stdout

        return None
    except Exception:
        return None


def get_changed_files(base_ref: str) -> Set[str]:
    """Get list of changed files."""
    try:
        result = subprocess.run(
            ["git", "diff", "--name-only", f"{base_ref}...HEAD"],
            capture_output=True,
            text=True,
            check=False,
        )
        files = set(result.stdout.strip().split("\n")) if result.stdout.strip() else set()

        # Also check staged/unstaged
        for cmd in [["git", "diff", "--name-only", "--cached"], ["git", "diff", "--name-only"]]:
            result = subprocess.run(cmd, capture_output=True, text=True, check=False)
            if result.stdout.strip():
                files.update(result.stdout.strip().split("\n"))

        return {f for f in files if f}
    except Exception:
        return set()


def parse_diff_for_clauses(diff_text: str) -> Dict[str, str]:
    """Parse diff to find affected clause IDs and their change type."""
    affected: Dict[str, str] = {}

    for line in diff_text.split("\n"):
        # Check for added lines with CSP IDs
        match = DIFF_ADD_RE.match(line)
        if match:
            clause_id = match.group(1)
            if clause_id not in affected:
                affected[clause_id] = "added"
            continue

        # Check for removed lines with CSP IDs
        match = DIFF_DEL_RE.match(line)
        if match:
            clause_id = match.group(1)
            if clause_id not in affected:
                affected[clause_id] = "removed"
            elif affected[clause_id] == "added":
                affected[clause_id] = "modified"
            continue

        # Check context lines (modified nearby)
        match = DIFF_CONTEXT_RE.match(line)
        if match:
            clause_id = match.group(1)
            if clause_id not in affected:
                affected[clause_id] = "modified"

    return affected


def load_trace(trace_path: Path) -> Optional[dict]:
    """Load TRACE.yaml."""
    try:
        return yaml.safe_load(trace_path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"WARN: Failed to load {trace_path}: {e}", file=sys.stderr)
        return None


def check_downstream_changes(
    clause_id: str,
    trace: dict,
    changed_files: Set[str],
) -> Dict[str, List[str]]:
    """Check which downstream artifacts were also changed."""
    clause = trace.get("clauses", {}).get(clause_id, {})
    downstream = {
        "plan": clause.get("plan", []) or [],
        "code": clause.get("code", []) or [],
        "tests": clause.get("tests", []) or [],
        "prd": clause.get("prd", []) or [],
    }

    # Mark which downstream items were changed
    result = {}
    for category, items in downstream.items():
        result[category] = []
        for item in items:
            # Check if file was changed (for plan/code paths)
            if item.startswith("AT-"):
                # AT codes - would need to check if test implementation changed
                result[category].append(f"{item} (verify)")
            elif any(item in f or f.endswith(item.lstrip("./")) for f in changed_files):
                result[category].append(f"{item} (updated)")
            else:
                result[category].append(f"{item} (needs review)")

    return result


def generate_report(
    base_ref: str,
    contract_path: Path,
    trace_path: Path,
) -> ImpactReport:
    """Generate the impact report."""
    report = ImpactReport()

    # Get changed files
    changed_files = get_changed_files(base_ref)

    # Check if CONTRACT.md changed
    if str(contract_path) not in changed_files and contract_path.name not in changed_files:
        # Try relative path matching
        contract_changed = any(
            contract_path.name in f or str(contract_path) in f
            for f in changed_files
        )
        if not contract_changed:
            return report

    report.contract_changed = True

    # Get diff and parse for affected clauses
    diff_text = run_git_diff(base_ref, str(contract_path))
    if not diff_text:
        # No diff available, but file is in changed list
        return report

    affected_clauses = parse_diff_for_clauses(diff_text)
    if not affected_clauses:
        return report

    report.affected_clauses = list(affected_clauses.keys())

    # Load TRACE.yaml
    trace = load_trace(trace_path)
    if not trace:
        # Can't determine downstream without trace
        for clause_id, change_type in affected_clauses.items():
            report.items.append(ImpactItem(
                clause_id=clause_id,
                clause_name="Unknown (TRACE.yaml missing)",
                change_type=change_type,
                downstream={},
                resolved=False,
            ))
            report.unresolved_count += 1
        return report

    # Build impact items
    for clause_id, change_type in affected_clauses.items():
        clause_data = trace.get("clauses", {}).get(clause_id, {})
        clause_name = clause_data.get("name", "Unknown")

        downstream = check_downstream_changes(clause_id, trace, changed_files)

        # Check if resolved (all downstream items updated or verified)
        needs_review = any(
            "(needs review)" in item
            for items in downstream.values()
            for item in items
        )

        item = ImpactItem(
            clause_id=clause_id,
            clause_name=clause_name,
            change_type=change_type,
            downstream=downstream,
            resolved=not needs_review,
        )
        report.items.append(item)

        if not item.resolved:
            report.unresolved_count += 1

    return report


def format_report_text(report: ImpactReport) -> str:
    """Format report as human-readable text."""
    lines = []
    lines.append("=" * 60)
    lines.append("CONTRACT CHANGE IMPACT REPORT")
    lines.append("=" * 60)
    lines.append("")

    if not report.contract_changed:
        lines.append("No CONTRACT.md changes detected.")
        return "\n".join(lines)

    if not report.affected_clauses:
        lines.append("CONTRACT.md changed but no CSP clause IDs affected.")
        return "\n".join(lines)

    lines.append(f"Affected clauses: {len(report.affected_clauses)}")
    lines.append(f"Unresolved items: {report.unresolved_count}")
    lines.append("")

    for item in report.items:
        status = "RESOLVED" if item.resolved else "NEEDS ATTENTION"
        lines.append(f"[{status}] {item.clause_id}: {item.clause_name}")
        lines.append(f"  Change type: {item.change_type}")

        for category, artifacts in item.downstream.items():
            if artifacts:
                lines.append(f"  {category}:")
                for artifact in artifacts:
                    lines.append(f"    - {artifact}")
        lines.append("")

    if report.unresolved_count > 0:
        lines.append("-" * 60)
        lines.append("ACTION REQUIRED:")
        lines.append("Update downstream artifacts marked '(needs review)' or")
        lines.append("add them to the changeset to resolve this report.")

    return "\n".join(lines)


def format_report_json(report: ImpactReport) -> str:
    """Format report as JSON."""
    data = {
        "contract_changed": report.contract_changed,
        "affected_clauses": report.affected_clauses,
        "unresolved_count": report.unresolved_count,
        "items": [
            {
                "clause_id": item.clause_id,
                "clause_name": item.clause_name,
                "change_type": item.change_type,
                "downstream": item.downstream,
                "resolved": item.resolved,
            }
            for item in report.items
        ],
    }
    return json.dumps(data, indent=2)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate Contract Change Impact Report"
    )
    parser.add_argument(
        "--base",
        default="origin/main",
        help="Base ref for diff (default: origin/main)",
    )
    parser.add_argument(
        "--contract",
        type=Path,
        default=Path("specs/CONTRACT.md"),
        help="Path to CONTRACT.md",
    )
    parser.add_argument(
        "--trace",
        type=Path,
        default=Path("specs/TRACE.yaml"),
        help="Path to TRACE.yaml",
    )
    parser.add_argument(
        "--json",
        action="store_true",
        help="Output as JSON",
    )
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Exit 1 if any unresolved items",
    )
    args = parser.parse_args()

    report = generate_report(args.base, args.contract, args.trace)

    if args.json:
        print(format_report_json(report))
    else:
        print(format_report_text(report))

    if args.strict and report.unresolved_count > 0:
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())
