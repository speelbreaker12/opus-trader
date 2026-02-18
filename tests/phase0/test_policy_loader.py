#!/usr/bin/env python3
"""
tests/phase0/test_policy_loader.py

Executable tests for the machine-readable policy loader (S0-005).
Covers: happy path, error paths, fail-closed defaults, snapshot integrity.
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
POLICY_PATH = ROOT / "config" / "policy.json"
SNAPSHOT_PATH = ROOT / "evidence" / "phase0" / "policy" / "policy_config_snapshot.json"
LOADER_SCRIPT = ROOT / "tools" / "policy_loader.py"

sys.path.insert(0, str(ROOT / "tools"))
from policy_loader import _is_strict_numeric, load_policy, validate_policy


# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

@pytest.fixture()
def valid_policy() -> dict:
    return json.loads(POLICY_PATH.read_text(encoding="utf-8"))


# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

class TestHappyPath:
    def test_valid_policy_no_errors(self, valid_policy: dict) -> None:
        errors = validate_policy(valid_policy)
        assert errors == [], f"Unexpected errors: {errors}"

    def test_cli_strict_default_exits_zero(self) -> None:
        """CLI defaults to strict mode and exits 0 on valid policy."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH), "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert "POLICY VALIDATION OK" in result.stdout


# ---------------------------------------------------------------------------
# Fail-closed: strict is default (HIGH #1)
# ---------------------------------------------------------------------------

class TestFailClosedDefault:
    def test_cli_default_fails_on_bad_policy(self, tmp_path: Path) -> None:
        """Without --lenient, bad policy must exit 1 (fail-closed)."""
        bad = {"policy_id": "X"}  # missing most keys
        p = tmp_path / "bad.json"
        p.write_text(json.dumps(bad), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(p), "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 1
        assert "POLICY VALIDATION FAILED" in result.stderr

    def test_cli_lenient_exits_zero_on_bad_policy(self, tmp_path: Path) -> None:
        """With --lenient, bad policy exits 0 but still prints failure message."""
        bad = {"policy_id": "X"}
        p = tmp_path / "bad.json"
        p.write_text(json.dumps(bad), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(p), "--lenient", "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert "POLICY VALIDATION FAILED" in result.stderr

    def test_cli_lenient_emits_stderr_warning(self, tmp_path: Path) -> None:
        """--lenient must emit a loud WARNING to stderr."""
        bad = {"policy_id": "X"}
        p = tmp_path / "bad.json"
        p.write_text(json.dumps(bad), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(p), "--lenient", "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert "WARNING" in result.stderr
        assert "--lenient" in result.stderr

    def test_cli_absolute_path_rejected_without_flag(self) -> None:
        """Absolute --policy path requires --allow-absolute."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH)],
            capture_output=True, text=True,
        )
        assert result.returncode == 1
        assert "absolute path requires --allow-absolute" in result.stderr

    def test_cli_absolute_path_accepted_with_flag(self) -> None:
        """Absolute --policy path works with --allow-absolute."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH), "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert "POLICY VALIDATION OK" in result.stdout

    def test_cli_lenient_warning_on_valid_policy(self) -> None:
        """--lenient WARNING must fire even when policy is valid."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH), "--lenient", "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert "POLICY VALIDATION OK" in result.stdout
        assert "WARNING" in result.stderr
        assert "--lenient" in result.stderr

    def test_cli_relative_path_traversal_rejected(self, tmp_path: Path) -> None:
        """Relative path traversal (../) must be rejected without --allow-absolute."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", "../../etc/passwd"],
            capture_output=True, text=True,
            cwd=str(tmp_path),
        )
        assert result.returncode == 1
        assert "escapes working directory" in result.stderr

    def test_cli_allow_absolute_lenient_bad_policy(self, tmp_path: Path) -> None:
        """--allow-absolute + --lenient on bad policy: exit 0, FAILED on stderr, no OK on stdout."""
        bad = {"policy_id": "X"}
        p = tmp_path / "bad.json"
        p.write_text(json.dumps(bad), encoding="utf-8")
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(p), "--allow-absolute", "--lenient"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert "POLICY VALIDATION OK" not in result.stdout
        assert "POLICY VALIDATION FAILED" in result.stderr
        assert "WARNING" in result.stderr


# ---------------------------------------------------------------------------
# Happy path (--print flag)
# ---------------------------------------------------------------------------

class TestPrintFlag:
    def test_cli_print_produces_valid_json(self) -> None:
        """--print must output parseable JSON to stdout after OK line."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH), "--allow-absolute", "--print"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        lines = result.stdout.strip().split("\n", 1)
        assert lines[0] == "POLICY VALIDATION OK"
        parsed = json.loads(lines[1])
        assert parsed["policy_id"] == "LP-001"
        assert parsed["fail_closed"] is True

    def test_cli_no_print_omits_json(self) -> None:
        """Without --print, stdout is only the OK line."""
        result = subprocess.run(
            [sys.executable, str(LOADER_SCRIPT), "--policy", str(POLICY_PATH), "--allow-absolute"],
            capture_output=True, text=True,
        )
        assert result.returncode == 0
        assert result.stdout.strip() == "POLICY VALIDATION OK"


# ---------------------------------------------------------------------------
# Missing / malformed keys
# ---------------------------------------------------------------------------

class TestMissingKeys:
    def test_missing_required_key(self, valid_policy: dict) -> None:
        del valid_policy["fail_closed"]
        errors = validate_policy(valid_policy)
        assert any("missing required top-level key: fail_closed" in e for e in errors)

    def test_unknown_top_level_key(self, valid_policy: dict) -> None:
        valid_policy["rogue_key"] = "surprise"
        errors = validate_policy(valid_policy)
        assert any("unknown top-level keys" in e for e in errors)

    def test_empty_policy_id(self, valid_policy: dict) -> None:
        valid_policy["policy_id"] = "  "
        errors = validate_policy(valid_policy)
        assert any("policy_id must be a non-empty string" in e for e in errors)


# ---------------------------------------------------------------------------
# fail_closed field validation (P1 — safety-critical)
# ---------------------------------------------------------------------------

class TestFailClosedField:
    def test_fail_closed_false_rejected(self, valid_policy: dict) -> None:
        valid_policy["fail_closed"] = False
        errors = validate_policy(valid_policy)
        assert any("fail_closed must be true" in e for e in errors)

    def test_fail_closed_string_rejected(self, valid_policy: dict) -> None:
        valid_policy["fail_closed"] = "yes"
        errors = validate_policy(valid_policy)
        assert any("fail_closed must be true" in e for e in errors)

    def test_fail_closed_zero_rejected(self, valid_policy: dict) -> None:
        valid_policy["fail_closed"] = 0
        errors = validate_policy(valid_policy)
        assert any("fail_closed must be true" in e for e in errors)

    def test_fail_closed_none_rejected(self, valid_policy: dict) -> None:
        valid_policy["fail_closed"] = None
        errors = validate_policy(valid_policy)
        assert any("fail_closed must be true" in e for e in errors)

    def test_fail_closed_int_one_rejected(self, valid_policy: dict) -> None:
        valid_policy["fail_closed"] = 1
        errors = validate_policy(valid_policy)
        assert any("fail_closed must be true" in e for e in errors)

    def test_fail_closed_true_passes(self, valid_policy: dict) -> None:
        assert valid_policy["fail_closed"] is True
        errors = validate_policy(valid_policy)
        assert not any("fail_closed" in e for e in errors)


# ---------------------------------------------------------------------------
# MARKET must be forbidden (HIGH #3)
# ---------------------------------------------------------------------------

class TestMarketForbidden:
    def test_market_missing_from_forbidden(self, valid_policy: dict) -> None:
        valid_policy["forbidden_order_types"] = ["STOP", "TRIGGER"]
        errors = validate_policy(valid_policy)
        assert any("forbidden_order_types must include MARKET" in e for e in errors)

    def test_market_present_passes(self, valid_policy: dict) -> None:
        assert "MARKET" in valid_policy["forbidden_order_types"]
        errors = validate_policy(valid_policy)
        assert not any("MARKET" in e for e in errors)


# ---------------------------------------------------------------------------
# Bool-as-int bug (MEDIUM #5)
# ---------------------------------------------------------------------------

class TestBoolAsInt:
    def test_strict_numeric_rejects_bool(self) -> None:
        assert _is_strict_numeric(True) is False
        assert _is_strict_numeric(False) is False

    def test_strict_numeric_accepts_int_float(self) -> None:
        assert _is_strict_numeric(42) is True
        assert _is_strict_numeric(3.14) is True
        assert _is_strict_numeric(0) is True

    def test_strict_numeric_rejects_string(self) -> None:
        assert _is_strict_numeric("") is False
        assert _is_strict_numeric("42") is False

    def test_strict_numeric_rejects_none(self) -> None:
        assert _is_strict_numeric(None) is False

    def test_strict_numeric_rejects_nan_inf(self) -> None:
        assert _is_strict_numeric(float("nan")) is False
        assert _is_strict_numeric(float("inf")) is False
        assert _is_strict_numeric(float("-inf")) is False

    def test_bool_risk_limit_rejected(self, valid_policy: dict) -> None:
        valid_policy["risk_limits"]["max_daily_loss_usd"] = True
        errors = validate_policy(valid_policy)
        assert any("must be numeric (not bool)" in e for e in errors)


# ---------------------------------------------------------------------------
# Environment constraints (MEDIUM #8)
# ---------------------------------------------------------------------------

class TestEnvironmentConstraints:
    def test_dev_must_not_be_trade_capable(self, valid_policy: dict) -> None:
        valid_policy["environments"]["DEV"]["trade_capable"] = True
        errors = validate_policy(valid_policy)
        assert any("DEV must not be trade_capable" in e for e in errors)

    def test_paper_must_not_be_trade_capable(self, valid_policy: dict) -> None:
        valid_policy["environments"]["PAPER"]["trade_capable"] = True
        errors = validate_policy(valid_policy)
        assert any("PAPER must not be trade_capable" in e for e in errors)

    def test_live_must_be_trade_capable(self, valid_policy: dict) -> None:
        valid_policy["environments"]["LIVE"]["trade_capable"] = False
        errors = validate_policy(valid_policy)
        assert any("LIVE must be trade_capable" in e for e in errors)

    def test_staging_trade_capable_unconstrained(self, valid_policy: dict) -> None:
        """STAGING trade_capable is intentionally unconstrained (testnet integration)."""
        valid_policy["environments"]["STAGING"]["trade_capable"] = True
        errors = validate_policy(valid_policy)
        assert not any("STAGING" in e and "trade_capable" in e for e in errors)

        valid_policy["environments"]["STAGING"]["trade_capable"] = False
        errors = validate_policy(valid_policy)
        assert not any("STAGING" in e and "trade_capable" in e for e in errors)

    def test_unknown_environment_entry_flagged(self, valid_policy: dict) -> None:
        """Unknown environment keys (typos, extras) must be flagged."""
        valid_policy["environments"]["PROD"] = {"trade_capable": True, "purpose": "oops"}
        errors = validate_policy(valid_policy)
        assert any("unknown entries" in e and "PROD" in e for e in errors)


# ---------------------------------------------------------------------------
# Allowed/forbidden overlap
# ---------------------------------------------------------------------------

class TestOrderTypeValidation:
    def test_overlap_detected(self, valid_policy: dict) -> None:
        valid_policy["allowed_order_types"].append("MARKET")
        errors = validate_policy(valid_policy)
        assert any("overlap" in e for e in errors)

    def test_empty_allowed_order_types_rejected(self, valid_policy: dict) -> None:
        valid_policy["allowed_order_types"] = []
        errors = validate_policy(valid_policy)
        assert any("allowed_order_types must be a non-empty string list" in e for e in errors)

    def test_empty_forbidden_order_types_rejected(self, valid_policy: dict) -> None:
        valid_policy["forbidden_order_types"] = []
        errors = validate_policy(valid_policy)
        assert any("forbidden_order_types must be a non-empty string list" in e for e in errors)

    def test_case_insensitive_overlap_detected(self, valid_policy: dict) -> None:
        """'market' in allowed overlaps with 'MARKET' in forbidden (case-insensitive)."""
        valid_policy["allowed_order_types"].append("market")
        errors = validate_policy(valid_policy)
        assert any("overlap" in e for e in errors)

    def test_case_insensitive_market_forbidden(self, valid_policy: dict) -> None:
        """'market' (lowercase) in forbidden satisfies the MARKET requirement."""
        valid_policy["forbidden_order_types"] = ["market", "STOP"]
        errors = validate_policy(valid_policy)
        assert not any("must include MARKET" in e for e in errors)


# ---------------------------------------------------------------------------
# Risk limit boundaries (P2 — zero and negative)
# ---------------------------------------------------------------------------

class TestRiskLimitBoundaries:
    def test_zero_risk_limit_rejected(self, valid_policy: dict) -> None:
        valid_policy["risk_limits"]["max_daily_loss_usd"] = 0
        errors = validate_policy(valid_policy)
        assert any("must be > 0" in e for e in errors)

    def test_negative_risk_limit_rejected(self, valid_policy: dict) -> None:
        valid_policy["risk_limits"]["max_gross_notional_usd"] = -100
        errors = validate_policy(valid_policy)
        assert any("must be > 0" in e for e in errors)

    def test_positive_risk_limit_passes(self, valid_policy: dict) -> None:
        errors = validate_policy(valid_policy)
        assert not any("must be > 0" in e for e in errors)

    def test_unknown_risk_limit_key_flagged(self, valid_policy: dict) -> None:
        """Typos or extra keys in risk_limits must be flagged."""
        valid_policy["risk_limits"]["max_daily_los_usd"] = 5000
        errors = validate_policy(valid_policy)
        assert any("unknown keys" in e and "max_daily_los_usd" in e for e in errors)

    def test_missing_risk_limit_key_clear_message(self, valid_policy: dict) -> None:
        """Missing risk_limits key says 'missing', not 'not bool'."""
        del valid_policy["risk_limits"]["max_orders_per_minute"]
        errors = validate_policy(valid_policy)
        assert any("max_orders_per_minute" in e and "missing" in e for e in errors)
        assert not any("max_orders_per_minute" in e and "not bool" in e for e in errors)


# ---------------------------------------------------------------------------
# Missing environment entry (P2)
# ---------------------------------------------------------------------------

class TestEnvironmentTypeValidation:
    def test_environments_not_dict_rejected(self, valid_policy: dict) -> None:
        for bad_value in [None, "string", [1, 2], 42]:
            p = {**valid_policy, "environments": bad_value}
            errors = validate_policy(p)
            assert any("environments must be an object" in e for e in errors), (
                f"expected error for environments={bad_value!r}"
            )


class TestMissingEnvironment:
    def test_missing_staging_detected(self, valid_policy: dict) -> None:
        del valid_policy["environments"]["STAGING"]
        errors = validate_policy(valid_policy)
        assert any("environments missing entry: STAGING" in e for e in errors)

    def test_missing_dev_detected(self, valid_policy: dict) -> None:
        del valid_policy["environments"]["DEV"]
        errors = validate_policy(valid_policy)
        assert any("environments missing entry: DEV" in e for e in errors)


# ---------------------------------------------------------------------------
# Snapshot integrity (MEDIUM #6)
# ---------------------------------------------------------------------------

class TestSnapshotIntegrity:
    def test_snapshot_matches_policy(self) -> None:
        """Evidence snapshot must be byte-for-byte identical to config/policy.json."""
        policy_text = POLICY_PATH.read_text(encoding="utf-8")
        snapshot_text = SNAPSHOT_PATH.read_text(encoding="utf-8")
        assert policy_text == snapshot_text, (
            "evidence/phase0/policy/policy_config_snapshot.json has drifted from config/policy.json"
        )


# ---------------------------------------------------------------------------
# Load errors
# ---------------------------------------------------------------------------

class TestLoadErrors:
    def test_missing_file(self, tmp_path: Path) -> None:
        with pytest.raises(ValueError, match="missing policy file"):
            load_policy(tmp_path / "nonexistent.json")

    def test_invalid_json(self, tmp_path: Path) -> None:
        p = tmp_path / "bad.json"
        p.write_text("{not json", encoding="utf-8")
        with pytest.raises(ValueError, match="invalid JSON"):
            load_policy(p)

    def test_non_object_root(self, tmp_path: Path) -> None:
        p = tmp_path / "array.json"
        p.write_text("[1,2,3]", encoding="utf-8")
        with pytest.raises(ValueError, match="policy root must be an object"):
            load_policy(p)

    def test_invalid_utf8(self, tmp_path: Path) -> None:
        p = tmp_path / "binary.json"
        p.write_bytes(b"\xff\xfe{}")
        with pytest.raises(ValueError, match="cannot decode policy file"):
            load_policy(p)
