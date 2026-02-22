"""Tests for proof graph schema parsing and deny-unknown-fields."""
from __future__ import annotations

import copy
import json
import unittest
from pathlib import Path

from python.proof_graph.schema import ProofGraph, ProofGraphParseError

FIXTURES = Path(__file__).parent / "fixtures"


def _load(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class TestSchemaVersion(unittest.TestCase):
    def test_valid_version(self):
        data = _load("valid_proof_graph.json")
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.schema_version, 1)

    def test_unsupported_version(self):
        data = _load("valid_proof_graph.json")
        data["schema_version"] = 2
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("unsupported schema_version", str(ctx.exception))

    def test_missing_version(self):
        data = _load("valid_proof_graph.json")
        del data["schema_version"]
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("schema_version", str(ctx.exception))


class TestDenyUnknownFields(unittest.TestCase):
    def test_unknown_top_level(self):
        data = _load("valid_proof_graph.json")
        data["extra_field"] = "surprise"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("extra_field", str(ctx.exception))

    def test_unknown_in_story_meta(self):
        data = _load("valid_proof_graph.json")
        data["story_meta"]["bogus"] = True
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("bogus", str(ctx.exception))

    def test_unknown_in_at_entry(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["phantom_field"] = 42
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("phantom_field", str(ctx.exception))

    def test_unknown_in_test_entry(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["tests"][0]["extra"] = "x"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("extra", str(ctx.exception))

    def test_unknown_in_causal_proof(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["tests"][0]["causal_proof"]["weird"] = 1
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("weird", str(ctx.exception))


class TestValidFixtures(unittest.TestCase):
    def test_valid_proof_graph(self):
        data = _load("valid_proof_graph.json")
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.story_meta.story_id, "S1-007")
        self.assertEqual(len(pg.ats), 1)
        self.assertEqual(pg.ats[0].at_id, "AT-201")
        self.assertEqual(len(pg.ats[0].tests), 2)

    def test_minimal_policy_story(self):
        data = _load("minimal_policy_story.json")
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.story_meta.category, "policy")
        self.assertEqual(len(pg.ats), 0)

    def test_all_invalid_fixtures_parse(self):
        """All invalid_*.json files should parse (schema-wise) — rules catch the errors."""
        for name in ["invalid_blocking.json", "invalid_stale_sha.json",
                      "invalid_phantom_at.json", "invalid_fail_open_risk.json"]:
            with self.subTest(name=name):
                data = _load(name)
                pg = ProofGraph.from_dict(data)
                self.assertIsNotNone(pg)


class TestInvalidEnumValues(unittest.TestCase):
    def test_bad_verdict(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["at_verdict"]["verdict"] = "INVALID_VALUE"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("INVALID_VALUE", str(ctx.exception))

    def test_bad_test_kind(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["tests"][0]["kind"] = "MAYBE"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("MAYBE", str(ctx.exception))


class TestMissingRequiredFields(unittest.TestCase):
    def test_missing_head_sha(self):
        data = _load("valid_proof_graph.json")
        del data["head_sha"]
        with self.assertRaises(ProofGraphParseError):
            ProofGraph.from_dict(data)

    def test_missing_ats(self):
        data = _load("valid_proof_graph.json")
        del data["ats"]
        with self.assertRaises(ProofGraphParseError):
            ProofGraph.from_dict(data)

    def test_missing_story_meta(self):
        data = _load("valid_proof_graph.json")
        del data["story_meta"]
        with self.assertRaises(ProofGraphParseError):
            ProofGraph.from_dict(data)


class TestOptionalFields(unittest.TestCase):
    def test_debt_register_optional(self):
        data = _load("valid_proof_graph.json")
        del data["debt_register"]
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.debt_register, [])

    def test_at_debt_optional(self):
        data = _load("valid_proof_graph.json")
        # debt is not present in valid fixture — should parse fine
        self.assertIsNone(ProofGraph.from_dict(data).ats[0].debt)

    def test_equivalent_mutants_optional(self):
        data = _load("valid_proof_graph.json")
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.ats[0].equivalent_mutants, [])


if __name__ == "__main__":
    unittest.main()
