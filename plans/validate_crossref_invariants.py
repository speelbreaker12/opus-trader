#!/usr/bin/env python3
"""Validate crossref execution invariants YAML + semantics."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import sys
from typing import List

import jsonschema
import yaml

EXIT_PASS = 0
EXIT_SCHEMA_OR_PARSE = 2
EXIT_SEMANTIC = 3


class ValidationError(RuntimeError):
    """Semantic invariant violation."""


def load_yaml(path: Path) -> dict:
    try:
        payload = yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as exc:  # noqa: BLE001
        raise RuntimeError(f"failed to parse YAML {path}: {exc}") from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"YAML root must be an object: {path}")

    return payload


def load_schema(path: Path) -> dict:
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"failed to parse schema JSON {path}: {exc}") from exc

    if not isinstance(payload, dict):
        raise RuntimeError(f"schema root must be an object: {path}")

    return payload


def semantic_checks(inv: dict) -> List[str]:
    findings: List[str] = []

    canonical_sources = inv["global_invariants"]["ci_gating_scope"]["canonical_sources"]
    if len(set(canonical_sources)) != len(canonical_sources):
        findings.append("canonical_sources contains duplicates")

    for source in canonical_sources:
        if not Path(source).exists():
            findings.append(f"canonical source missing in repo: {source}")

    shared_parser = inv["slice_1"].get("shared_parser_path", "")
    if not shared_parser:
        findings.append("slice_1.shared_parser_path is empty")
    elif not Path(shared_parser).exists():
        findings.append(f"shared parser path missing: {shared_parser}")

    required_sequence = inv["workflow_loop"]["required_sequence"]
    required_steps = [
        "verify_quick",
        "self_review_pass",
        "codex_review_1",
        "kimi_review",
        "codex_review_2",
        "verify_full",
        "contract_review_generate",
        "contract_review_validate",
        "pre_pr_gate",
        "pr_gate_wait",
    ]
    for step in required_steps:
        if step not in required_sequence:
            findings.append(f"workflow_loop.required_sequence missing step: {step}")

    for earlier, later in (("contract_review_generate", "contract_review_validate"), ("verify_full", "pre_pr_gate")):
        if earlier in required_sequence and later in required_sequence:
            if required_sequence.index(earlier) > required_sequence.index(later):
                findings.append(f"workflow sequence order invalid: {earlier} must precede {later}")

    cond = inv["workflow_loop"].get("optional_prd_pass_flip_condition", "")
    if not isinstance(cond, str) or not cond.strip():
        findings.append("workflow_loop.optional_prd_pass_flip_condition must be non-empty")

    exit_codes = inv["slice_2"].get("exit_codes", {})
    for key in ("0", "2", "3", "4", "5", "6", "7"):
        if key not in exit_codes:
            findings.append(f"slice_2.exit_codes missing key {key}")

    return sorted(findings)


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate crossref execution invariants")
    parser.add_argument(
        "--invariants",
        default="plans/crossref_execution_invariants.yaml",
        help="Path to invariants YAML",
    )
    parser.add_argument(
        "--schema",
        default="plans/schemas/crossref_execution_invariants.schema.json",
        help="Path to invariants JSON schema",
    )
    args = parser.parse_args()

    inv_path = Path(args.invariants)
    schema_path = Path(args.schema)

    if not inv_path.exists():
        print(f"ERROR: invariants file not found: {inv_path}", file=sys.stderr)
        return EXIT_SCHEMA_OR_PARSE
    if not schema_path.exists():
        print(f"ERROR: schema file not found: {schema_path}", file=sys.stderr)
        return EXIT_SCHEMA_OR_PARSE

    try:
        invariants = load_yaml(inv_path)
        schema = load_schema(schema_path)
        jsonschema.validate(instance=invariants, schema=schema)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: invariant schema validation failed: {exc}", file=sys.stderr)
        return EXIT_SCHEMA_OR_PARSE

    findings = semantic_checks(invariants)
    if findings:
        print("ERROR: invariant semantic checks failed:", file=sys.stderr)
        for finding in findings:
            print(f"  - {finding}", file=sys.stderr)
        return EXIT_SEMANTIC

    print("OK: crossref execution invariants are schema-valid and semantically consistent.")
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
