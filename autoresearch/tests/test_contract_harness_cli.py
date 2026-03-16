from __future__ import annotations

import json
import os
import shutil
import subprocess
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

    def test_contract_phase_eval_requires_output_dir(self) -> None:
        result = subprocess.run(
            ["bash", str(HARNESS), "contract", "phase1", "eval"],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("requires --output-dir", result.stderr)

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

    def test_baseline_regenerates_existing_outputs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            temp_harness = temp_root / "autoresearch" / "skills" / "harness.sh"
            skill_dir = temp_root / "autoresearch" / "skills" / "demo"
            outputs_dir = skill_dir / "outputs" / "baseline-ci"
            fixture_path = skill_dir / "fixtures" / "case.txt"
            skills_root = temp_root / "SKILLS"
            bin_dir = temp_root / "bin"

            temp_harness.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HARNESS, temp_harness)
            skill_dir.mkdir(parents=True, exist_ok=True)
            outputs_dir.mkdir(parents=True, exist_ok=True)
            fixture_path.parent.mkdir(parents=True, exist_ok=True)
            skills_root.mkdir(parents=True, exist_ok=True)
            bin_dir.mkdir(parents=True, exist_ok=True)

            (skills_root / "demo.md").write_text("demo skill\n", encoding="utf-8")
            fixture_path.write_text("fixture body\n", encoding="utf-8")
            (skill_dir / "eval.json").write_text(
                json.dumps({"tests": [{"id": "T1", "fixture": "fixtures/case.txt", "prompt": "Review it."}]}),
                encoding="utf-8",
            )
            (skill_dir / "results.tsv").write_text(
                "commit\tscore\tpassed\ttotal\tstatus\tdescription\n",
                encoding="utf-8",
            )
            (outputs_dir / "T1.md").write_text("stale output\n", encoding="utf-8")

            claude_stub = bin_dir / "claude"
            claude_stub.write_text(
                "#!/usr/bin/env bash\n"
                "printf 'fresh output\\n'\n",
                encoding="utf-8",
            )
            claude_stub.chmod(0o755)

            evaluator = temp_root / "autoresearch" / "skills" / "evaluate.py"
            evaluator.write_text(
                "#!/usr/bin/env python3\n"
                "import json\n"
                "print(json.dumps({'score': 1.0, 'passed': 1, 'total': 1}))\n",
                encoding="utf-8",
            )
            evaluator.chmod(0o755)

            subprocess.run(["git", "init"], cwd=temp_root, check=True, capture_output=True, text=True)
            subprocess.run(["git", "config", "user.name", "Test User"], cwd=temp_root, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=temp_root, check=True)
            subprocess.run(["git", "add", "."], cwd=temp_root, check=True)
            subprocess.run(
                ["git", "commit", "-m", "seed baseline fixture"],
                cwd=temp_root,
                check=True,
                capture_output=True,
                text=True,
            )

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"

            result = subprocess.run(
                ["bash", str(temp_harness), "baseline", "demo", "--tag", "ci", "--model", "stub"],
                cwd=temp_root,
                capture_output=True,
                text=True,
                check=False,
                env=env,
            )
            self.assertEqual(result.returncode, 0, msg=result.stderr)
            self.assertEqual((outputs_dir / "T1.md").read_text(encoding="utf-8"), "fresh output\n")

    def test_check_monotonic_fails_closed_on_non_numeric_keep_score(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            temp_root = Path(temp_dir)
            temp_harness = temp_root / "autoresearch" / "skills" / "harness.sh"
            skill_dir = temp_root / "autoresearch" / "skills" / "demo"

            temp_harness.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HARNESS, temp_harness)
            skill_dir.mkdir(parents=True, exist_ok=True)
            (skill_dir / "eval.json").write_text(json.dumps({"tests": []}), encoding="utf-8")
            (skill_dir / "results.tsv").write_text(
                "\n".join(
                    [
                        "commit\tscore\tpassed\ttotal\tstatus\tdescription",
                        "aaaa111\t1.0\t1\t1\tkeep\tbaseline",
                        "bbbb222\toops\t1\t1\tkeep\tbad row",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )

            result = subprocess.run(
                ["bash", str(temp_harness), "check-monotonic", "demo"],
                cwd=temp_root,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("invalid numeric score", result.stderr)


if __name__ == "__main__":
    unittest.main()
