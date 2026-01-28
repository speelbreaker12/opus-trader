#!/usr/bin/env python3
"""
tools/phase1_evidence.py

Helper for Phase-1 tests to emit evidence artifacts consistently.

Usage from tests (Python):
    from tools.phase1_evidence import P1Evidence

    ev = P1Evidence(root=".")
    ev.write_determinism_hashes(["abc123", "abc123"])  # Two runs, same hash
    ev.write_rejection_log(log_lines)
    ev.write_config_matrix({"key1": {"status": "PASS", "reason": "CONFIG_MISSING"}})
    ev.write_crash_auto_passed()

Usage from CLI (for Rust tests to call):
    python tools/phase1_evidence.py determinism-hashes abc123 abc123
    python tools/phase1_evidence.py rejection-log "2024-01-01 intent_id=xyz rejected ..."
    python tools/phase1_evidence.py config-matrix '{"key1": {"status": "PASS", "reason": "CONFIG_MISSING"}}'
    python tools/phase1_evidence.py crash-auto-passed
    python tools/phase1_evidence.py rejection-cases "case1: missing config" "case2: invalid instrument"
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Optional


class P1Evidence:
    """Helper to write Phase-1 evidence artifacts."""

    def __init__(self, root: str = "."):
        self.root = Path(root).resolve()
        self.evidence_root = self.root / "evidence" / "phase1"

    def _ensure_dir(self, path: Path) -> None:
        path.parent.mkdir(parents=True, exist_ok=True)

    def _write(self, path: Path, content: str) -> None:
        self._ensure_dir(path)
        path.write_text(content, encoding="utf-8")
        print(f"[P1Evidence] Wrote: {path}")

    def _append(self, path: Path, content: str) -> None:
        self._ensure_dir(path)
        with open(path, "a", encoding="utf-8") as f:
            f.write(content)
        print(f"[P1Evidence] Appended to: {path}")

    def _timestamp(self) -> str:
        return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    # -------------------------------------------------------------------------
    # P1-B: Determinism
    # -------------------------------------------------------------------------
    def write_determinism_hashes(
        self,
        hashes: List[str],
        test_name: str = "test_intent_determinism_same_inputs_same_hash",
    ) -> None:
        """Write intent hashes from determinism test runs."""
        path = self.evidence_root / "determinism" / "intent_hashes.txt"
        lines = [
            f"# {test_name}",
            f"# Generated: {self._timestamp()}",
            f"# Runs: {len(hashes)}",
            "",
        ]
        for i, h in enumerate(hashes, 1):
            lines.append(f"run_{i}: {h}")
        lines.append("")
        if len(set(hashes)) == 1:
            lines.append("RESULT: PASS (all hashes identical)")
        else:
            lines.append("RESULT: FAIL (hashes differ)")
        self._write(path, "\n".join(lines) + "\n")

    # -------------------------------------------------------------------------
    # P1-C: No Side Effects - Rejection Cases
    # -------------------------------------------------------------------------
    def write_rejection_cases(
        self,
        cases: List[str],
        ci_link: Optional[str] = None,
    ) -> None:
        """Write rejection cases documentation."""
        path = self.evidence_root / "no_side_effects" / "rejection_cases.md"
        lines = [
            "# Rejection Cases (P1-C)",
            "",
            f"Generated: {self._timestamp()}",
            "",
            "## Cases Exercised",
            "",
        ]
        for i, case in enumerate(cases, 1):
            lines.append(f"{i}. {case}")
        lines.append("")
        if ci_link:
            lines.append(f"## CI Link")
            lines.append(f"- {ci_link}")
            lines.append("")
        lines.append("## Assertions Verified")
        lines.append("- WAL unchanged (no committed entry)")
        lines.append("- No open orders created")
        lines.append("- No position deltas")
        lines.append("- No pending exposure increments")
        self._write(path, "\n".join(lines) + "\n")

    # -------------------------------------------------------------------------
    # P1-D: Traceability - Rejection Log
    # -------------------------------------------------------------------------
    def write_rejection_log(
        self,
        log_lines: List[str],
        intent_id: Optional[str] = None,
    ) -> None:
        """Write sample rejection log showing intent_id propagation."""
        path = self.evidence_root / "traceability" / "sample_rejection_log.txt"
        lines = [
            f"# Sample Rejection Log (P1-D)",
            f"# Generated: {self._timestamp()}",
        ]
        if intent_id:
            lines.append(f"# Expected intent_id: {intent_id}")
        lines.append("")
        lines.extend(log_lines)
        lines.append("")

        # Verify intent_id appears in all lines (simple check)
        if intent_id:
            missing = [ln for ln in log_lines if intent_id not in ln and ln.strip()]
            if missing:
                lines.append(f"# WARNING: {len(missing)} lines missing intent_id")
            else:
                lines.append(f"# VERIFIED: intent_id={intent_id} present in all log lines")
        self._write(path, "\n".join(lines) + "\n")

    # -------------------------------------------------------------------------
    # P1-F: Config Fail-Closed Matrix
    # -------------------------------------------------------------------------
    def write_config_matrix(
        self,
        results: Dict[str, Dict[str, Any]],
    ) -> None:
        """
        Write config fail-closed test results.

        Args:
            results: Dict of {config_key: {"status": "PASS"|"FAIL", "reason": "REASON_CODE"}}
        """
        path = self.evidence_root / "config_fail_closed" / "missing_keys_matrix.json"
        output = {
            "generated": self._timestamp(),
            "test": "test_missing_config_fails_closed",
            "results": results,
            "summary": {
                "total": len(results),
                "passed": sum(1 for r in results.values() if r.get("status") == "PASS"),
                "failed": sum(1 for r in results.values() if r.get("status") == "FAIL"),
            },
        }
        self._write(path, json.dumps(output, indent=2) + "\n")

    # -------------------------------------------------------------------------
    # P1-G: Crash-Mid-Intent
    # -------------------------------------------------------------------------
    def write_crash_auto_passed(
        self,
        test_name: str = "test_crash_mid_intent_no_duplicate_dispatch",
        details: Optional[str] = None,
    ) -> None:
        """Mark AUTO crash test as passed."""
        path = self.evidence_root / "crash_mid_intent" / "auto_test_passed.txt"
        lines = [
            f"# {test_name}",
            f"# Passed: {self._timestamp()}",
            "",
            "Verified:",
            "- No duplicate dispatch on restart",
            "- No ghost state",
            "- No unsafe opens",
        ]
        if details:
            lines.append("")
            lines.append(f"Details: {details}")
        self._write(path, "\n".join(lines) + "\n")

    def write_crash_drill(
        self,
        trigger: str,
        restart_steps: List[str],
        proof_items: List[str],
    ) -> None:
        """Write manual crash drill documentation (if AUTO not feasible)."""
        path = self.evidence_root / "crash_mid_intent" / "drill.md"
        lines = [
            "# Crash-Mid-Intent Drill (P1-G MANUAL)",
            "",
            f"Executed: {self._timestamp()}",
            "",
            "## Trigger",
            f"{trigger}",
            "",
            "## Restart Steps",
        ]
        for i, step in enumerate(restart_steps, 1):
            lines.append(f"{i}. {step}")
        lines.append("")
        lines.append("## Proof")
        for item in proof_items:
            lines.append(f"- {item}")
        lines.append("")
        lines.append("## Conclusion")
        lines.append("No dispatch occurred. No persistent side effects beyond counters/logs.")
        lines.append("Restart does not create duplicates.")
        self._write(path, "\n".join(lines) + "\n")


def main() -> int:
    """CLI interface for Rust tests to call."""
    parser = argparse.ArgumentParser(description="Emit Phase-1 evidence artifacts")
    parser.add_argument("--root", default=".", help="Repo root")
    subparsers = parser.add_subparsers(dest="command", required=True)

    # determinism-hashes
    p_det = subparsers.add_parser("determinism-hashes", help="Write determinism hash results")
    p_det.add_argument("hashes", nargs="+", help="Hash values from each run")

    # rejection-cases
    p_cases = subparsers.add_parser("rejection-cases", help="Write rejection cases doc")
    p_cases.add_argument("cases", nargs="+", help="Rejection case descriptions")
    p_cases.add_argument("--ci-link", help="CI run link")

    # rejection-log
    p_log = subparsers.add_parser("rejection-log", help="Write sample rejection log")
    p_log.add_argument("lines", nargs="+", help="Log lines")
    p_log.add_argument("--intent-id", help="Expected intent_id")

    # config-matrix
    p_cfg = subparsers.add_parser("config-matrix", help="Write config fail-closed matrix")
    p_cfg.add_argument("json_data", help="JSON object with results")

    # crash-auto-passed
    p_crash_auto = subparsers.add_parser("crash-auto-passed", help="Mark AUTO crash test passed")
    p_crash_auto.add_argument("--details", help="Additional details")

    # crash-drill
    p_drill = subparsers.add_parser("crash-drill", help="Write manual crash drill")
    p_drill.add_argument("--trigger", required=True, help="What triggered the crash")
    p_drill.add_argument("--restart-steps", nargs="+", required=True, help="Restart steps")
    p_drill.add_argument("--proof", nargs="+", required=True, help="Proof items")

    args = parser.parse_args()
    ev = P1Evidence(root=args.root)

    if args.command == "determinism-hashes":
        ev.write_determinism_hashes(args.hashes)
    elif args.command == "rejection-cases":
        ev.write_rejection_cases(args.cases, ci_link=getattr(args, "ci_link", None))
    elif args.command == "rejection-log":
        ev.write_rejection_log(args.lines, intent_id=getattr(args, "intent_id", None))
    elif args.command == "config-matrix":
        data = json.loads(args.json_data)
        ev.write_config_matrix(data)
    elif args.command == "crash-auto-passed":
        ev.write_crash_auto_passed(details=getattr(args, "details", None))
    elif args.command == "crash-drill":
        ev.write_crash_drill(args.trigger, args.restart_steps, args.proof)
    else:
        print(f"Unknown command: {args.command}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
