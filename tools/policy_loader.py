#!/usr/bin/env python3
"""
tools/policy_loader.py

Minimal machine-readable policy loader + validator for Phase 0.
"""

from __future__ import annotations

import argparse
import json
import math
import sys
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

REQUIRED_FORBIDDEN_ORDER_TYPES = ["MARKET"]


def load_policy(path: Path) -> Dict[str, Any]:
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise ValueError(f"missing policy file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise ValueError(f"invalid JSON in {path}: {exc}") from exc
    except UnicodeDecodeError as exc:
        raise ValueError(f"cannot decode policy file {path}: {exc}") from exc
    except OSError as exc:
        raise ValueError(f"cannot read policy file {path}: {exc}") from exc
    if not isinstance(obj, dict):
        raise ValueError("policy root must be an object")
    return obj


def _is_strict_numeric(value: object) -> bool:
    """Return True if value is a finite int or float but NOT bool."""
    if not isinstance(value, (int, float)) or isinstance(value, bool):
        return False
    if isinstance(value, float) and not math.isfinite(value):
        return False
    return True


def validate_policy(policy: Dict[str, Any]) -> List[str]:
    errors: List[str] = []

    for key in REQUIRED_TOP_LEVEL:
        if key not in policy:
            errors.append(f"missing required top-level key: {key}")

    if errors:
        return errors

    unknown_keys = set(policy.keys()) - set(REQUIRED_TOP_LEVEL)
    if unknown_keys:
        errors.append(f"unknown top-level keys: {sorted(unknown_keys)}")

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

        unknown_envs = set(envs.keys()) - set(REQUIRED_ENVS)
        if unknown_envs:
            errors.append(f"environments has unknown entries: {sorted(unknown_envs)}")

        dev_entry = envs.get("DEV")
        if isinstance(dev_entry, dict) and isinstance(dev_entry.get("trade_capable"), bool) and dev_entry["trade_capable"] is not False:
            errors.append("DEV must not be trade_capable")
        # STAGING: intentionally unconstrained — testnet integration may need
        # trade_capable=true or false depending on deployment target.
        paper_entry = envs.get("PAPER")
        if isinstance(paper_entry, dict) and isinstance(paper_entry.get("trade_capable"), bool) and paper_entry["trade_capable"] is not False:
            errors.append("PAPER must not be trade_capable")
        live_entry = envs.get("LIVE")
        if isinstance(live_entry, dict) and isinstance(live_entry.get("trade_capable"), bool) and live_entry["trade_capable"] is not True:
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
        allowed_upper = {x.upper() for x in allowed if isinstance(x, str)}
        forbidden_upper = {x.upper() for x in forbidden if isinstance(x, str)}
        overlap = allowed_upper & forbidden_upper
        if overlap:
            errors.append(f"allowed/forbidden order type overlap: {sorted(overlap)}")

    if isinstance(forbidden, list):
        forbidden_upper = {x.upper() for x in forbidden if isinstance(x, str)}
        for required in REQUIRED_FORBIDDEN_ORDER_TYPES:
            if required not in forbidden_upper:
                errors.append(f"forbidden_order_types must include {required}")

    risk_limits = policy["risk_limits"]
    if not isinstance(risk_limits, dict):
        errors.append("risk_limits must be an object")
    else:
        required_numeric_limits = [
            "max_daily_loss_usd",
            "max_gross_notional_usd",
            "max_orders_per_minute",
        ]
        unknown_limits = set(risk_limits.keys()) - set(required_numeric_limits)
        if unknown_limits:
            errors.append(f"risk_limits has unknown keys: {sorted(unknown_limits)}")
        for key in required_numeric_limits:
            value = risk_limits.get(key)
            if value is None:
                errors.append(f"risk_limits.{key} is missing")
            elif not _is_strict_numeric(value):
                errors.append(f"risk_limits.{key} must be numeric (not bool)")
            elif value <= 0:
                errors.append(f"risk_limits.{key} must be > 0")

    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate machine-readable trading policy.")
    parser.add_argument("--policy", default="config/policy.json", help="Path to machine policy JSON")
    parser.add_argument(
        "--lenient",
        action="store_true",
        help="[DEV ONLY] Exit 0 even when validation errors are present (default: strict/fail-closed)",
    )
    parser.add_argument(
        "--print",
        action="store_true",
        dest="should_print",
        help="Print canonicalized policy JSON on success",
    )
    parser.add_argument(
        "--allow-absolute",
        action="store_true",
        help="Allow absolute paths for --policy (required if --policy is an absolute path)",
    )
    args = parser.parse_args()

    if Path(args.policy).is_absolute() and not args.allow_absolute:
        print(
            "POLICY LOADER FAILED: absolute path requires --allow-absolute flag",
            file=sys.stderr,
        )
        return 1

    if args.lenient:
        print(
            "WARNING: --lenient mode active. Validation errors will NOT cause a non-zero exit. "
            "Do NOT use this flag in CI gates or production deploy scripts.",
            file=sys.stderr,
        )

    policy_path = Path(args.policy).resolve()
    if not args.allow_absolute:
        cwd = Path.cwd().resolve()
        try:
            policy_path.relative_to(cwd)
        except ValueError:
            print(
                f"POLICY LOADER FAILED: resolved path {policy_path} escapes working directory {cwd}. "
                "Use --allow-absolute to override.",
                file=sys.stderr,
            )
            return 1
    try:
        policy = load_policy(policy_path)
    except ValueError as exc:
        print(f"POLICY LOADER FAILED: {exc}", file=sys.stderr)
        return 1

    errors = validate_policy(policy)
    if errors:
        print("POLICY VALIDATION FAILED", file=sys.stderr)
        for err in errors:
            print(f"- {err}", file=sys.stderr)
        return 0 if args.lenient else 1

    print("POLICY VALIDATION OK")
    if args.should_print:
        print(json.dumps(policy, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
