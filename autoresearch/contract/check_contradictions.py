#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path
from typing import Any


NORMATIVE_RE = re.compile(r"\b(MUST(?:\s+NOT)?|SHALL(?:\s+NOT)?|SHOULD|MAY)\b", re.IGNORECASE)
CONDITIONAL_RE = re.compile(r"\b(AND|OR|EXCEPT|IF|WHEN|UNLESS)\b", re.IGNORECASE)


def fail(message: str) -> None:
    raise SystemExit(f"FAIL: {message}")


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def normative_tokens(text: str) -> list[str]:
    return [match.group(1).upper().replace("  ", " ") for match in NORMATIVE_RE.finditer(text)]


def has_conditional(text: str) -> bool:
    return bool(CONDITIONAL_RE.search(text))


def negation_signature(text: str) -> tuple[str, bool] | None:
    normalized = " ".join(text.upper().split())
    if "MUST NOT" in normalized:
        return normalized.replace("MUST NOT", "MUST"), True
    if "SHALL NOT" in normalized:
        return normalized.replace("SHALL NOT", "SHALL"), True
    if "MUST" in normalized:
        return normalized, False
    if "SHALL" in normalized:
        return normalized, False
    return None


def extract_contract_signatures(contract_text: str) -> tuple[set[str], set[str]]:
    positives: set[str] = set()
    negatives: set[str] = set()
    for chunk in re.split(r"[\n\.]+", contract_text):
        signature = negation_signature(chunk)
        if signature is None:
            continue
        normalized, negated = signature
        if negated:
            negatives.add(normalized)
        else:
            positives.add(normalized)
    return positives, negatives


def analyze_mechanical_change(old_text: str, new_text: str) -> tuple[str, str]:
    old_tokens = normative_tokens(old_text)
    new_tokens = normative_tokens(new_text)
    old_upper = " ".join(old_text.upper().split())
    new_upper = " ".join(new_text.upper().split())

    if old_tokens and not new_tokens:
        return "rejected", "CONTRADICTION"
    if old_tokens and any(token in {"SHOULD", "MAY"} for token in new_tokens):
        return "rejected", "CONTRADICTION"
    if ("MUST NOT" in old_upper or "SHALL NOT" in old_upper) and (
        ("MUST" in new_upper or "SHALL" in new_upper)
        and "MUST NOT" not in new_upper
        and "SHALL NOT" not in new_upper
    ):
        return "rejected", "CONTRADICTION"
    if old_tokens and has_conditional(new_text) and not has_conditional(old_text):
        return "pending_scope_review", "SCOPE_NARROWING"
    return "proposed", ""


def analyze_new_requirement(contract_text: str, proposed_text: str) -> tuple[str, str]:
    signature = negation_signature(proposed_text)
    if signature is None:
        return "proposed", ""
    normalized, negated = signature
    positives, negatives = extract_contract_signatures(contract_text)
    if negated and normalized in positives:
        return "rejected", "CONTRADICTION"
    if not negated and normalized in negatives:
        return "rejected", "CONTRADICTION"
    return "proposed", ""


def analyze_batch_conflicts(proposals: list[dict[str, Any]]) -> set[str]:
    conflicts: set[str] = set()
    seen: dict[str, tuple[str, bool]] = {}
    for proposal in proposals:
        text = ""
        if proposal.get("mechanical_ok") is True and isinstance(proposal.get("replace_span"), dict):
            text = str(proposal["replace_span"].get("new_text", ""))
        elif isinstance(proposal.get("proposed_text"), str):
            text = proposal["proposed_text"]
        signature = negation_signature(text)
        if signature is None:
            continue
        normalized, negated = signature
        previous = seen.get(normalized)
        if previous is not None and previous[1] != negated:
            conflicts.add(proposal["proposal_id"])
            conflicts.add(previous[0])
        else:
            seen[normalized] = (proposal["proposal_id"], negated)
    return conflicts


def evaluate_proposals(contract_text: str, proposals: list[dict[str, Any]]) -> dict[str, Any]:
    results: list[dict[str, str]] = []
    batch_conflicts = analyze_batch_conflicts(proposals)

    for proposal in proposals:
        proposal_id = proposal.get("proposal_id", "<unknown>")
        if proposal_id in batch_conflicts:
            results.append({
                "proposal_id": proposal_id,
                "status": "rejected",
                "reason_code": "BATCH_CONTRADICTION",
            })
            continue

        if proposal.get("mechanical_ok") is True and isinstance(proposal.get("replace_span"), dict):
            status, reason_code = analyze_mechanical_change(
                str(proposal["replace_span"].get("old_text", "")),
                str(proposal["replace_span"].get("new_text", "")),
            )
        else:
            status, reason_code = analyze_new_requirement(
                contract_text,
                str(proposal.get("proposed_text", "")),
            )
        results.append({
            "proposal_id": proposal_id,
            "status": status,
            "reason_code": reason_code,
        })

    return {"status": "ok", "results": results}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Check contract proposal contradictions")
    parser.add_argument("--contract", required=True, type=Path)
    parser.add_argument("--proposals", required=True, type=Path)
    parser.add_argument("--json", action="store_true", dest="json_output")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    try:
        contract_text = args.contract.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing contract file: {args.contract}")

    payload = load_json(args.proposals)
    proposals = payload.get("proposals")
    if not isinstance(proposals, list):
        fail(f"{args.proposals} must contain a proposals array")

    result = evaluate_proposals(contract_text, proposals)
    if args.json_output:
        print(json.dumps(result))
    else:
        print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
