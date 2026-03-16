from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HARNESS = REPO_ROOT / "autoresearch" / "skills" / "harness.sh"
EVALUATE_PY = REPO_ROOT / "autoresearch" / "skills" / "evaluate.py"
CONTRACT_TEMPLATE = REPO_ROOT / "autoresearch" / "contract"


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _write_json(path: Path, payload: object) -> None:
    _write_text(path, json.dumps(payload, indent=2))


class _TempContractRepo:
    def __init__(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)

        temp_harness = self.root / "autoresearch" / "skills" / "harness.sh"
        temp_harness.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(HARNESS, temp_harness)
        shutil.copy2(EVALUATE_PY, self.root / "autoresearch" / "skills" / "evaluate.py")
        shutil.copytree(CONTRACT_TEMPLATE, self.root / "autoresearch" / "contract")

        _write_text(
            self.root / "SKILLS" / "contract-gap-detector.md",
            "# contract-gap-detector\nReturn JSON only.\n",
        )
        _write_text(
            self.root / "SKILLS" / "contract-patch.md",
            "# contract-patch\nReturn JSON only.\n",
        )
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
                    "AT-999 is referenced here",
                    "PolicyGuard SHOULD reject when data is missing.",
                    "",
                    "## 2.2 PolicyGuard",
                    "",
                    "evidence_chain_score must fail closed when stale.",
                    "",
                ]
            )
            + "\n",
        )
        self.refresh_context("all")
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        _write_text(
            self.bin_dir / "claude",
            "\n".join(
                [
                    "#!/usr/bin/env python3",
                    "import json",
                    "import os",
                    "import sys",
                    "",
                    "args = sys.argv[1:]",
                    "if '-p' not in args:",
                    "    raise SystemExit('missing -p')",
                    "prompt = args[args.index('-p') + 1]",
                    "mode = os.environ.get('FAKE_CLAUDE_MODE', 'phase2_ok')",
                    "",
                    "if 'contract-gap-detector' in prompt:",
                    "    payload = {",
                    "        'generated_at': '2026-03-14T22:00:00Z',",
                    "        'validator_version': 'fake-claude',",
                    "        'findings': [",
                    "            {",
                    "                'finding_id': 'F-001',",
                    "                'section': '§1',",
                    "                'category': 'cross_ref_broken',",
                    "                'severity': 'P1',",
                    "                'description': 'Broken AT reference.',",
                    "                'evidence': {'line': 3, 'quote': 'AT-999 is referenced here'},",
                    "                'proposed_fix_type': 'mechanical',",
                    "                'proposed_fix': 'Replace AT-999 with AT-101.'",
                    "            }",
                    "        ]",
                    "    }",
                    "    print(json.dumps(payload))",
                    "    raise SystemExit(0)",
                    "",
                    "if 'contract-patch' in prompt:",
                    "    if mode == 'phase2_bad_ref':",
                    "        source_finding = 'F-999'",
                    "        category = 'missing_fail_closed'",
                    "    else:",
                    "        source_finding = 'F-001'",
                    "        category = 'cross_ref_broken'",
                    "    payload = {",
                    "        'generated_at': '2026-03-14T22:00:01Z',",
                    "        'validator_version': 'fake-claude',",
                    "        'proposals': [",
                    "            {",
                    "                'proposal_id': 'P-001',",
                    "                'source_finding': source_finding,",
                    "                'source_finding_category': category,",
                    "                'section': '§1',",
                    "                'change_type': 'mechanical',",
                    "                'rationale': 'Repair the AT reference.',",
                    "                'status': 'proposed',",
                    "                'dedupe_key': 'fixture-1/p-001',",
                    "                'mechanical_ok': True,",
                    "                'mechanical_details': 'Exact token substitution.',",
                    "                'replace_span': {",
                    "                    'start_line': 3,",
                    "                    'end_line': 3,",
                    "                    'old_text': 'AT-999 is referenced here',",
                    "                    'new_text': 'AT-101 is referenced here'",
                    "                },",
                    "                'diff_preview': '\\n'.join([",
                    "                    'diff --git a/specs/CONTRACT.md b/specs/CONTRACT.md',",
                    "                    '--- a/specs/CONTRACT.md',",
                    "                    '+++ b/specs/CONTRACT.md',",
                    "                    '@@ -3,1 +3,1 @@',",
                    "                    '-AT-999 is referenced here',",
                    "                    '+AT-101 is referenced here',",
                    "                ]),",
                    "            }",
                    "        ]",
                    "    }",
                    "    print(json.dumps(payload))",
                    "    raise SystemExit(0)",
                    "",
                    "print('{}')",
                    "",
                ]
            )
            + "\n",
        )
        os.chmod(self.bin_dir / "claude", 0o755)

    def close(self) -> None:
        self.temp_dir.cleanup()

    def refresh_context(self, mode: str) -> None:
        result = subprocess.run(
            [
                "python3",
                str(self.root / "autoresearch" / "contract" / "refresh_context.py"),
                "--root",
                str(self.root),
                "--mode",
                mode,
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
        )
        if result.returncode != 0:
            raise AssertionError(result.stderr or result.stdout)

    def write_phase1_fixture(self, name: str, content: str) -> None:
        _write_text(self.root / "autoresearch" / "contract" / "phase1" / "fixtures" / name, content)

    def write_phase2_fixture(self, name: str, content: str) -> None:
        _write_text(
            self.root / "autoresearch" / "contract" / "phase2" / "fixtures" / "static" / name,
            content,
        )

    def set_contract_hash(self, value: str) -> None:
        manifest = self.root / "autoresearch" / "contract" / "common" / "context_manifest.json"
        payload = json.loads(manifest.read_text(encoding="utf-8"))
        payload["contract_content_hash"] = value
        if "common_contract_hash" in payload:
            payload["common_contract_hash"] = value
        if "snapshot_contract_hash" in payload:
            payload["snapshot_contract_hash"] = value
        _write_json(manifest, payload)

    def set_phase1_eval(self, fixtures: list[str]) -> None:
        _write_json(
            self.root / "autoresearch" / "contract" / "phase1" / "eval.json",
            {
                "description": "phase1 test",
                "tests": [{"fixture": fixture} for fixture in fixtures],
            },
        )

    def set_phase2_eval(self, fixtures: list[str]) -> None:
        _write_json(
            self.root / "autoresearch" / "contract" / "phase2" / "eval.json",
            {
                "description": "phase2 test",
                "tests": [{"fixture": fixture} for fixture in fixtures],
            },
        )

    def run(self, *args: str, mode: str = "phase2_ok") -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.bin_dir}{os.pathsep}{env.get('PATH', '')}"
        env["FAKE_CLAUDE_MODE"] = mode
        return subprocess.run(
            ["bash", str(self.root / "autoresearch" / "skills" / "harness.sh"), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )

    def latest_output_dir(self, phase: str) -> Path:
        output_root = self.root / "autoresearch" / "contract" / phase / "outputs"
        return sorted(path for path in output_root.iterdir() if path.is_dir())[-1]


class ContractPhaseRunTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = _TempContractRepo()

    def test_apply_status_results_allows_enforcement_rejection_to_override_scope_review(self) -> None:
        contract_dir = REPO_ROOT / "autoresearch" / "contract"
        sys.path.insert(0, str(contract_dir))
        try:
            import run_phase as contract_run_phase

            payload = {
                "proposals": [
                    {
                        "proposal_id": "P-001",
                        "status": "proposed",
                    }
                ]
            }
            contradiction_results = {
                "results": [
                    {
                        "proposal_id": "P-001",
                        "status": "pending_scope_review",
                        "reason_code": "SCOPE_NARROWING",
                    }
                ]
            }
            enforcement_results = [
                {
                    "proposal_id": "P-001",
                    "status": "rejected",
                    "reason_code": "ENFORCEMENT_EVIDENCE_MISSING",
                }
            ]

            updated = contract_run_phase.apply_status_results(
                payload, contradiction_results, enforcement_results
            )
        finally:
            sys.path.pop(0)

        self.assertEqual(updated["proposals"][0]["status"], "rejected")

    def tearDown(self) -> None:
        self.repo.close()

    def test_contract_phase1_run_generates_findings_and_results(self) -> None:
        self.repo.write_phase1_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase1_eval(["fixtures/fixture-1.md"])

        result = self.repo.run("contract", "phase1", "run")
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("phase1 run complete", result.stdout)

        output_root = self.repo.root / "autoresearch" / "contract" / "phase1" / "outputs"
        run_dirs = sorted(path for path in output_root.iterdir() if path.is_dir())
        self.assertEqual(len(run_dirs), 1)
        findings_path = run_dirs[0] / "fixture-1" / "findings.json"
        findings = json.loads(findings_path.read_text(encoding="utf-8"))
        self.assertEqual(findings["findings"][0]["finding_id"], "F-001")

        results_lines = (
            self.repo.root / "autoresearch" / "contract" / "phase1" / "results.tsv"
        ).read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(results_lines), 2)
        self.assertIn("phase1 run", results_lines[-1])

    def test_contract_phase2_run_generates_review_package(self) -> None:
        self.repo.write_phase2_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase2_eval(["fixtures/static/fixture-1.md"])

        result = self.repo.run("contract", "phase2", "run")
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("phase2 run complete", result.stdout)

        output_root = self.repo.root / "autoresearch" / "contract" / "phase2" / "outputs"
        run_dirs = sorted(path for path in output_root.iterdir() if path.is_dir())
        self.assertEqual(len(run_dirs), 1)
        run_dir = run_dirs[0]
        fixture_dir = run_dir / "fixture-1"
        self.assertTrue((fixture_dir / "findings.json").exists())
        self.assertTrue((fixture_dir / "proposals.json").exists())
        patched_path = fixture_dir / "patched" / "fixture-1.patched.md"
        self.assertTrue(patched_path.exists())
        self.assertIn("AT-101 is referenced here", patched_path.read_text(encoding="utf-8"))

        index = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "phase2" / "proposals_index.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(len(index), 1)
        self.assertEqual(index[0]["status"], "pending")
        self.assertEqual(index[0]["proposal_count"], 1)
        self.assertIn("CONTRACT_REVIEW_", index[0]["review_package_path"])

        review_dir = self.repo.root / "autoresearch" / "contract" / "phase2" / "review"
        review_files = sorted(path.name for path in review_dir.iterdir() if path.is_file())
        self.assertTrue(any(name.startswith("CONTRACT_REVIEW_") for name in review_files))

    def test_contract_phase1_baseline_and_eval_score_outputs(self) -> None:
        result = self.repo.run("contract", "phase1", "baseline")
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("phase1 baseline complete", result.stdout)

        results_lines = (
            self.repo.root / "autoresearch" / "contract" / "phase1" / "results.tsv"
        ).read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(results_lines), 2)
        self.assertIn("\tbaseline\t", results_lines[-1])

        output_dir = self.repo.latest_output_dir("phase1")
        eval_result = self.repo.run(
            "contract",
            "phase1",
            "eval",
            "--output-dir",
            str(output_dir),
        )
        self.assertEqual(eval_result.returncode, 0, msg=eval_result.stderr)
        self.assertIn("phase1 eval complete", eval_result.stdout)

        results_lines_after = (
            self.repo.root / "autoresearch" / "contract" / "phase1" / "results.tsv"
        ).read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(results_lines_after, results_lines)

    def test_contract_phase2_baseline_scores_without_review_side_effects(self) -> None:
        result = self.repo.run("contract", "phase2", "baseline")
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("phase2 baseline complete", result.stdout)

        results_lines = (
            self.repo.root / "autoresearch" / "contract" / "phase2" / "results.tsv"
        ).read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(results_lines), 2)
        self.assertIn("\tbaseline\t", results_lines[-1])

        index = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "phase2" / "proposals_index.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertEqual(index, [])

        review_dir = self.repo.root / "autoresearch" / "contract" / "phase2" / "review"
        review_files = sorted(path.name for path in review_dir.iterdir() if path.is_file())
        self.assertEqual(review_files, [".gitkeep"])

    def test_contract_phase1_eval_fails_closed_when_outputs_are_missing(self) -> None:
        empty_output_dir = self.repo.root / "tmp" / "missing-outputs"
        empty_output_dir.mkdir(parents=True, exist_ok=True)

        result = self.repo.run(
            "contract",
            "phase1",
            "eval",
            "--output-dir",
            str(empty_output_dir),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing outputs", result.stderr)

    def test_contract_phase2_run_fails_closed_on_cross_file_integrity_error(self) -> None:
        self.repo.write_phase2_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase2_eval(["fixtures/static/fixture-1.md"])

        result = self.repo.run("contract", "phase2", "run", mode="phase2_bad_ref")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("source_finding", result.stderr)

        results_lines = (
            self.repo.root / "autoresearch" / "contract" / "phase2" / "results.tsv"
        ).read_text(encoding="utf-8").strip().splitlines()
        self.assertEqual(len(results_lines), 1)

    def test_contract_phase1_run_fails_closed_on_stale_contract_manifest(self) -> None:
        self.repo.write_phase1_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase1_eval(["fixtures/fixture-1.md"])
        self.repo.set_contract_hash("b" * 64)

        result = self.repo.run("contract", "phase1", "run")
        self.assertEqual(result.returncode, 2)
        self.assertIn("Stale context", result.stderr)

    def test_contract_phase1_run_fails_closed_on_missing_eval_fixture(self) -> None:
        _write_json(
            self.repo.root / "autoresearch" / "contract" / "phase1" / "eval.json",
            {
                "description": "phase1 test",
                "tests": [{"fixture": "fixtures/does-not-exist.md"}],
            },
        )

        result = self.repo.run("contract", "phase1", "run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("references missing fixture", result.stderr)

    def test_contract_phase1_run_fails_closed_on_eval_entry_without_fixture(self) -> None:
        _write_json(
            self.repo.root / "autoresearch" / "contract" / "phase1" / "eval.json",
            {
                "description": "phase1 test",
                "tests": [{}],
            },
        )

        result = self.repo.run("contract", "phase1", "run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing fixture", result.stderr)

    def test_contract_phase1_run_dedupes_same_eval_fixture(self) -> None:
        self.repo.write_phase1_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase1_eval(["fixtures/fixture-1.md", "fixtures/fixture-1.md"])

        result = self.repo.run("contract", "phase1", "run")
        self.assertEqual(result.returncode, 0, msg=result.stderr)

    def test_contract_phase1_run_rejects_workdir_outside_contract_tree(self) -> None:
        self.repo.write_phase1_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase1_eval(["fixtures/fixture-1.md"])
        outside_dir = self.repo.root / "outside-workdir"
        outside_dir.mkdir(parents=True, exist_ok=True)

        result = self.repo.run(
            "contract",
            "phase1",
            "run",
            "--workdir",
            str(outside_dir),
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("--workdir must stay under", result.stderr)

    def test_contract_phase1_run_rejects_eval_fixture_escape(self) -> None:
        self.repo.write_phase1_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase1_eval(["../../../specs/CONTRACT.md"])

        result = self.repo.run("contract", "phase1", "run")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("fixture escapes allowed roots", result.stderr)

    def test_contract_refresh_commands_rebuild_context_and_snapshots(self) -> None:
        result = self.repo.run("contract", "refresh-all")
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("refresh-common complete", result.stdout)
        self.assertIn("refresh-fixtures complete", result.stdout)

        snapshot_path = (
            self.repo.root
            / "autoresearch"
            / "contract"
            / "phase2"
            / "fixtures"
            / "snapshot"
            / "s1_execution_pipeline_latest.md"
        )
        self.assertTrue(snapshot_path.exists())
        manifest = json.loads(
            (self.repo.root / "autoresearch" / "contract" / "common" / "context_manifest.json").read_text(
                encoding="utf-8"
            )
        )
        self.assertIn("common/section_index.md", manifest["tracked_files"])

    def test_phase2_snapshot_run_requires_refresh_fixtures_after_contract_change(self) -> None:
        self.repo.set_phase2_eval(["fixtures/snapshot/s1_execution_pipeline_latest.md"])

        contract_path = self.repo.root / "specs" / "CONTRACT.md"
        contract_path.write_text(
            contract_path.read_text(encoding="utf-8").replace(
                "PolicyGuard SHOULD reject when data is missing.",
                "PolicyGuard SHOULD reject when data is stale.",
            ),
            encoding="utf-8",
        )
        self.repo.refresh_context("common")

        result = self.repo.run("contract", "phase2", "run")
        self.assertEqual(result.returncode, 2)
        self.assertIn("refresh-fixtures", result.stderr)

        self.repo.refresh_context("fixtures")
        rerun = self.repo.run("contract", "phase2", "run")
        self.assertEqual(rerun.returncode, 0, msg=rerun.stderr)


if __name__ == "__main__":
    unittest.main()
