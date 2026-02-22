"""Integration tests for validate.py CLI."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
VALIDATE = REPO_ROOT / "python" / "proof_graph" / "validate.py"
FIXTURES = Path(__file__).parent / "fixtures"
CONTRACT = REPO_ROOT / "specs" / "CONTRACT.md"
PRD = REPO_ROOT / "plans" / "prd.json"


def _run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(
        [sys.executable, str(VALIDATE)] + args,
        capture_output=True, text=True,
        cwd=str(REPO_ROOT),
        **kwargs,
    )


class TestValidateCLI(unittest.TestCase):
    def test_valid_graph_exit_0(self):
        result = _run([
            str(FIXTURES / "valid_proof_graph.json"),
            "--contract-path", str(CONTRACT),
            "--prd-path", str(PRD),
        ])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_valid_graph_strict_exit_0(self):
        result = _run([
            str(FIXTURES / "valid_proof_graph.json"),
            "--contract-path", str(CONTRACT),
            "--prd-path", str(PRD),
            "--strict",
        ])
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_invalid_blocking_exit_1(self):
        result = _run([
            str(FIXTURES / "invalid_blocking.json"),
            "--contract-path", str(CONTRACT),
            "--prd-path", str(PRD),
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIn("R-001", result.stdout)

    def test_invalid_fail_open_risk_exit_1(self):
        result = _run([
            str(FIXTURES / "invalid_fail_open_risk.json"),
            "--contract-path", str(CONTRACT),
            "--prd-path", str(PRD),
        ])
        self.assertEqual(result.returncode, 1)
        self.assertIn("R-015", result.stdout)

    def test_missing_file_exit_3(self):
        result = _run(["/nonexistent/proof_graph.json"])
        self.assertEqual(result.returncode, 3)

    def test_bad_json_exit_3(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            f.write("{bad json")
            f.flush()
            try:
                result = _run([f.name])
                self.assertEqual(result.returncode, 3)
            finally:
                os.unlink(f.name)

    def test_unsupported_version_exit_2(self):
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            data = json.loads(
                (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
            )
            data["schema_version"] = 99
            json.dump(data, f)
            f.flush()
            try:
                result = _run([
                    f.name,
                    "--contract-path", str(CONTRACT),
                ])
                self.assertEqual(result.returncode, 2)
                self.assertIn("unsupported schema_version", result.stderr)
            finally:
                os.unlink(f.name)

    def test_json_output_mode(self):
        result = _run([
            str(FIXTURES / "invalid_blocking.json"),
            "--contract-path", str(CONTRACT),
            "--prd-path", str(PRD),
            "--json-output",
        ])
        self.assertEqual(result.returncode, 1)
        output = json.loads(result.stdout)
        self.assertIn("findings", output)
        self.assertIn("summary", output)
        self.assertGreater(output["summary"]["errors"], 0)

    def test_missing_contract_exit_3(self):
        result = _run([
            str(FIXTURES / "valid_proof_graph.json"),
            "--contract-path", "/nonexistent/CONTRACT.md",
        ])
        self.assertEqual(result.returncode, 3)
        self.assertIn("fail-closed", result.stderr)

    def test_strict_promotes_warnings(self):
        """With --strict, HARDENING findings become errors."""
        # invalid_stale_sha has a stale SHA (R-004 ERROR) — but let's create
        # a case where there's only a WARN.
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        # Remove TRIP test to trigger R-016 (WARN)
        data["ats"][0]["tests"] = [data["ats"][0]["tests"][1]]
        with tempfile.NamedTemporaryFile(
            mode="w", suffix=".json", delete=False
        ) as f:
            json.dump(data, f)
            f.flush()
            try:
                # Without --strict: WARN (exit 0)
                result_normal = _run([
                    f.name,
                    "--contract-path", str(CONTRACT),
                    "--prd-path", str(PRD),
                ])
                # R-016 is WARN, R-016b is BLOCKING for safety_critical+MED
                # So this will exit 1 due to R-016b
                # Let's adjust: make it non-safety-critical
                data["story_meta"]["safety_critical"] = False
                data["story_meta"]["loss_mode"]["level"] = "LOW"
                with tempfile.NamedTemporaryFile(
                    mode="w", suffix=".json", delete=False
                ) as f2:
                    json.dump(data, f2)
                    f2.flush()
                    result_normal = _run([
                        f2.name,
                        "--contract-path", str(CONTRACT),
                        "--prd-path", str(PRD),
                    ])
                    self.assertEqual(result_normal.returncode, 0,
                                     f"Expected exit 0 without --strict: {result_normal.stdout}")

                    result_strict = _run([
                        f2.name,
                        "--contract-path", str(CONTRACT),
                        "--prd-path", str(PRD),
                        "--strict",
                    ])
                    self.assertEqual(result_strict.returncode, 1,
                                     f"Expected exit 1 with --strict: {result_strict.stdout}")
                    os.unlink(f2.name)
            finally:
                os.unlink(f.name)


if __name__ == "__main__":
    unittest.main()
