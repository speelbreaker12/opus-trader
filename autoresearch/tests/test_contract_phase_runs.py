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


def _write_executable(path: Path, text: str) -> None:
    _write_text(path, text)
    os.chmod(path, 0o755)


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
        _write_json(
            self.root / "autoresearch" / "contract" / "phase1" / "internal" / "fixture_metadata.json",
            {
                "fixtures": {
                    "sample_contract_gap": {
                        "section_anchor": "1",
                        "injected_tokens": ["AT-999"],
                    },
                    "live_policyguard": {
                        "section_anchor": "2.2",
                        "injected_tokens": [],
                    },
                }
            },
        )
        _write_text(
            self.root / "autoresearch" / "contract" / "phase1" / "fixtures" / "live_policyguard.md",
            "# stale fixture\n",
        )
        _write_json(
            self.root / "autoresearch" / "contract" / "phase2" / "internal" / "snapshot_targets.json",
            {
                "targets": [
                    {
                        "fixture_path": "phase2/fixtures/snapshot/s2_2_policyguard_latest.md",
                        "section_anchor": "2.2",
                    },
                    {
                        "fixture_path": "phase2/fixtures/snapshot/s1_execution_pipeline_latest.md",
                        "section_anchor": "1",
                    },
                ]
            },
        )
        self._reset_runtime_artifacts()
        self._set_default_eval_fixtures()
        self.refresh_context("all")
        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        _write_executable(
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
    def _reset_runtime_artifacts(self) -> None:
        for phase in ("phase1", "phase2"):
            outputs_dir = self.root / "autoresearch" / "contract" / phase / "outputs"
            for path in outputs_dir.iterdir():
                if path.name.startswith("."):
                    continue
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            _write_text(
                self.root / "autoresearch" / "contract" / phase / "results.tsv",
                "commit\tscore\tpassed\ttotal\tstatus\tdescription\n",
            )

        _write_json(
            self.root / "autoresearch" / "contract" / "phase2" / "proposals_index.json",
            [],
        )
        review_dir = self.root / "autoresearch" / "contract" / "phase2" / "review"
        for path in review_dir.iterdir():
            if path.name.startswith("."):
                continue
            if path.is_dir():
                shutil.rmtree(path)
            else:
                path.unlink()

    def _set_default_eval_fixtures(self) -> None:
        _write_json(
            self.root / "autoresearch" / "contract" / "phase1" / "eval.json",
            {
                "description": "phase1 test",
                "tests": [
                    {
                        "id": "sample-phase1-gap",
                        "fixture": "fixtures/sample_contract_gap.md",
                        "output_file": "sample_contract_gap/findings.json",
                        "assertions": [
                            {
                                "id": "phase1-schema",
                                "check": "findings payload matches schema",
                                "rule": {
                                    "type": "json_schema_valid",
                                    "schema_path": "autoresearch/contract/phase1/findings.schema.json",
                                },
                            },
                            {
                                "id": "phase1-category",
                                "check": "detector identifies the planted cross_ref_broken gap",
                                "rule": {
                                    "type": "json_field_match",
                                    "path": "$.findings[*].category",
                                    "value": "cross_ref_broken",
                                    "match_mode": "any",
                                },
                            },
                            {
                                "id": "phase1-count",
                                "check": "detector emits a tight finding count",
                                "rule": {
                                    "type": "json_array_count_bounds",
                                    "path": "$.findings",
                                    "min": 1,
                                    "max": 3,
                                },
                            },
                            {
                                "id": "phase1-unique-ids",
                                "check": "finding ids stay unique",
                                "rule": {
                                    "type": "json_unique_field",
                                    "path": "$.findings[*].finding_id",
                                },
                            },
                            {
                                "id": "phase1-evidence",
                                "check": "evidence points at the planted broken AT token",
                                "rule": {
                                    "type": "json_field_match",
                                    "path": "$.findings[*].evidence.quote",
                                    "pattern": "AT-999",
                                    "match_mode": "any",
                                },
                            },
                        ],
                    }
                ],
            },
        )
        _write_json(
            self.root / "autoresearch" / "contract" / "phase2" / "eval.json",
            {
                "description": "phase2 test",
                "tests": [
                    {
                        "id": "sample-phase2-patch",
                        "fixture": "fixtures/static/sample_contract_patch.md",
                        "output_file": "sample_contract_patch/proposals.json",
                        "assertions": [
                            {
                                "id": "phase2-schema",
                                "check": "proposal payload matches schema",
                                "rule": {
                                    "type": "json_schema_valid",
                                    "schema_path": "autoresearch/contract/phase2/proposals.schema.json",
                                },
                            },
                            {
                                "id": "phase2-source-finding-exists",
                                "check": "proposal source_finding resolves in sibling findings.json",
                                "rule": {
                                    "type": "json_cross_ref_exists",
                                    "target_path": "findings.json",
                                    "source_json_path": "$.proposals[*].source_finding",
                                    "target_json_path": "$.findings[*].finding_id",
                                },
                            },
                            {
                                "id": "phase2-source-fields-match",
                                "check": "proposal category and section match sibling finding fields",
                                "rule": {
                                    "type": "json_cross_ref_match",
                                    "target_path": "findings.json",
                                    "source_records_path": "$.proposals[*]",
                                    "target_records_path": "$.findings[*]",
                                    "source_lookup_field": "source_finding",
                                    "target_lookup_field": "finding_id",
                                    "field_map": {
                                        "source_finding_category": "category",
                                        "section": "section",
                                    },
                                },
                            },
                            {
                                "id": "phase2-unique-ids",
                                "check": "proposal ids stay unique",
                                "rule": {
                                    "type": "json_unique_field",
                                    "path": "$.proposals[*].proposal_id",
                                },
                            },
                            {
                                "id": "phase2-unique-dedupe",
                                "check": "dedupe keys stay unique",
                                "rule": {
                                    "type": "json_unique_field",
                                    "path": "$.proposals[*].dedupe_key",
                                },
                            },
                            {
                                "id": "phase2-span-resolves",
                                "check": "mechanical replace spans resolve to one exact fixture slice",
                                "rule": {
                                    "type": "resolved_span_exists",
                                    "path": "$.proposals[?(@.mechanical_ok==true)].replace_span",
                                    "fixture_path": "autoresearch/contract/phase2/fixtures/static/sample_contract_patch.md",
                                    "require_unique": True,
                                },
                            },
                            {
                                "id": "phase2-no-noop",
                                "check": "mechanical replace spans are not normalized no-ops",
                                "rule": {
                                    "type": "json_field_not_match",
                                    "path": "$.proposals[?(@.mechanical_ok==true)].replace_span",
                                    "compare_fields": {
                                        "left": "new_text",
                                        "right": "old_text",
                                    },
                                    "normalize_whitespace": True,
                                },
                            },
                        ],
                    },
                    {
                        "id": "sample-phase2-patched",
                        "fixture": "fixtures/static/sample_contract_patch.md",
                        "output_file": "sample_contract_patch/patched/sample_contract_patch.patched.md",
                        "assertions": [
                            {
                                "id": "phase2-patched-contains-fix",
                                "check": "patched fixture contains the replacement AT reference",
                                "rule": {
                                    "type": "contains",
                                    "value": "AT-101 is referenced here",
                                },
                            },
                            {
                                "id": "phase2-patched-removes-old",
                                "check": "patched fixture no longer contains the broken AT reference",
                                "rule": {
                                    "type": "not_contains",
                                    "value": "AT-999 is referenced here",
                                },
                            },
                        ],
                    },
                ],
            },
        )

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

    def run(
        self,
        *args: str,
        mode: str = "phase2_ok",
        extra_env: dict[str, str] | None = None,
    ) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.bin_dir}{os.pathsep}{env.get('PATH', '')}"
        env["FAKE_CLAUDE_MODE"] = mode
        if extra_env:
            env.update(extra_env)
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

    def test_phase1_live_eval_requires_semantic_assertions(self) -> None:
        payload = json.loads(
            (REPO_ROOT / "autoresearch" / "contract" / "phase1" / "eval.json").read_text(
                encoding="utf-8"
            )
        )
        live_tests = [test for test in payload["tests"] if test["id"].startswith("live-")]
        self.assertEqual(len(live_tests), 5)

        for test in live_tests:
            rule_types = [assertion["rule"]["type"] for assertion in test["assertions"]]
            self.assertIn("json_array_count_bounds", rule_types, msg=test["id"])
            self.assertTrue(
                any(
                    assertion["rule"]["type"] == "json_field_match"
                    and assertion["rule"]["path"]
                    in {"$.findings[*].category", "$.findings[*].severity", "$.findings[*].section"}
                    for assertion in test["assertions"]
                ),
                msg=test["id"],
            )

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

    def test_contract_phase2_run_supports_codex_backend_with_short_prompt_wrapper(self) -> None:
        self.repo.write_phase2_fixture(
            "fixture-1.md",
            "# Fixture\n\nAT-999 is referenced here\n",
        )
        self.repo.set_phase2_eval(["fixtures/static/fixture-1.md"])
        (self.repo.bin_dir / "claude").unlink()
        fake_auth = self.repo.root / "fake-auth.json"
        _write_text(fake_auth, '{"provider":"test"}\n')
        _write_executable(
            self.repo.bin_dir / "codex",
            "\n".join(
                [
                    "#!/usr/bin/env python3",
                    "import json",
                    "import sys",
                    "from pathlib import Path",
                    "",
                    "args = sys.argv[1:]",
                    "if not args or args[0] != 'exec':",
                    "    print(f'unexpected codex args: {args}', file=sys.stderr)",
                    "    raise SystemExit(2)",
                    "prompt = sys.stdin.read()",
                    "if 'Read exactly one file and nothing else:' not in prompt:",
                    "    print('missing short prompt file-read instruction', file=sys.stderr)",
                    "    raise SystemExit(3)",
                    "if 'Fixture contents:' in prompt or 'Required schema:' in prompt:",
                    "    print('wrapper leaked large inline prompt content', file=sys.stderr)",
                    "    raise SystemExit(4)",
                    "if '--output-last-message' not in args:",
                    "    print('missing --output-last-message', file=sys.stderr)",
                    "    raise SystemExit(5)",
                    "last_path = Path(args[args.index('--output-last-message') + 1])",
                    "if 'Detector findings JSON:' in prompt:",
                    "    payload = {",
                    "        'generated_at': '2026-03-20T19:40:00Z',",
                    "        'validator_version': 'fake-codex',",
                    "        'proposals': [",
                    "            {",
                    "                'proposal_id': 'P-001',",
                    "                'source_finding': 'F-001',",
                    "                'source_finding_category': 'cross_ref_broken',",
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
                    "else:",
                    "    payload = {",
                    "        'generated_at': '2026-03-20T19:39:00Z',",
                    "        'validator_version': 'fake-codex',",
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
                    "last_path.write_text(json.dumps(payload), encoding='utf-8')",
                    "print(json.dumps(payload))",
                    "",
                ]
            )
            + "\n",
        )

        result = self.repo.run(
            "contract",
            "phase2",
            "run",
            "--backend",
            "codex",
            "--model",
            "gpt-5.4",
            extra_env={"CONTRACT_CODEX_AUTH_JSON": str(fake_auth)},
        )
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertIn("phase2 run complete", result.stdout)

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

    def test_contract_phase1_run_fails_closed_on_stale_live_fixture_until_refresh_common(self) -> None:
        self.repo.set_phase1_eval(["fixtures/live_policyguard.md"])

        live_fixture = (
            self.repo.root
            / "autoresearch"
            / "contract"
            / "phase1"
            / "fixtures"
            / "live_policyguard.md"
        )
        live_fixture.write_text("# drifted live fixture\n", encoding="utf-8")

        stale_result = self.repo.run("contract", "phase1", "run")
        self.assertEqual(stale_result.returncode, 2)
        self.assertIn("Run 'harness.sh contract refresh-common' first", stale_result.stderr)

        self.repo.refresh_context("common")

        refreshed_result = self.repo.run("contract", "phase1", "run")
        self.assertEqual(refreshed_result.returncode, 0, msg=refreshed_result.stderr)
        self.assertIn("phase1 run complete", refreshed_result.stdout)

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
