#!/usr/bin/env python3
"""
tools/phase0_meta_test.py

Phase-0 CI meta-test: fail if required Phase-0 docs + evidence artifacts are missing.

This enforces that Phase 0 is not "paper-only":
- Launch policy exists + snapshot
- Machine-readable policy config + loader are present and valid
- Env matrix exists + snapshot
- Keys/secrets doc exists + key scope probe JSON exists (valid)
- PAPER environment remains non-trading in env matrix + key-scope probe evidence
- Break-glass runbook exists + snapshot + executed drill record + logs
- Health endpoint doc exists + snapshot + executable command behavior
- Minimal owner status output exists and is executable (`trading_mode`, `is_trading_allowed`)
- Minimal Phase-0 test definitions exist with explicit names
- Code-level Phase-0 runtime integration tests exist and are wired in rust test gates
- Evidence pack has owner summary + CI links placeholder

Usage:
  python tools/phase0_meta_test.py
Optional:
  --root .   # repo root (default: cwd)
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def must_exist(paths: Iterable[Path]) -> List[str]:
    missing = []
    for p in paths:
        if not p.exists():
            missing.append(str(p))
    return missing


def must_be_nonempty(paths: Iterable[Path]) -> List[str]:
    bad = []
    for p in paths:
        if not p.exists():
            bad.append(f"{p} (missing)")
            continue
        if p.is_dir():
            bad.append(f"{p} (is a directory)")
            continue
        if p.stat().st_size == 0:
            bad.append(f"{p} (empty)")
    return bad


def must_contain_lines(path: Path, min_lines: int) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    text = path.read_text(encoding="utf-8", errors="replace").strip()
    if not text:
        return [f"{path} (empty)"]
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if len(lines) < min_lines:
        return [f"{path} (too few lines: {len(lines)} < {min_lines})"]
    return []


def must_be_valid_json(path: Path) -> List[str]:
    if not path.exists():
        return [f"{path} (missing)"]
    try:
        obj = json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        return [f"{path} (invalid JSON: {e})"]
    if obj is None:
        return [f"{path} (JSON is null)"]
    if isinstance(obj, (dict, list)) and len(obj) == 0:
        return [f"{path} (JSON is empty)"]
    return []


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8", errors="replace")


def has_any(text: str, needles: Iterable[str]) -> bool:
    lowered = text.lower()
    return any(n.lower() in lowered for n in needles)


def run_cli_json(root: Path, args: List[str], env: Dict[str, str]) -> Tuple[int, Optional[Dict[str, object]], str]:
    proc = subprocess.run(
        [str(root / "stoic-cli")] + args,
        cwd=str(root),
        env=env,
        text=True,
        capture_output=True,
        check=False,
    )
    combined = (proc.stdout + "\n" + proc.stderr).strip()
    if not proc.stdout.strip():
        return proc.returncode, None, combined
    try:
        payload = json.loads(proc.stdout)
    except Exception:
        return proc.returncode, None, combined
    if not isinstance(payload, dict):
        return proc.returncode, None, combined
    return proc.returncode, payload, combined


def build_meta_runtime_state_path(root: Path, prefix: str) -> tuple[Path, bool]:
    runtime_dir = root / "artifacts" / "phase0" / "meta_test_runtime"
    allow_external = False
    try:
        runtime_dir.mkdir(parents=True, exist_ok=True)
    except OSError:
        runtime_dir = Path(tempfile.gettempdir())
        allow_external = True
    token = f"{prefix}_{os.getpid()}_{time.time_ns()}"
    path = runtime_dir / f"{token}.json"
    if path.exists():
        path.unlink()
    return path, allow_external


def cleanup_runtime_state_artifacts(runtime_state: Path) -> None:
    runtime_state.unlink(missing_ok=True)
    lock_path = runtime_state.with_name(f".{runtime_state.name}.lock")
    lock_path.unlink(missing_ok=True)


def markdown_table_row_for_env(text: str, env: str) -> List[str]:
    target = env.strip().lower()
    for raw in text.splitlines():
        line = raw.strip()
        if not line.startswith("|"):
            continue
        cols = [c.strip() for c in line.strip("|").split("|")]
        if not cols:
            continue
        if cols[0].lower() == target:
            return cols
    return []


def test_policy_is_required_and_bound(root: Path) -> List[str]:
    policy = root / "docs" / "launch_policy.md"
    if not policy.exists():
        return [f"{policy} missing"]

    text = read_text(policy)
    errors: List[str] = []

    # Phase-0 executable proxy for "policy binding / fail-closed required".
    if not has_any(text, ["if something is not explicitly allowed here", "fail-closed"]):
        errors.append("missing explicit fail-closed policy binding statement")
    if not has_any(text, ["missing config key", "reject intent (no dispatch)"]):
        errors.append("missing explicit missing-config fail-closed rejection")
    if not has_any(text, ["any ambiguity", "treat as open risk"]):
        errors.append("missing ambiguity->OPEN-risk fail-closed rule")
    if not has_any(text, ["no open risk permitted", "open forbidden"]):
        errors.append("missing explicit OPEN-risk prohibition in mode rules")

    return errors


def test_api_keys_are_least_privilege(root: Path) -> List[str]:
    probe_path = root / "evidence" / "phase0" / "keys" / "key_scope_probe.json"
    if not probe_path.exists():
        return [f"{probe_path} missing"]

    obj = json.loads(read_text(probe_path))
    errors: List[str] = []

    # Support both expanded multi-env probe schema and minimal flat schema.
    if isinstance(obj, dict) and isinstance(obj.get("probes"), list):
        trade_envs = 0
        trade_envs_with_forbidden_withdraw = 0

        for i, probe in enumerate(obj.get("probes", []), start=1):
            if not isinstance(probe, dict):
                errors.append(f"probe[{i}] is not an object")
                continue

            if probe.get("withdraw_enabled") is not False:
                errors.append(f"probe[{i}] withdraw_enabled must be false")

            scopes = probe.get("scopes", [])
            scopes_lower = {str(s).lower() for s in scopes} if isinstance(scopes, list) else set()
            results = probe.get("probe_results", {}) if isinstance(probe.get("probe_results"), dict) else {}

            if "trade" in scopes_lower:
                trade_envs += 1
                withdraw = results.get("withdraw", {}) if isinstance(results.get("withdraw"), dict) else {}
                wresult = str(withdraw.get("result", "")).lower()
                if wresult in {"permission_denied", "forbidden", "rejected", "failed", "not_allowed"}:
                    trade_envs_with_forbidden_withdraw += 1
                else:
                    errors.append(
                        f"probe[{i}] trade-capable key must show forbidden withdrawal; got result={wresult or 'missing'}"
                    )

            # If a probe is read-only/public, it must not demonstrate successful trading.
            if "trade" not in scopes_lower:
                place_order = results.get("place_order", {}) if isinstance(results.get("place_order"), dict) else {}
                presult = str(place_order.get("result", "")).lower()
                if presult in {"success", "accepted"}:
                    errors.append(f"probe[{i}] non-trade scope shows successful order placement")

        if trade_envs == 0:
            errors.append("no trade-capable environment probe found")
        if trade_envs_with_forbidden_withdraw == 0:
            errors.append("no evidence that withdrawal is forbidden for trade-capable keys")

        summary = obj.get("summary", {})
        if isinstance(summary, dict) and "least_privilege_verified" in summary:
            if summary.get("least_privilege_verified") is not True:
                errors.append("summary.least_privilege_verified must be true")
    else:
        # Minimal flat schema fallback.
        if not isinstance(obj, dict):
            return ["key_scope_probe JSON must be an object"]
        if obj.get("withdraw_enabled") is not False:
            errors.append("withdraw_enabled must be false")
        scopes = obj.get("scopes")
        if not isinstance(scopes, list) or len(scopes) == 0:
            errors.append("scopes must be a non-empty list")

    return errors


def test_break_glass_kill_blocks_open_allows_reduce(root: Path) -> List[str]:
    drill = root / "evidence" / "phase0" / "break_glass" / "drill.md"
    logs = root / "evidence" / "phase0" / "break_glass" / "log_excerpt.txt"
    missing = []
    if not drill.exists():
        missing.append(f"{drill} missing")
    if not logs.exists():
        missing.append(f"{logs} missing")
    if missing:
        return missing

    drill_text = read_text(drill)
    log_text = read_text(logs)
    errors: List[str] = []

    if not has_any(drill_text + "\n" + log_text, ["kill_engaged", "trading_mode=kill", "received=kill"]):
        errors.append("no deterministic evidence that Kill was engaged")
    if not has_any(
        drill_text + "\n" + log_text,
        ["did_new_open_dispatch_stop: yes", "orders_escaped=0", "open_blocked", "queued=0"],
    ):
        errors.append("no deterministic evidence that OPEN dispatch stopped under Kill")
    if not has_any(
        drill_text + "\n" + log_text,
        ["was_risk_reduction_possible_if_exposure: yes", "reduce_only", "result=accepted", "reduce_only_works=true"],
    ):
        errors.append("no deterministic evidence that risk reduction remained possible")

    # Executable command-path check (Phase-0 command-level e2e drill).
    cli = root / "stoic-cli"
    policy = root / "config" / "policy.json"
    if not cli.exists():
        errors.append(f"{cli} missing")
        return errors
    if not policy.exists():
        errors.append(f"{policy} missing")
        return errors

    runtime_state, allow_external_runtime_state = build_meta_runtime_state_path(root, "phase0_break_glass")
    try:
        env = os.environ.copy()
        env["STOIC_BUILD_ID"] = "phase0-break-glass-meta-test"
        env["STOIC_POLICY_PATH"] = str(policy)
        env["STOIC_RUNTIME_STATE_PATH"] = str(runtime_state)
        if allow_external_runtime_state:
            env["STOIC_ALLOW_EXTERNAL_RUNTIME_STATE"] = "1"
        env["STOIC_DRILL_MODE"] = "1"

        rc, payload, details = run_cli_json(
            root,
            ["simulate-open", "--instrument", "BTC-28MAR26-50000-C", "--count", "2"],
            env,
        )
        if rc != 0 or payload is None or payload.get("result") != "ACCEPTED":
            errors.append(f"simulate-open command path failed: rc={rc} details={details}")
            return errors

        rc, payload, details = run_cli_json(root, ["orders", "--pending", "--format", "json"], env)
        if rc != 0 or payload is None or int(payload.get("pending_count", -1)) < 1:
            errors.append(f"orders --pending command path failed before kill: rc={rc} details={details}")
            return errors

        rc, payload, details = run_cli_json(root, ["emergency", "kill", "--reason", "phase0-meta-test"], env)
        if rc != 0 or payload is None or payload.get("trading_mode") != "KILL":
            errors.append(f"emergency kill command path failed: rc={rc} details={details}")
            return errors

        rc, payload, details = run_cli_json(root, ["status", "--format", "json"], env)
        if rc != 0 or payload is None:
            errors.append(f"status command failed after kill: rc={rc} details={details}")
            return errors
        if payload.get("trading_mode") != "KILL":
            errors.append("status after kill must report trading_mode=KILL")
        if payload.get("is_trading_allowed") is not False:
            errors.append("status after kill must report is_trading_allowed=false")

        rc, payload, details = run_cli_json(root, ["orders", "--pending", "--format", "json"], env)
        if rc != 0 or payload is None or int(payload.get("pending_count", -1)) != 0:
            errors.append(f"orders --pending must be empty after kill: rc={rc} details={details}")
            return errors

        rc, payload, details = run_cli_json(
            root,
            ["emergency", "reduce-only", "--reason", "phase0-meta-reduce"],
            env,
        )
        if rc != 0 or payload is None or payload.get("trading_mode") != "REDUCE_ONLY":
            errors.append(f"emergency reduce-only command path failed: rc={rc} details={details}")
            return errors

        rc, payload, details = run_cli_json(
            root,
            ["simulate-close", "--instrument", "BTC-28MAR26-50000-C", "--dry-run"],
            env,
        )
        if rc != 0 or payload is None or payload.get("result") != "ACCEPTED":
            errors.append(f"simulate-close command path failed in reduce-only: rc={rc} details={details}")
            return errors

    finally:
        cleanup_runtime_state_artifacts(runtime_state)

    return errors


def test_machine_policy_loader_and_config(root: Path) -> List[str]:
    errors: List[str] = []
    policy_path = root / "config" / "policy.json"
    snapshot_path = root / "evidence" / "phase0" / "policy" / "policy_config_snapshot.json"
    loader_path = root / "tools" / "policy_loader.py"

    if not policy_path.exists():
        errors.append(f"{policy_path} missing")
        return errors
    if not snapshot_path.exists():
        errors.append(f"{snapshot_path} missing")
        return errors
    if not loader_path.exists():
        errors.append(f"{loader_path} missing")
        return errors

    try:
        policy_obj = json.loads(read_text(policy_path))
    except Exception as e:
        errors.append(f"policy config invalid JSON: {e}")
        return errors

    if not isinstance(policy_obj, dict) or not policy_obj:
        errors.append("policy config must be a non-empty JSON object")
        return errors

    required_keys = [
        "policy_id",
        "policy_version",
        "contract_version_target",
        "environments",
        "allowed_order_types",
        "forbidden_order_types",
        "risk_limits",
        "fail_closed",
    ]
    for key in required_keys:
        if key not in policy_obj:
            errors.append(f"policy config missing required key: {key}")

    if policy_obj.get("fail_closed") is not True:
        errors.append("policy config fail_closed must be true")

    envs = policy_obj.get("environments")
    if isinstance(envs, dict):
        paper = envs.get("PAPER")
        if isinstance(paper, dict) and paper.get("trade_capable") is not False:
            errors.append("policy config environments.PAPER.trade_capable must be false")
    else:
        errors.append("policy config environments must be an object")

    if read_text(policy_path) != read_text(snapshot_path):
        errors.append("policy config snapshot is not a literal copy of config/policy.json")

    cmd = [sys.executable, str(loader_path), "--policy", str(policy_path), "--strict"]
    proc = subprocess.run(
        cmd,
        cwd=str(root),
        text=True,
        capture_output=True,
        check=False,
    )
    if proc.returncode != 0:
        details = (proc.stdout + "\n" + proc.stderr).strip()
        errors.append(f"policy loader strict validation failed: {details}")

    return errors


def test_paper_is_non_trading(root: Path) -> List[str]:
    env_matrix = root / "docs" / "env_matrix.md"
    probe_path = root / "evidence" / "phase0" / "keys" / "key_scope_probe.json"
    errors: List[str] = []

    if not env_matrix.exists():
        return [f"{env_matrix} missing"]

    env_text = read_text(env_matrix)
    if not has_any(
        env_text,
        [
            "paper must not hold trade-capable credentials",
            "paper must not have trade-capable keys",
            "paper cannot place private orders",
        ],
    ):
        errors.append("env_matrix missing explicit PAPER non-trading invariant")

    row = markdown_table_row_for_env(env_text, "PAPER")
    if not row:
        errors.append("env_matrix missing PAPER row in Matrix table")
    else:
        if len(row) < 11:
            errors.append(f"PAPER row has too few columns: {len(row)} < 11")
        else:
            account = row[2].strip().lower()
            api_key = row[3].strip().lower()
            key_type = row[4].strip().lower()
            perms = row[5].strip().lower()
            withdraw = row[6].strip().lower()
            secrets_source = row[8].strip().lower()
            notes = row[10].strip().lower()

            if key_type not in {"none", "data_only"}:
                errors.append(f"PAPER key type must be NONE or DATA_ONLY (got '{row[4].strip()}')")
            if "trade" in perms:
                errors.append("PAPER permissions/scopes must not include trade")
            if key_type == "none":
                if account not in {"n/a", "none", ""}:
                    errors.append("PAPER account/subaccount must be N/A when key type is NONE")
                if api_key not in {"n/a", "none", ""}:
                    errors.append("PAPER API key must be N/A when key type is NONE")
                if secrets_source not in {"n/a", "none", ""}:
                    errors.append("PAPER secrets source must be N/A when key type is NONE")
            if withdraw in {"true", "yes", "1"}:
                errors.append("PAPER withdraw flag must not be true")
            if not has_any(notes, ["public endpoints only", "execution simulated", "no private trade auth"]):
                errors.append("PAPER notes must state non-trading/public-only intent")

    if not probe_path.exists():
        errors.append(f"{probe_path} missing")
        return errors

    try:
        probe_obj = json.loads(read_text(probe_path))
    except Exception as e:
        errors.append(f"{probe_path} invalid JSON: {e}")
        return errors

    if isinstance(probe_obj, dict) and isinstance(probe_obj.get("probes"), list):
        paper_probe = None
        for probe in probe_obj.get("probes", []):
            if isinstance(probe, dict) and str(probe.get("env", "")).strip().upper() == "PAPER":
                paper_probe = probe
                break
        if paper_probe is None:
            errors.append("key_scope_probe missing PAPER probe entry")
            return errors

        scopes = paper_probe.get("scopes", [])
        scopes_lower = {str(s).lower() for s in scopes} if isinstance(scopes, list) else set()
        if "trade" in scopes_lower:
            errors.append("PAPER probe scopes must not include trade")
        if paper_probe.get("withdraw_enabled") not in {False, None}:
            errors.append("PAPER probe withdraw_enabled must be false or omitted")

        results = paper_probe.get("probe_results", {})
        if isinstance(results, dict):
            place_order = results.get("place_order")
            if isinstance(place_order, dict):
                presult = str(place_order.get("result", "")).lower()
                if presult in {"success", "accepted"}:
                    errors.append("PAPER probe must not show successful order placement")
    elif isinstance(probe_obj, dict) and str(probe_obj.get("env", "")).strip().upper() == "PAPER":
        scopes = probe_obj.get("scopes", [])
        scopes_lower = {str(s).lower() for s in scopes} if isinstance(scopes, list) else set()
        if "trade" in scopes_lower:
            errors.append("PAPER probe scopes must not include trade")
        if probe_obj.get("withdraw_enabled") not in {False, None}:
            errors.append("PAPER probe withdraw_enabled must be false or omitted")

    return errors


def test_health_command_behavior(root: Path) -> List[str]:
    errors: List[str] = []
    cli = root / "stoic-cli"

    if not cli.exists():
        return [f"{cli} missing"]
    if not os.access(cli, os.X_OK):
        return [f"{cli} is not executable"]

    base_env = os.environ.copy()
    base_env["STOIC_BUILD_ID"] = "phase0-health-test-build"

    cmd = [str(cli), "health", "--format", "json"]
    healthy = subprocess.run(
        cmd,
        cwd=str(root),
        env=base_env,
        text=True,
        capture_output=True,
        check=False,
    )
    if healthy.returncode != 0:
        details = (healthy.stdout + "\n" + healthy.stderr).strip()
        errors.append(f"health command healthy path must exit 0; got {healthy.returncode}: {details}")
        return errors

    try:
        healthy_payload = json.loads(healthy.stdout)
    except Exception as e:
        errors.append(f"health command healthy output is not valid JSON: {e}")
        return errors

    for field in ["ok", "build_id", "contract_version", "timestamp_utc"]:
        if field not in healthy_payload:
            errors.append(f"healthy payload missing required field: {field}")
    if healthy_payload.get("ok") is not True:
        errors.append("healthy payload must set ok=true")
    if not isinstance(healthy_payload.get("build_id"), str) or not healthy_payload.get("build_id"):
        errors.append("healthy payload build_id must be a non-empty string")
    if not isinstance(healthy_payload.get("contract_version"), str) or not healthy_payload.get("contract_version"):
        errors.append("healthy payload contract_version must be a non-empty string")

    unhealthy_env = base_env.copy()
    unhealthy_env["STOIC_POLICY_PATH"] = str(root / "config" / "missing_policy.json")
    unhealthy = subprocess.run(
        cmd,
        cwd=str(root),
        env=unhealthy_env,
        text=True,
        capture_output=True,
        check=False,
    )
    if unhealthy.returncode != 1:
        details = (unhealthy.stdout + "\n" + unhealthy.stderr).strip()
        errors.append(f"health command unhealthy path must exit 1; got {unhealthy.returncode}: {details}")
        return errors

    try:
        unhealthy_payload = json.loads(unhealthy.stdout)
    except Exception as e:
        errors.append(f"health command unhealthy output is not valid JSON: {e}")
        return errors

    if unhealthy_payload.get("ok") is not False:
        errors.append("unhealthy payload must set ok=false")
    payload_errors = unhealthy_payload.get("errors")
    if not isinstance(payload_errors, list) or len(payload_errors) == 0:
        errors.append("unhealthy payload must include non-empty errors list")
    elif not any("policy" in str(err).lower() for err in payload_errors):
        errors.append("unhealthy payload errors must mention policy failure")

    return errors


def test_status_command_behavior(root: Path) -> List[str]:
    errors: List[str] = []
    cli = root / "stoic-cli"
    policy = root / "config" / "policy.json"

    if not cli.exists():
        return [f"{cli} missing"]
    if not policy.exists():
        return [f"{policy} missing"]
    if not os.access(cli, os.X_OK):
        return [f"{cli} is not executable"]

    runtime_state, allow_external_runtime_state = build_meta_runtime_state_path(root, "phase0_status")
    try:

        base_env = os.environ.copy()
        base_env["STOIC_BUILD_ID"] = "phase0-status-meta-test"
        base_env["STOIC_POLICY_PATH"] = str(policy)
        base_env["STOIC_RUNTIME_STATE_PATH"] = str(runtime_state)
        if allow_external_runtime_state:
            base_env["STOIC_ALLOW_EXTERNAL_RUNTIME_STATE"] = "1"

        rc, payload, details = run_cli_json(root, ["status", "--format", "json"], base_env)
        if rc != 0 or payload is None:
            errors.append(f"status healthy path must succeed: rc={rc} details={details}")
            return errors

        for field in ["ok", "build_id", "contract_version", "timestamp_utc", "trading_mode", "is_trading_allowed"]:
            if field not in payload:
                errors.append(f"status healthy payload missing required field: {field}")
        if payload.get("ok") is not True:
            errors.append("status healthy payload must set ok=true")

        missing_env = base_env.copy()
        missing_env["STOIC_POLICY_PATH"] = str(root / "config" / "missing_policy.json")
        rc, payload, details = run_cli_json(root, ["status", "--format", "json"], missing_env)
        if rc != 1 or payload is None:
            errors.append(f"status unhealthy path must fail with rc=1: rc={rc} details={details}")
            return errors
        if payload.get("ok") is not False:
            errors.append("status unhealthy payload must set ok=false")
        if payload.get("trading_mode") != "KILL":
            errors.append("status unhealthy payload must force trading_mode=KILL")
        if payload.get("is_trading_allowed") is not False:
            errors.append("status unhealthy payload must force is_trading_allowed=false")
        payload_errors = payload.get("errors")
        if not isinstance(payload_errors, list) or len(payload_errors) == 0:
            errors.append("status unhealthy payload must include non-empty errors list")
        elif not any("policy" in str(err).lower() for err in payload_errors):
            errors.append("status unhealthy payload errors must mention policy failure")

    finally:
        cleanup_runtime_state_artifacts(runtime_state)

    return errors


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=".", help="Repo root (default: cwd)")
    args = ap.parse_args()

    root = Path(args.root).resolve()

    # Required docs (MANUAL)
    required_docs = [
        root / "docs" / "launch_policy.md",
        root / "docs" / "env_matrix.md",
        root / "docs" / "keys_and_secrets.md",
        root / "docs" / "break_glass_runbook.md",
        root / "docs" / "health_endpoint.md",
        root / "config" / "policy.json",
        root / "tools" / "policy_loader.py",
        root / "stoic-cli",
    ]

    # Required evidence files
    required_evidence = [
        root / "evidence" / "phase0" / "README.md",
        root / "evidence" / "phase0" / "ci_links.md",
        root / "evidence" / "phase0" / "policy" / "launch_policy_snapshot.md",
        root / "evidence" / "phase0" / "policy" / "policy_config_snapshot.json",
        root / "evidence" / "phase0" / "env" / "env_matrix_snapshot.md",
        root / "evidence" / "phase0" / "keys" / "key_scope_probe.json",
        root / "evidence" / "phase0" / "break_glass" / "runbook_snapshot.md",
        root / "evidence" / "phase0" / "break_glass" / "drill.md",
        root / "evidence" / "phase0" / "break_glass" / "log_excerpt.txt",
        root / "evidence" / "phase0" / "health" / "health_endpoint_snapshot.md",
    ]

    # Required Phase-0 acceptance test definition files
    required_phase0_tests = [
        root / "tests" / "phase0" / "README.md",
        root / "tests" / "phase0" / "test_policy_is_required_and_bound.md",
        root / "tests" / "phase0" / "test_machine_policy_loader_and_config.md",
        root / "tests" / "phase0" / "test_health_command_behavior.md",
        root / "tests" / "phase0" / "test_status_command_behavior.md",
        root / "tests" / "phase0" / "test_api_keys_are_least_privilege.md",
        root / "tests" / "phase0" / "test_break_glass_kill_blocks_open_allows_reduce.md",
    ]

    # Required code-level runtime integration tests
    required_phase0_runtime_tests = [
        root / "crates" / "soldier_infra" / "tests" / "test_phase0_runtime.rs",
    ]

    errors: List[str] = []

    errors += [f"Missing required doc: {p}" for p in must_exist(required_docs)]
    errors += [f"Bad required doc: {p}" for p in must_be_nonempty(required_docs)]

    errors += [f"Missing required evidence: {p}" for p in must_exist(required_evidence)]
    errors += [f"Bad required evidence: {p}" for p in must_be_nonempty(required_evidence)]
    errors += [f"Missing required phase0 test definition: {p}" for p in must_exist(required_phase0_tests)]
    errors += [f"Bad required phase0 test definition: {p}" for p in must_be_nonempty(required_phase0_tests)]
    errors += [f"Missing required phase0 runtime integration test: {p}" for p in must_exist(required_phase0_runtime_tests)]
    errors += [f"Bad required phase0 runtime integration test: {p}" for p in must_be_nonempty(required_phase0_runtime_tests)]

    # Minimal content checks to prevent 1-line placeholders
    errors += must_contain_lines(root / "evidence" / "phase0" / "README.md", min_lines=8)
    errors += must_contain_lines(root / "evidence" / "phase0" / "break_glass" / "drill.md", min_lines=8)
    errors += must_be_valid_json(root / "evidence" / "phase0" / "keys" / "key_scope_probe.json")

    phase0_tests = [
        ("test_policy_is_required_and_bound", test_policy_is_required_and_bound(root)),
        ("test_machine_policy_loader_and_config", test_machine_policy_loader_and_config(root)),
        ("test_api_keys_are_least_privilege", test_api_keys_are_least_privilege(root)),
        ("test_paper_is_non_trading", test_paper_is_non_trading(root)),
        ("test_health_command_behavior", test_health_command_behavior(root)),
        ("test_status_command_behavior", test_status_command_behavior(root)),
        (
            "test_break_glass_kill_blocks_open_allows_reduce",
            test_break_glass_kill_blocks_open_allows_reduce(root),
        ),
    ]

    for name, t_errors in phase0_tests:
        if t_errors:
            errors.append(f"{name} FAILED")
            errors.extend([f"{name}: {msg}" for msg in t_errors])
        else:
            print(f"{name}: PASS")

    if errors:
        eprint("PHASE 0 META-TEST FAILED")
        for msg in errors:
            eprint(f"- {msg}")
        return 1

    print("PHASE 0 META-TEST OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
