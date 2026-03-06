"""Tests for init.py — V2 skeleton builder."""
from __future__ import annotations

import json
import os
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent.parent
PRD = REPO_ROOT / "plans" / "prd.json"
CONTRACT = REPO_ROOT / "specs" / "CONTRACT.md"


class TestInitV2(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.output_dir = Path(self.tmpdir) / "output"

    def _init(
        self,
        story_id: str,
        premortem_path: Path | None = None,
    ) -> dict:
        from python.proof_graph.init import init_v2

        out_path = init_v2(
            story_id=story_id,
            prd_path=PRD,
            contract_path=CONTRACT,
            output_dir=self.output_dir,
            premortem_path=premortem_path,
        )
        return json.loads(out_path.read_text(encoding="utf-8"))

    def test_schema_version_is_2(self):
        graph = self._init("S1-007")
        self.assertEqual(graph["schema_version"], 2)

    def test_story_meta_populated(self):
        graph = self._init("S1-007")
        sm = graph["story_meta"]
        self.assertEqual(sm["story_id"], "S1-007")
        self.assertIn("category", sm)
        self.assertIn("enforcement_point", sm)
        self.assertIn("loss_mode", sm)
        self.assertIn("safety_critical", sm)

    def test_evidence_entries_stubs(self):
        graph = self._init("S1-007")
        for at in graph["ats"]:
            ee = at["enforcement"]["evidence_entries"]
            # Each evidence entry has required fields
            for entry in ee:
                self.assertIn("file", entry)
                self.assertIn("line_start", entry)
                self.assertIn("line_end", entry)
                self.assertIn("symbol", entry)

    def test_wiring_v2_fields(self):
        graph = self._init("S1-007")
        for at in graph["ats"]:
            w = at["wiring"]
            self.assertIn("caller_chain", w)
            self.assertEqual(w["caller_chain"], [])
            self.assertIn("entrypoint", w)
            self.assertIn("proof_type", w)

    def test_trading_halt_trigger_false(self):
        graph = self._init("S1-007")
        self.assertFalse(graph["story_verdict"]["trading_halt_trigger"])

    def test_meta_populated(self):
        graph = self._init("S1-007")
        meta = graph["meta"]
        self.assertIn("hints", meta)
        self.assertIn("init_tool_version", meta)
        self.assertEqual(meta["init_tool_version"], "2.0.0")
        self.assertIn("init_timestamp", meta)

    def test_meta_hints_per_at(self):
        graph = self._init("S1-007")
        meta = graph["meta"]
        for at in graph["ats"]:
            at_id = at["at_id"]
            self.assertIn(at_id, meta["hints"])
            self.assertIn("safety_critical", meta["hints"][at_id])
            self.assertIn("loss_mode_level", meta["hints"][at_id])

    def test_extra_discovered_field(self):
        graph = self._init("S1-007")
        for at in graph["ats"]:
            self.assertIn("extra_discovered", at)
            self.assertFalse(at["extra_discovered"])

    def test_premortem_path_parsing(self):
        """When canonical premortem file exists, section values are populated."""
        premortem_path = Path(self.tmpdir) / "S1-007_premortem.md"
        premortem_path.write_text(
            "# Premortem\n"
            "## Section 2\n"
            "assumptions: ALL_VALIDATED\n"
            "## Section 4\n"
            "decision match: YES\n"
            "## Section 5\n"
            "wrong impl blocked: ALL\n",
            encoding="utf-8",
        )
        graph = self._init("S1-007", premortem_path=premortem_path)
        for at in graph["ats"]:
            pc = at["premortem_checks"]
            self.assertEqual(pc.get("section5_wrong_impl_blocked"), "ALL")
            self.assertEqual(pc.get("section4_decision_match"), "YES")
            self.assertEqual(pc.get("section2_assumptions"), "ALL_VALIDATED")

    def test_premortem_missing_no_crash(self):
        """When premortem file doesn't exist, premortem fields are absent."""
        premortem_path = Path(self.tmpdir) / "missing_premortem.md"
        graph = self._init("S1-007", premortem_path=premortem_path)
        for at in graph["ats"]:
            pc = at["premortem_checks"]
            self.assertNotIn("section5_wrong_impl_blocked", pc)
            self.assertNotIn("section4_decision_match", pc)
            self.assertNotIn("section2_assumptions", pc)

    def test_default_premortem_path_uses_repo_root_not_cwd(self):
        """Default premortem lookup should follow the repo inputs, not the caller cwd."""
        from python.proof_graph.init import init_v2

        repo_root = Path(self.tmpdir) / "repo"
        (repo_root / "plans").mkdir(parents=True)
        (repo_root / "specs").mkdir()
        (repo_root / "reviews" / "premortems").mkdir(parents=True)

        (repo_root / "plans" / "prd.json").write_text(
            json.dumps(
                {
                    "items": [
                        {
                            "id": "S9-171",
                            "category": "execution",
                            "enforcement_point": "plans/parallel_review.sh",
                            "scope": {"touch": ["plans/parallel_review.sh"]},
                            "loss_mode": {"level": "HIGH"},
                            "enforcing_contract_ats": ["AT-9171"],
                        }
                    ]
                }
            ),
            encoding="utf-8",
        )
        (repo_root / "specs" / "CONTRACT.md").write_text("# contract\n", encoding="utf-8")
        (repo_root / "reviews" / "premortems" / "S9-171_premortem.md").write_text(
            "# Premortem\n"
            "## Section 2\n"
            "assumptions: ALL_VALIDATED\n"
            "## Section 4\n"
            "decision match: YES\n"
            "## Section 5\n"
            "wrong impl blocked: ALL\n",
            encoding="utf-8",
        )

        outside_cwd = Path(self.tmpdir) / "outside"
        outside_cwd.mkdir()
        previous_cwd = Path.cwd()
        try:
            os.chdir(outside_cwd)
            out_path = init_v2(
                story_id="S9-171",
                prd_path=repo_root / "plans" / "prd.json",
                contract_path=repo_root / "specs" / "CONTRACT.md",
                output_dir=self.output_dir,
            )
        finally:
            os.chdir(previous_cwd)

        graph = json.loads(out_path.read_text(encoding="utf-8"))
        premortem_checks = graph["ats"][0]["premortem_checks"]
        self.assertEqual(premortem_checks.get("section5_wrong_impl_blocked"), "ALL")
        self.assertEqual(premortem_checks.get("section4_decision_match"), "YES")
        self.assertEqual(premortem_checks.get("section2_assumptions"), "ALL_VALIDATED")

    def test_unknown_story_id(self):
        """Unknown story still generates a skeleton with <FILL> placeholders."""
        graph = self._init("XTEST-999")
        self.assertEqual(graph["schema_version"], 2)
        self.assertEqual(graph["story_meta"]["story_id"], "XTEST-999")
        self.assertEqual(graph["ats"], [])


if __name__ == "__main__":
    unittest.main()
