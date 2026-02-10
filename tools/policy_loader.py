#!/usr/bin/env python3
"""
tools/policy_loader.py

Minimal machine-readable policy loader + validator for Phase 0.
"""

from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any, Dict, List


REQUIRED_TOP_LEVEL = [
    "policy_id",
    "policy_version",
    "contract_version_target",
    "environments",
    "allowed_order_types",
    "forbidden_order_types",
    "risk_limits",
    "fail_closed",
]

REQUIRED_ENVS = ["DEV", "STAGING", "PAPER", "LIVE"]


def load_policy(path: Path) -> Dict[str, Any]:
    if not path.exists():
        raise ValueError(f"missing policy file: {path}")
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        raise ValueError(f"invalid JSON in {path}: {exc}") from exc
    if not isinstance(obj, dict):
        raise ValueError("policy root must be an object")
    return obj


def validate_policy(policy: Dict[str, Any]) -> List[str]:
    errors: List[str] = []

    for key in REQUIRED_TOP_LEVEL:
        if key not in policy:
            errors.append(f"missing required top-level key: {key}")

    if errors:
        return errors

    if not isinstance(policy["policy_id"], str) or not policy["policy_id"].strip():
        errors.append("policy_id must be a non-empty string")
    if not isinstance(policy["policy_version"], str) or not policy["policy_version"].strip():
        errors.append("policy_version must be a non-empty string")
    if not isinstance(policy["contract_version_target"], str) or not policy["contract_version_target"].strip():
        errors.append("contract_version_target must be a non-empty string")
    if not isinstance(policy["fail_closed"], bool) or policy["fail_closed"] is not True:
        errors.append("fail_closed must be true")

    envs = policy["environments"]
    if not isinstance(envs, dict):
        errors.append("environments must be an object")
    else:
        for env in REQUIRED_ENVS:
            if env not in envs:
                errors.append(f"environments missing entry: {env}")
                continue
            entry = envs[env]
            if not isinstance(entry, dict):
                errors.append(f"environment {env} must be an object")
                continue
            if "trade_capable" not in entry or not isinstance(entry["trade_capable"], bool):
                errors.append(f"environment {env} must define boolean trade_capable")
            if "purpose" not in entry or not isinstance(entry["purpose"], str) or not entry["purpose"].strip():
                errors.append(f"environment {env} must define non-empty purpose")

        paper_entry = envs.get("PAPER")
        if isinstance(paper_entry, dict) and paper_entry.get("trade_capable") is not False:
            errors.append("PAPER must not be trade_capable")
        live_entry = envs.get("LIVE")
        if isinstance(live_entry, dict) and live_entry.get("trade_capable") is not True:
            errors.append("LIVE must be trade_capable")

    allowed = policy["allowed_order_types"]
    forbidden = policy["forbidden_order_types"]
    if (
        not isinstance(allowed, list)
        or not allowed
        or not all(isinstance(x, str) and x.strip() for x in allowed)
    ):
        errors.append("allowed_order_types must be a non-empty string list")
    if (
        not isinstance(forbidden, list)
        or not forbidden
        or not all(isinstance(x, str) and x.strip() for x in forbidden)
    ):
        errors.append("forbidden_order_types must be a non-empty string list")
    if isinstance(allowed, list) and isinstance(forbidden, list):
        overlap = set(allowed) & set(forbidden)
        if overlap:
            errors.append(f"allowed/forbidden order type overlap: {sorted(overlap)}")

    risk_limits = policy["risk_limits"]
    if not isinstance(risk_limits, dict):
        errors.append("risk_limits must be an object")
    else:
        required_numeric_limits = [
            "max_daily_loss_usd",
            "max_gross_notional_usd",
            "max_orders_per_minute",
        ]
        for key in required_numeric_limits:
            value = risk_limits.get(key)
            if not isinstance(value, (int, float)):
                errors.append(f"risk_limits.{key} must be numeric")
            elif value <= 0:
                errors.append(f"risk_limits.{key} must be > 0")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate machine-readable trading policy.")
    parser.add_argument("--policy", default="config/policy.json", help="Path to machine policy JSON")
    parser.add_argument(
        "--strict",
        action="store_true",
        help="Fail (non-zero) when validation errors are present",
    )
    parser.add_argument(
        "--print",
        action="store_true",
        dest="should_print",
        help="Print canonicalized policy JSON on success",
    )
    args = parser.parse_args()

    policy_path = Path(args.policy).resolve()
    try:
        policy = load_policy(policy_path)
    except Exception as exc:
        print(f"POLICY LOADER FAILED: {exc}")
        return 1

    errors = validate_policy(policy)
    if errors:
        print("POLICY VALIDATION FAILED")
        for err in errors:
            print(f"- {err}")
        return 1 if args.strict else 0

    print("POLICY VALIDATION OK")
    if args.should_print:
        print(json.dumps(policy, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
