#!/usr/bin/env python3
"""
tools/validate_status.py (v4)

Contract-enforced /status validator for CSP + Phase 0/1 foundation status-lite.

Validates:
  - JSONSchema (Draft 2020-12)
  - Phase-aware contract checks:
      - Phase 2+ (CSP): minimum keys, manifest membership, tier/order, latch invariants
      - Phase 0/1 (foundation): status-lite shape + forbidden Phase-2+ authority fields
  - owner_view schema lock (CSP payloads)

Usage:
  # Validate live /status (runtime, allows extra keys)
  python tools/validate_status.py --url http://localhost:8080/api/v1/status

  # Validate fixture (strict, no extra keys)
  python tools/validate_status.py --file tests/fixtures/status/foo.json --strict

  # CI mode (quiet, exit code only)
  python tools/validate_status.py --file foo.json --quiet

Exit codes:
  0 = OK
  1 = Validation failed
  2 = Setup error (missing files, bad args, missing dependency)
"""

from __future__ import annotations

import argparse
import functools
import importlib.util
import json
import sys
import urllib.request
from pathlib import Path
from typing import Any

DEFAULT_CSP_SCHEMA_PATH = "python/schemas/status_csp_min.schema.json"
DEFAULT_FOUNDATION_SCHEMA_PATH = "python/schemas/status_foundation.schema.json"

# CSP Minimum Keys (contract-mandated, must always exist)
CSP_MINIMUM_KEYS = frozenset([
    "status_schema_version",
    "contract_version",
    "build_id",
    "runtime_config_hash",
    "supported_profiles",
    "enforced_profile",
    "trading_mode",
    "risk_state",
    "bunker_mode_active",
    "connectivity_degraded",
    "mode_reasons",
    "open_permission_blocked_latch",
    "open_permission_reason_codes",
    "open_permission_requires_reconcile",
    "policy_age_sec",
    "last_policy_update_ts",
    "f1_cert_state",
    "f1_cert_expires_at",
    "disk_used_pct",
    "disk_used_last_update_ts_ms",
    "disk_used_pct_secondary",
    "disk_used_secondary_last_update_ts_ms",
    "mm_util",
    "mm_util_last_update_ts_ms",
    "loop_tick_last_ts_ms",
    "wal_queue_depth",
    "wal_queue_capacity",
    "wal_queue_enqueue_failures",
    "atomic_naked_events_24h",
    "429_count_5m",
    "10028_count_5m",
    "deribit_http_p95_ms",
    "ws_event_lag_ms",
])

FOUNDATION_REQUIRED_KEYS = frozenset([
    "service_up",
    "build_id",
    "contract_version",
    "dispatch_enabled",
    "phase",
])

FOUNDATION_FORBIDDEN_KEYS = frozenset([
    "trading_mode",
    "opens_globally_permitted",
    "is_trading_allowed",
    "mode_reasons",
    "open_permission_blocked_latch",
    "open_permission_reason_codes",
    "open_permission_requires_reconcile",
])

GENERATED_STATUS_CODES_PATH = Path(__file__).with_name("generated_status_reason_codes.py")


def eprint(*args: Any) -> None:
    print(*args, file=sys.stderr)


def load_json_file(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def fetch_json_url(url: str, timeout_s: float) -> dict[str, Any]:
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout_s) as resp:
        data = resp.read()
    return json.loads(data.decode("utf-8"))


def validate_schema(instance: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    """Validate against JSONSchema. Returns list of errors (empty = OK)."""
    try:
        from jsonschema import Draft202012Validator
    except ImportError as ex:
        return [
            "SETUP ERROR: Missing dependency 'jsonschema'",
            "Fix: pip install jsonschema",
            f"Import error: {ex}",
        ]

    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda e: e.path)

    out: list[str] = []
    for err in errors:
        path = "$" + ("." + ".".join(str(p) for p in err.path) if err.path else "")
        out.append(f"[SCHEMA] {path}: {err.message}")
    return out


def check_minimum_keys(status: dict[str, Any]) -> list[str]:
    """Ensure all CSP minimum keys are present."""
    missing = CSP_MINIMUM_KEYS - set(status.keys())
    if missing:
        return [f"[CSP-MIN] Missing required key: {k}" for k in sorted(missing)]
    return []


def is_foundation_status(status: dict[str, Any]) -> bool:
    return status.get("phase") == "foundation"


def normalize_code_list(value: Any) -> list[str]:
    if isinstance(value, dict):
        if "values" in value:
            return normalize_code_list(value["values"])
        code = value.get("code")
        return [code] if isinstance(code, str) else []
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            if isinstance(item, str):
                out.append(item)
            elif isinstance(item, dict):
                code = item.get("code")
                if isinstance(code, str):
                    out.append(code)
        return out
    return []


@functools.lru_cache(maxsize=1)
def load_generated_status_module() -> Any | None:
    if not GENERATED_STATUS_CODES_PATH.exists():
        return None

    try:
        spec = importlib.util.spec_from_file_location(
            "generated_status_reason_codes_runtime",
            GENERATED_STATUS_CODES_PATH,
        )
        if spec is None or spec.loader is None:
            return None

        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    except Exception:
        return None


def decision_a_canonical_latch_reason() -> str:
    module = load_generated_status_module()
    if module is not None:
        token = getattr(module, "DECISION_A_CANONICAL_LATCH_REASON", None)
        if isinstance(token, str) and token:
            return token
    # Fallback keeps isolated --help copies robust when generated module is absent.
    return "REDUCEONLY_OPEN_PERMISSION_LATCHED"


def is_subsequence_in_order(seq: list[str], ordered_universe: list[str]) -> bool:
    """True iff seq preserves relative order of ordered_universe."""
    if not all(isinstance(v, str) for v in seq):
        return False
    if not all(isinstance(v, str) for v in ordered_universe):
        return False
    index = {v: i for i, v in enumerate(ordered_universe)}
    try:
        idxs = [index[v] for v in seq]
    except KeyError:
        return False
    return idxs == sorted(idxs)


def resolve_open_permission_semantics_version(status: dict[str, Any]) -> tuple[int | None, list[str]]:
    errs: list[str] = []
    status_schema_version = status.get("status_schema_version")
    semantics_version = status.get("open_permission_semantics_version")

    if status_schema_version not in (1, 2):
        errs.append("[SEMANTICS] status_schema_version must be 1 or 2")
        return None, errs

    if status_schema_version == 1:
        if semantics_version is None:
            return 1, errs
        if semantics_version != 1:
            errs.append(
                "[SEMANTICS] status_schema_version=1 requires "
                "open_permission_semantics_version to be omitted or 1"
            )
        return 1, errs

    if semantics_version != 2:
        errs.append(
            "[SEMANTICS] status_schema_version=2 requires "
            "open_permission_semantics_version=2"
        )
    return 2, errs


def resolve_decision_a_latch_reason(
    open_permission_semantics_version: int | None,
    reduce_only_reasons: list[str],
    decision_a_registry: Any,
) -> tuple[str | None, str | None]:
    """
    Resolve Decision-A latch token with status-semantics versioning.

    - Semantics v1: exact canonical token is required.
    - Semantics v2+: manifest must provide exactly one explicit
      DecisionALatchReasonCode value, and it must be in ReduceOnly reasons.
    """
    canonical = decision_a_canonical_latch_reason()

    if open_permission_semantics_version is not None and open_permission_semantics_version >= 2:
        explicit_codes = normalize_code_list(decision_a_registry)
        if len(explicit_codes) != 1:
            return (
                None,
                "[MANIFEST] registries.DecisionALatchReasonCode must define "
                "exactly one code for status_schema_version >= 2 semantics",
            )

        explicit_code = explicit_codes[0]
        if explicit_code not in reduce_only_reasons:
            return (
                None,
                "[MANIFEST] registries.DecisionALatchReasonCode must also be "
                "present in ModeReasonCode.ReduceOnly",
            )
        return explicit_code, None

    if canonical not in reduce_only_reasons:
        return (
            None,
            "[MANIFEST] ModeReasonCode.ReduceOnly must include "
            f"'{canonical}' for status_schema_version=1 semantics",
        )
    return canonical, None


def check_foundation_status_contract(status: dict[str, Any], manifest: dict[str, Any]) -> list[str]:
    """
    Validate Phase 0/1 status-lite payload contract.

    Required:
      - service_up, build_id, contract_version, dispatch_enabled, phase
      - dispatch_enabled == false
      - phase == "foundation"

    Forbidden in foundation phase:
      trading_mode, opens_globally_permitted, is_trading_allowed, mode_reasons,
      open_permission_blocked_latch, open_permission_reason_codes,
      open_permission_requires_reconcile
    """
    errs: list[str] = []

    missing = FOUNDATION_REQUIRED_KEYS - set(status.keys())
    if missing:
        errs.extend(
            f"[FOUNDATION] Missing required key: {k}" for k in sorted(missing)
        )

    if status.get("phase") != "foundation":
        errs.append(
            f"[FOUNDATION] phase must be 'foundation' (got {status.get('phase')!r})"
        )

    dispatch_enabled = status.get("dispatch_enabled")
    if not isinstance(dispatch_enabled, bool):
        errs.append(
            f"[FOUNDATION] dispatch_enabled must be boolean (got {type(dispatch_enabled).__name__})"
        )
    elif dispatch_enabled:
        errs.append(
            "[FOUNDATION] dispatch_enabled must be false while phase='foundation'"
        )

    service_up = status.get("service_up")
    if not isinstance(service_up, bool):
        errs.append(
            f"[FOUNDATION] service_up must be boolean (got {type(service_up).__name__})"
        )

    for key in sorted(FOUNDATION_FORBIDDEN_KEYS):
        if key in status:
            errs.append(f"[FOUNDATION] phase='foundation' forbids field '{key}'")

    manifest_contract_version = manifest.get("contract_version", "5.2")
    if status.get("contract_version") != manifest_contract_version:
        errs.append(
            f"[CONTRACT] Version mismatch: status has '{status.get('contract_version')}', "
            f"manifest requires '{manifest_contract_version}'"
        )

    return errs


def check_contract_invariants(status: dict[str, Any], manifest: dict[str, Any]) -> list[str]:
    """
    Check contract invariants that JSONSchema cannot express:
    - Contract version binding
    - Active ⇒ mode_reasons == []
    - ReduceOnly/Kill ⇒ mode_reasons non-empty
    - Tier purity and ordering
    - Latch invariants + Decision A
    - status_schema_version/open_permission_semantics_version coherence
    - Enum membership
    """
    errs: list[str] = []

    regs = manifest.get("registries", {})
    mode_regs = regs.get("ModeReasonCode", {})
    reduce_only_reasons = normalize_code_list(mode_regs.get("ReduceOnly", []))
    kill_reasons = normalize_code_list(mode_regs.get("Kill", []))
    open_perm_reasons = normalize_code_list(regs.get("OpenPermissionReasonCode", []))
    manifest_contract_version = manifest.get("contract_version", "5.2")
    open_permission_semantics_version, semantics_errors = resolve_open_permission_semantics_version(
        status
    )
    errs.extend(semantics_errors)
    decision_a_latch_reason, decision_a_manifest_error = resolve_decision_a_latch_reason(
        open_permission_semantics_version=open_permission_semantics_version,
        reduce_only_reasons=reduce_only_reasons,
        decision_a_registry=regs.get("DecisionALatchReasonCode"),
    )

    trading_mode = status.get("trading_mode")
    mode_reasons = status.get("mode_reasons", [])
    latch = status.get("open_permission_blocked_latch")
    latch_reasons = status.get("open_permission_reason_codes", [])
    requires_reconcile = status.get("open_permission_requires_reconcile")

    # 1. Contract version binding
    if status.get("contract_version") != manifest_contract_version:
        errs.append(
            f"[CONTRACT] Version mismatch: status has '{status.get('contract_version')}', "
            f"manifest requires '{manifest_contract_version}'"
        )
    if decision_a_manifest_error is not None:
        errs.append(decision_a_manifest_error)

    # 2. Active ⇒ mode_reasons == []
    if trading_mode == "Active" and mode_reasons != []:
        errs.append(
            "[INVARIANT] trading_mode='Active' requires mode_reasons=[] "
            f"(got {mode_reasons})"
        )

    # 3. ReduceOnly/Kill ⇒ mode_reasons non-empty
    if trading_mode in ("ReduceOnly", "Kill"):
        if not isinstance(mode_reasons, list) or len(mode_reasons) == 0:
            errs.append(
                f"[INVARIANT] trading_mode='{trading_mode}' requires at least one mode_reason"
            )

    # 4. Tier purity + ordering
    if isinstance(mode_reasons, list):
        if trading_mode == "ReduceOnly":
            bad = [r for r in mode_reasons if r not in reduce_only_reasons]
            if bad:
                errs.append(
                    f"[TIER] Invalid ReduceOnly mode_reasons (not in manifest): {bad}"
                )
            if mode_reasons and not is_subsequence_in_order(mode_reasons, reduce_only_reasons):
                errs.append(
                    "[ORDER] mode_reasons violates manifest ReduceOnly tier ordering"
                )
        elif trading_mode == "Kill":
            bad = [r for r in mode_reasons if r not in kill_reasons]
            if bad:
                errs.append(
                    f"[TIER] Invalid Kill mode_reasons (not in manifest): {bad}"
                )
            if mode_reasons and not is_subsequence_in_order(mode_reasons, kill_reasons):
                errs.append(
                    "[ORDER] mode_reasons violates manifest Kill tier ordering"
                )
        elif trading_mode not in ("Active", None):
            errs.append(f"[ENUM] Unknown trading_mode: '{trading_mode}'")

    # 5. Latch invariants + Decision A
    if latch is True:
        # Basic latch invariants
        if requires_reconcile is not True:
            errs.append(
                "[LATCH] latch=true requires open_permission_requires_reconcile=true"
            )
        if not isinstance(latch_reasons, list) or len(latch_reasons) == 0:
            errs.append(
                "[LATCH] latch=true requires non-empty open_permission_reason_codes"
            )

        # Decision A: latch=true ⇒ ¬Active (ReduceOnly or Kill allowed)
        if trading_mode == "Active":
            errs.append(
                "[DECISION-A] latch=true prohibits trading_mode='Active' "
                "(must be 'ReduceOnly' or 'Kill')"
            )

        # Decision A: latch=true ⇒ REDUCEONLY_OPEN_PERMISSION_LATCHED in mode_reasons
        # (unless already in Kill mode, which is more severe)
        if trading_mode == "ReduceOnly" and decision_a_latch_reason is not None:
            if not isinstance(mode_reasons, list) or decision_a_latch_reason not in mode_reasons:
                errs.append(
                    "[DECISION-A] latch=true with trading_mode='ReduceOnly' requires "
                    f"'{decision_a_latch_reason}' in mode_reasons"
                )

    elif latch is False:
        if requires_reconcile is not False:
            errs.append(
                "[LATCH] latch=false requires open_permission_requires_reconcile=false"
            )
        if latch_reasons != []:
            errs.append(
                "[LATCH] latch=false requires open_permission_reason_codes=[]"
            )
    else:
        errs.append(
            f"[LATCH] open_permission_blocked_latch must be boolean (got {type(latch).__name__})"
        )

    # 6. Latch reason membership
    if isinstance(latch_reasons, list):
        bad = [c for c in latch_reasons if c not in open_perm_reasons]
        if bad:
            errs.append(
                f"[ENUM] Unknown open_permission_reason_codes (not in manifest): {bad}"
            )

    # 7. owner_view type check
    if "owner_view" in status and not isinstance(status["owner_view"], dict):
        errs.append(
            f"[SCHEMA] owner_view must be object (got {type(status['owner_view']).__name__})"
        )

    return errs


def check_no_extra_keys(status: dict[str, Any], schema: dict[str, Any]) -> list[str]:
    """For strict mode: ensure no keys beyond what schema defines."""
    # Get allowed keys from schema properties
    allowed = set(schema.get("properties", {}).keys())
    actual = set(status.keys())
    extra = actual - allowed

    if extra:
        return [f"[STRICT] Extra key not in schema: '{k}'" for k in sorted(extra)]
    return []


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Validate /status JSON against CSP contract",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Validate live endpoint
  %(prog)s --url http://localhost:8080/api/v1/status

  # Validate fixture (strict mode)
  %(prog)s --file tests/fixtures/status/market_data_stale.json --strict

  # CI mode (quiet output)
  %(prog)s --file foo.json --quiet
""",
    )
    ap.add_argument("--url", help="Fetch status from URL")
    ap.add_argument("--file", help="Read status from file")
    ap.add_argument(
        "--schema",
        default=None,
        help=(
            "Path to JSONSchema. If omitted, phase-aware defaults apply: "
            f"foundation -> {DEFAULT_FOUNDATION_SCHEMA_PATH}, "
            f"otherwise -> {DEFAULT_CSP_SCHEMA_PATH}"
        ),
    )
    ap.add_argument(
        "--schema-csp",
        default=DEFAULT_CSP_SCHEMA_PATH,
        help="Default schema path for CSP status payloads (default: %(default)s)",
    )
    ap.add_argument(
        "--schema-foundation",
        default=DEFAULT_FOUNDATION_SCHEMA_PATH,
        help="Default schema path for phase='foundation' payloads (default: %(default)s)",
    )
    ap.add_argument(
        "--manifest",
        default="specs/status/status_reason_registries_manifest.json",
        help="Path to reason codes manifest (default: %(default)s)",
    )
    ap.add_argument(
        "--strict",
        action="store_true",
        help="Strict mode: fail on extra keys (use for fixtures)",
    )
    ap.add_argument(
        "--quiet",
        action="store_true",
        help="Quiet mode: no output, exit code only",
    )
    ap.add_argument(
        "--timeout",
        type=float,
        default=5.0,
        help="URL fetch timeout in seconds (default: %(default)s)",
    )
    args = ap.parse_args()

    # Exactly one input source
    if bool(args.url) == bool(args.file):
        if not args.quiet:
            eprint("Error: provide exactly one of --url or --file")
        return 2

    # Load status
    try:
        if args.url:
            status = fetch_json_url(args.url, args.timeout)
        else:
            status = load_json_file(Path(args.file))
    except Exception as ex:
        if not args.quiet:
            eprint(f"Error loading status: {ex}")
        return 2

    # Resolve phase-aware schema path
    if args.schema:
        schema_path = Path(args.schema)
    else:
        schema_path = (
            Path(args.schema_foundation)
            if is_foundation_status(status)
            else Path(args.schema_csp)
        )

    manifest_path = Path(args.manifest)

    # Check required files exist
    if not schema_path.exists():
        if not args.quiet:
            eprint(f"Error: schema not found: {schema_path}")
        return 2
    if not manifest_path.exists():
        if not args.quiet:
            eprint(f"Error: manifest not found: {manifest_path}")
        return 2

    # Load schema and manifest
    try:
        schema = load_json_file(schema_path)
        manifest = load_json_file(manifest_path)
    except Exception as ex:
        if not args.quiet:
            eprint(f"Error loading schema/manifest: {ex}")
        return 2

    # Run all checks
    errors: list[str] = []

    # 1. Schema validation
    schema_errors = validate_schema(status, schema)
    if schema_errors and schema_errors[0].startswith("SETUP ERROR"):
        # Missing jsonschema dependency
        if not args.quiet:
            for line in schema_errors:
                eprint(line)
        return 2
    errors.extend(schema_errors)

    # 2-3. Phase-aware contract checks
    if is_foundation_status(status):
        errors.extend(check_foundation_status_contract(status, manifest))
    else:
        errors.extend(check_minimum_keys(status))
        errors.extend(check_contract_invariants(status, manifest))

    # 4. Strict mode: no extra keys
    if args.strict:
        errors.extend(check_no_extra_keys(status, schema))

    # Report results
    if errors:
        if not args.quiet:
            source = args.url or args.file
            eprint(f"VALIDATION FAILED: {source}")
            eprint(f"  {len(errors)} error(s):")
            for msg in errors:
                eprint(f"  - {msg}")
        return 1

    if not args.quiet:
        source = args.url or args.file
        print(f"VALIDATION OK: {source}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
