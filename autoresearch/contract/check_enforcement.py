#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, NoReturn


def fail(message: str) -> NoReturn:
    raise SystemExit(f"FAIL: {message}")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def validate_weak_normative(payload: dict[str, Any]) -> list[dict[str, str]]:
    proposals = payload.get("proposals")
    if not isinstance(proposals, list):
        fail("proposals payload must contain a proposals array")

    results: list[dict[str, str]] = []
    for proposal in proposals:
        if not isinstance(proposal, dict):
            fail("proposals payload contains a non-object proposal")
        if proposal.get("source_finding_category") != "weak_normative":
            continue
        proposal_id = str(proposal.get("proposal_id", "<unknown>"))
        enforcement_point = str(proposal.get("enforcement_point", "")).strip()
        callsite_evidence = str(proposal.get("callsite_evidence", "")).strip()
        if not enforcement_point or not callsite_evidence:
            results.append({
                "proposal_id": proposal_id,
                "status": "rejected",
                "reason_code": "ENFORCEMENT_EVIDENCE_MISSING",
            })
            continue
        if enforcement_point not in callsite_evidence:
            results.append({
                "proposal_id": proposal_id,
                "status": "pending_scope_review",
                "reason_code": "ENFORCEMENT_EVIDENCE_WEAK",
            })
            continue
        results.append({
            "proposal_id": proposal_id,
            "status": "proposed",
            "reason_code": "",
        })
    return results


def validate_missing_fail_closed(payload: dict[str, Any]) -> list[dict[str, str]]:
    """Require enforcement_point + callsite_evidence for missing_fail_closed proposals."""
    proposals = payload.get("proposals")
    if not isinstance(proposals, list):
        fail("proposals payload must contain a proposals array")
    results: list[dict[str, str]] = []
    for proposal in proposals:
        if not isinstance(proposal, dict):
            fail("proposals payload contains a non-object proposal")
        if proposal.get("source_finding_category") != "missing_fail_closed":
            continue
        proposal_id = str(proposal.get("proposal_id", "<unknown>"))
        enforcement_point = str(proposal.get("enforcement_point", "")).strip()
        callsite_evidence = str(proposal.get("callsite_evidence", "")).strip()
        if not enforcement_point or not callsite_evidence:
            results.append({"proposal_id": proposal_id, "status": "rejected", "reason_code": "FAIL_CLOSED_ENFORCEMENT_EVIDENCE_MISSING"})
            continue
        if enforcement_point not in callsite_evidence:
            results.append({"proposal_id": proposal_id, "status": "pending_scope_review", "reason_code": "FAIL_CLOSED_ENFORCEMENT_EVIDENCE_WEAK"})
            continue
        results.append({"proposal_id": proposal_id, "status": "proposed", "reason_code": ""})
    return results


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Validate weak-normative enforcement evidence")
    parser.add_argument("--proposals", required=True, type=Path)
    parser.add_argument("--json", action="store_true", dest="json_output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    payload = load_json(args.proposals)
    result = {"status": "ok", "results": validate_weak_normative(payload)}
    if args.json_output:
        print(json.dumps(result))
    else:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
