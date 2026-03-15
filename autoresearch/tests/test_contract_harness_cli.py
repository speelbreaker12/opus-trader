from __future__ import annotations

import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HARNESS = REPO_ROOT / "autoresearch" / "skills" / "harness.sh"


class ContractHarnessCliTests(unittest.TestCase):
    def test_contract_status_succeeds(self) -> None:
        result = subprocess.run(
            ["bash", str(HARNESS), "contract", "status"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("Contract autoresearch status", result.stdout)
        self.assertIn("phase1", result.stdout)
        self.assertIn("phase2", result.stdout)

    def test_deferred_contract_command_fails_closed(self) -> None:
        result = subprocess.run(
            ["bash", str(HARNESS), "contract", "phase1", "run"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("deferred in the current manual-promotion slice", result.stderr)

    def test_contract_status_rejects_unknown_args(self) -> None:
        result = subprocess.run(
            ["bash", str(HARNESS), "contract", "status", "--bogus"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract status takes no arguments", result.stderr)

    def test_contract_scaffold_rejects_unknown_args(self) -> None:
        result = subprocess.run(
            ["bash", str(HARNESS), "contract", "scaffold", "--bogus"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("contract scaffold takes no arguments", result.stderr)

    def test_contract_status_fails_closed_on_malformed_index(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            temp_harness = temp_root / "autoresearch" / "skills" / "harness.sh"
            temp_harness.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HARNESS, temp_harness)
            shutil.copytree(
                REPO_ROOT / "autoresearch" / "contract",
                temp_root / "autoresearch" / "contract",
            )
            bad_index = temp_root / "autoresearch" / "contract" / "phase2" / "proposals_index.json"
            bad_index.write_text('{"entries": "oops"}', encoding="utf-8")

            result = subprocess.run(
                ["bash", str(temp_harness), "contract", "status"],
                cwd=temp_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("entries/runs must be a JSON array", result.stderr)


if __name__ == "__main__":
    unittest.main()
