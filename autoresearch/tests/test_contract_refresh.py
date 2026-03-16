from __future__ import annotations

import json
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_TEMPLATE = REPO_ROOT / "autoresearch" / "contract"
REFRESH_PY = REPO_ROOT / "autoresearch" / "contract" / "refresh_context.py"


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _write_json(path: Path, payload: object) -> None:
    _write_text(path, json.dumps(payload, indent=2) + "\n")


class _TempRefreshRepo:
    def __init__(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        shutil.copytree(CONTRACT_TEMPLATE, self.root / "autoresearch" / "contract")
        _write_text(
            self.root / "specs" / "CONTRACT.md",
            "\n".join(
                [
                    "# Contract",
                    "",
                    "## Definitions",
                    "",
                    "Shared definitions.",
                    "",
                    "## 0.0 Normative Scope",
                    "",
                    "Normative scope text.",
                    "",
                    "## 1 Execution Pipeline",
                    "",
                    "AT-101",
                    "- Given: pipeline guard exists.",
                    "",
                    "Execution pipeline body.",
                    "",
                    "## 2.2 PolicyGuard",
                    "",
                    "AT-201",
                    "- Given: policy guard exists.",
                    "",
                    "evidence_chain_score must fail closed when stale.",
                    "",
                ]
            )
            + "\n",
        )

    def close(self) -> None:
        self.temp_dir.cleanup()

    def run(self, mode: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            ["python3", str(REFRESH_PY), "--root", str(self.root), "--mode", mode],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )


class ContractRefreshTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = _TempRefreshRepo()

    def tearDown(self) -> None:
        self.repo.close()

    def test_refresh_common_generates_common_files_and_manifest_hashes(self) -> None:
        result = self.repo.run("common")
        self.assertEqual(result.returncode, 0, msg=result.stderr)

        contract_header = (
            self.repo.root / "autoresearch" / "contract" / "common" / "contract_header.md"
        ).read_text(encoding="utf-8")
        self.assertIn("## Definitions", contract_header)
        self.assertIn("## 0.0 Normative Scope", contract_header)

        section_index = (
            self.repo.root / "autoresearch" / "contract" / "common" / "section_index.md"
        ).read_text(encoding="utf-8")
        self.assertIn("| 1 | Execution Pipeline |", section_index)
        self.assertIn("| 2.2 | PolicyGuard |", section_index)

        at_registry = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "common" / "at_registry.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(at_registry[0]["at_id"], "AT-101")
        self.assertEqual(at_registry[1]["at_id"], "AT-201")

        manifest = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "common" / "context_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertIn("common/contract_header.md", manifest["tracked_files"])
        self.assertIn("common/section_index.md", manifest["tracked_files"])
        self.assertEqual(len(manifest["contract_content_hash"]), 64)

    def test_refresh_fixtures_generates_snapshot_targets_and_manifest_hashes(self) -> None:
        _write_json(
            self.repo.root / "autoresearch" / "contract" / "common" / "gate_input_registry.json",
            {
                "fixtures": {
                    "s2_2_policyguard_latest.md": {
                        "governed_inputs": ["evidence_chain_score"]
                    }
                }
            },
        )
        common_result = self.repo.run("common")
        self.assertEqual(common_result.returncode, 0, msg=common_result.stderr)

        result = self.repo.run("fixtures")
        self.assertEqual(result.returncode, 0, msg=result.stderr)

        policyguard_snapshot = (
            self.repo.root
            / "autoresearch"
            / "contract"
            / "phase2"
            / "fixtures"
            / "snapshot"
            / "s2_2_policyguard_latest.md"
        ).read_text(encoding="utf-8")
        self.assertIn("## 2.2 PolicyGuard", policyguard_snapshot)
        self.assertIn("evidence_chain_score", policyguard_snapshot)

        manifest = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "common" / "context_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(manifest["common_contract_hash"], manifest["contract_content_hash"])
        self.assertEqual(manifest["snapshot_contract_hash"], manifest["contract_content_hash"])
        self.assertIn(
            "phase2/fixtures/snapshot/s2_2_policyguard_latest.md",
            manifest["tracked_files"],
        )

    def test_refresh_common_does_not_rebless_stale_snapshot_hashes(self) -> None:
        common_result = self.repo.run("common")
        self.assertEqual(common_result.returncode, 0, msg=common_result.stderr)
        fixtures_result = self.repo.run("fixtures")
        self.assertEqual(fixtures_result.returncode, 0, msg=fixtures_result.stderr)

        manifest_path = self.repo.root / "autoresearch" / "contract" / "common" / "context_manifest.json"
        before = json.loads(manifest_path.read_text(encoding="utf-8"))
        original_snapshot_hash = before["snapshot_contract_hash"]

        contract_path = self.repo.root / "specs" / "CONTRACT.md"
        contract_path.write_text(
            contract_path.read_text(encoding="utf-8").replace(
                "Execution pipeline body.",
                "Execution pipeline body updated.",
            ),
            encoding="utf-8",
        )

        refreshed_common = self.repo.run("common")
        self.assertEqual(refreshed_common.returncode, 0, msg=refreshed_common.stderr)

        after = json.loads(manifest_path.read_text(encoding="utf-8"))
        self.assertNotEqual(after["contract_content_hash"], original_snapshot_hash)
        self.assertEqual(after["common_contract_hash"], after["contract_content_hash"])
        self.assertEqual(after["snapshot_contract_hash"], original_snapshot_hash)

    def test_refresh_common_fails_closed_on_stale_phase1_fixture_mapping(self) -> None:
        _write_json(
            self.repo.root / "autoresearch" / "contract" / "phase1" / "internal" / "fixture_metadata.json",
            {
                "fixtures": {
                    "sample_contract_gap": {
                        "section_anchor": "9.9"
                    }
                }
            },
        )

        result = self.repo.run("common")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("reference missing sections", result.stderr)

    def test_refresh_fixtures_fails_closed_on_missing_governed_input_reference(self) -> None:
        _write_json(
            self.repo.root / "autoresearch" / "contract" / "common" / "gate_input_registry.json",
            {
                "fixtures": {
                    "s2_2_policyguard_latest.md": {
                        "governed_inputs": ["not_present_here"]
                    }
                }
            },
        )
        common_result = self.repo.run("common")
        self.assertEqual(common_result.returncode, 0, msg=common_result.stderr)

        result = self.repo.run("fixtures")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("resolved 0 times", result.stderr)


if __name__ == "__main__":
    unittest.main()
