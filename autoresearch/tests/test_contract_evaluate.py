from __future__ import annotations

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
EVALUATE_PY = REPO_ROOT / "autoresearch" / "skills" / "evaluate.py"

_SPEC = importlib.util.spec_from_file_location("contract_evaluate", EVALUATE_PY)
assert _SPEC is not None and _SPEC.loader is not None
evaluate = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(evaluate)


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _write_json(path: Path, payload: object) -> None:
    _write_text(path, json.dumps(payload, indent=2) + "\n")


class ContractEvaluateTests(unittest.TestCase):
    def test_run_evaluation_supports_contract_json_rules(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            schema_path = root / "schemas" / "findings.schema.json"
            _write_json(
                schema_path,
                {
                    "type": "object",
                    "required": ["findings"],
                    "properties": {
                        "findings": {
                            "type": "array",
                            "items": {
                                "type": "object",
                                "required": ["finding_id", "category", "evidence"],
                                "properties": {
                                    "finding_id": {"type": "string"},
                                    "category": {"type": "string"},
                                    "evidence": {
                                        "type": "object",
                                        "required": ["quote"],
                                        "properties": {"quote": {"type": "string"}},
                                    },
                                },
                            },
                        }
                    },
                },
            )
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {
                            "finding_id": "F-001",
                            "category": "cross_ref_broken",
                            "evidence": {"quote": "AT-999 is referenced here"},
                        }
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/findings.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_schema_valid",
                                    "schema_path": "schemas/findings.schema.json",
                                },
                            },
                            {
                                "id": "A2",
                                "rule": {
                                    "type": "json_field_match",
                                    "path": "$.findings[*].category",
                                    "value": "cross_ref_broken",
                                },
                            },
                            {
                                "id": "A3",
                                "rule": {
                                    "type": "json_array_count_bounds",
                                    "path": "$.findings",
                                    "min": 1,
                                    "max": 2,
                                },
                            },
                            {
                                "id": "A4",
                                "rule": {
                                    "type": "json_unique_field",
                                    "path": "$.findings[*].finding_id",
                                },
                            },
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 1.0)
            self.assertEqual(results["passed"], 4)
            self.assertEqual(results["total"], 4)

    def test_json_field_not_match_detects_forbidden_quote(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {
                            "finding_id": "F-001",
                            "category": "cross_ref_broken",
                            "evidence": {"quote": "outside-token leaked into evidence"},
                        }
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/findings.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_field_not_match",
                                    "path": "$.findings[*].evidence.quote",
                                    "pattern": "outside-token",
                                },
                            }
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 0.0)
            self.assertIn("forbidden value", results["tests"][0]["assertions"][0]["reason"])

    def test_json_field_match_requires_all_selected_values_by_default(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {"finding_id": "F-001", "category": "cross_ref_broken"},
                        {"finding_id": "F-002", "category": "missing_fail_closed"},
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/findings.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_field_match",
                                    "path": "$.findings[*].category",
                                    "value": "cross_ref_broken",
                                },
                            }
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 0.0)
            self.assertIn("1/2", results["tests"][0]["assertions"][0]["reason"])

    def test_json_field_match_filtered_path_keeps_severity_and_section_correlated(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {
                            "finding_id": "F-001",
                            "severity": "P0",
                            "section": "Acceptance Tests",
                        },
                        {
                            "finding_id": "F-002",
                            "severity": "P1",
                            "section": "Stale-L2 body / gate interaction",
                        },
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/findings.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_field_match",
                                    "path": '$.findings[?(@.severity=="P0")].section',
                                    "pattern": "Stale-L2",
                                    "match_mode": "any",
                                },
                            }
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 0.0)
            self.assertIn("no selected values matched", results["tests"][0]["assertions"][0]["reason"])

    def test_cross_ref_and_resolved_span_rules_pass(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture_path = root / "fixtures" / "fixture-1.md"
            _write_text(
                fixture_path,
                "# Fixture\n\nAT-999 is referenced here\nPolicyGuard SHOULD reject when data is missing.\n",
            )
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            proposals_path = root / "outputs" / "fixture-1" / "proposals.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {
                            "finding_id": "F-001",
                            "category": "cross_ref_broken",
                            "section": "§1",
                        }
                    ]
                },
            )
            _write_json(
                proposals_path,
                {
                    "proposals": [
                        {
                            "proposal_id": "P-001",
                            "source_finding": "F-001",
                            "source_finding_category": "cross_ref_broken",
                            "section": "§1",
                            "replace_span": {
                                "start_line": 3,
                                "end_line": 3,
                                "old_text": "AT-999 is referenced here",
                                "new_text": "AT-101 is referenced here",
                            },
                        }
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/proposals.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_cross_ref_exists",
                                    "target_path": "findings.json",
                                    "source_json_path": "$.proposals[*].source_finding",
                                    "target_json_path": "$.findings[*].finding_id",
                                },
                            },
                            {
                                "id": "A2",
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
                                "id": "A3",
                                "rule": {
                                    "type": "resolved_span_exists",
                                    "path": "$.proposals[*].replace_span",
                                    "fixture_path": "fixtures/fixture-1.md",
                                    "require_unique": True,
                                },
                            },
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 1.0)
            self.assertEqual(results["passed"], 3)

    def test_cross_ref_rules_fail_closed_on_duplicate_target_ids(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            findings_path = root / "outputs" / "fixture-1" / "findings.json"
            proposals_path = root / "outputs" / "fixture-1" / "proposals.json"
            _write_json(
                findings_path,
                {
                    "findings": [
                        {"finding_id": "F-001", "category": "cross_ref_broken", "section": "§1"},
                        {"finding_id": "F-001", "category": "cross_ref_broken", "section": "§1"},
                    ]
                },
            )
            _write_json(
                proposals_path,
                {
                    "proposals": [
                        {
                            "proposal_id": "P-001",
                            "source_finding": "F-001",
                            "source_finding_category": "cross_ref_broken",
                            "section": "§1",
                        }
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/proposals.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "json_cross_ref_exists",
                                    "target_path": "findings.json",
                                    "source_json_path": "$.proposals[*].source_finding",
                                    "target_json_path": "$.findings[*].finding_id",
                                },
                            }
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 0.0)
            self.assertIn("must be unique", results["tests"][0]["assertions"][0]["reason"])

    def test_validate_eval_config_rejects_snapshot_span_without_snapshot_path(self) -> None:
        eval_config = {
            "tests": [
                {
                    "id": "fixture-1",
                    "assertions": [
                        {
                            "id": "A1",
                            "rule": {
                                "type": "resolved_span_exists",
                                "path": "$.proposals[*].replace_span",
                                "fixture_path": "phase2/fixtures/snapshot/fixture-1.md",
                            },
                        }
                    ],
                }
            ]
        }

        with self.assertRaisesRegex(ValueError, "requires snapshot_path"):
            evaluate.validate_eval_config(eval_config, REPO_ROOT)

    def test_resolved_span_exists_fails_for_non_unique_old_text(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            fixture_path = root / "fixtures" / "fixture-1.md"
            _write_text(
                fixture_path,
                "# Fixture\n\nAT-999 is referenced here\nAT-999 is referenced here\n",
            )
            proposals_path = root / "outputs" / "fixture-1" / "proposals.json"
            _write_json(
                proposals_path,
                {
                    "proposals": [
                        {
                            "replace_span": {
                                "start_line": 3,
                                "end_line": 3,
                                "old_text": "AT-999 is referenced here",
                                "new_text": "AT-101 is referenced here",
                            }
                        }
                    ]
                },
            )
            eval_config = {
                "tests": [
                    {
                        "id": "fixture-1",
                        "output_file": "fixture-1/proposals.json",
                        "assertions": [
                            {
                                "id": "A1",
                                "rule": {
                                    "type": "resolved_span_exists",
                                    "path": "$.proposals[*].replace_span",
                                    "fixture_path": "fixtures/fixture-1.md",
                                    "require_unique": True,
                                },
                            }
                        ],
                    }
                ]
            }

            results = evaluate.run_evaluation(
                eval_config,
                root / "outputs",
                eval_path=root / "eval.json",
                skill_dir=root,
            )
            self.assertEqual(results["score"], 0.0)
            self.assertIn("unique target slice", results["tests"][0]["assertions"][0]["reason"])

    def test_validate_eval_config_rejects_non_unique_span_rule_opt_out(self) -> None:
        eval_config = {
            "tests": [
                {
                    "id": "fixture-1",
                    "assertions": [
                        {
                            "id": "A1",
                            "rule": {
                                "type": "resolved_span_exists",
                                "path": "$.proposals[*].replace_span",
                                "fixture_path": "fixtures/fixture-1.md",
                                "require_unique": False,
                            },
                        }
                    ],
                }
            ]
        }

        with self.assertRaisesRegex(ValueError, "requires unique exact target resolution"):
            evaluate.validate_eval_config(eval_config, REPO_ROOT)


if __name__ == "__main__":
    unittest.main()
