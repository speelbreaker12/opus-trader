"""Tests for scaffold.py skeleton generator."""
from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

from python.proof_graph.scaffold import scaffold

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
PRD = REPO_ROOT / "plans" / "prd.json"
CONTRACT = REPO_ROOT / "specs" / "CONTRACT.md"


class TestScaffold(unittest.TestCase):
    def test_creates_output_dir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "nested" / "deep"
            result = scaffold(
                story_id="S1-007",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            self.assertTrue(result.exists())
            self.assertTrue(out_dir.is_dir())

    def test_generates_valid_json(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S1-007",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertEqual(data["schema_version"], 1)
            self.assertEqual(data["story_meta"]["story_id"], "S1-007")

    def test_populates_ats_from_prd(self):
        """S1-001 has enforcing_contract_ats: [AT-905, AT-901]."""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S1-001",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            at_ids = [at["at_id"] for at in data["ats"]]
            self.assertIn("AT-905", at_ids)
            self.assertIn("AT-901", at_ids)

    def test_placeholders_present(self):
        """Scaffolded graph should have <FILL> placeholders."""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S1-001",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            text = result.read_text(encoding="utf-8")
            self.assertIn("<FILL>", text)

    def test_policy_story_empty_ats(self):
        """Policy stories have no enforcing_contract_ats."""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S0-000",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertEqual(data["ats"], [])
            self.assertEqual(data["story_meta"]["category"], "policy")

    def test_head_sha_is_40_chars(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S1-007",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertEqual(len(data["head_sha"]), 40)

    def test_unknown_story_id(self):
        """Unknown story ID should still produce a skeleton with <FILL> values."""
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S99-999",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertEqual(data["story_meta"]["story_id"], "S99-999")
            self.assertEqual(data["story_meta"]["category"], "<FILL>")

    def test_generated_at_present(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            out_dir = Path(tmpdir) / "story"
            result = scaffold(
                story_id="S1-007",
                prd_path=PRD,
                contract_path=CONTRACT,
                output_dir=out_dir,
            )
            data = json.loads(result.read_text(encoding="utf-8"))
            self.assertIn("generated_at", data)
            self.assertTrue(len(data["generated_at"]) > 0)


if __name__ == "__main__":
    unittest.main()
