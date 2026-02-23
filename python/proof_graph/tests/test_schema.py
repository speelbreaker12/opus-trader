"""Tests for proof graph schema parsing and deny-unknown-fields."""
from __future__ import annotations

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

    def test_unsupported_version_high(self):
        data = _load("valid_proof_graph.json")
        data["schema_version"] = 99
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("unsupported schema_version", str(ctx.exception))

    def test_unsupported_version_zero(self):
        data = _load("valid_proof_graph.json")
        data["schema_version"] = 0
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("unsupported schema_version", str(ctx.exception))

    def test_unsupported_version_string(self):
        data = _load("valid_proof_graph.json")
        data["schema_version"] = "2"
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

    def test_valid_proof_graph_v2(self):
        data = _load("valid_proof_graph_v2.json")
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.schema_version, 2)
        self.assertEqual(pg.story_meta.story_id, "S1-007")
        # V2 fields
        at = pg.ats[0]
        self.assertEqual(len(at.enforcement.evidence_entries), 1)
        ee = at.enforcement.evidence_entries[0]
        self.assertEqual(ee.file, "crates/soldier_core/src/execution/build_order_intent.rs")
        self.assertEqual(ee.line_start, 40)
        self.assertEqual(ee.line_end, 45)
        self.assertEqual(ee.symbol, "check_metadata_staleness")
        self.assertIn("threshold", ee.snippet)
        # caller_chain
        self.assertEqual(len(at.wiring.caller_chain), 4)
        self.assertEqual(at.wiring.entrypoint, "test_fn")
        self.assertEqual(at.wiring.proof_type, "integration_test")
        # why_causal
        self.assertIn("dispatch_count==0", at.tests[0].causal_proof.why_causal)
        # premortem V2 enums
        from python.proof_graph.enums import WrongImplStatus, DecisionMatch, AssumptionStatus
        self.assertEqual(at.premortem_checks.section5_wrong_impl_blocked, WrongImplStatus.ALL)
        self.assertEqual(at.premortem_checks.section4_decision_match, DecisionMatch.YES)
        self.assertEqual(at.premortem_checks.section2_assumptions, AssumptionStatus.ALL_VALIDATED)
        # trading_halt_trigger
        self.assertFalse(pg.story_verdict.trading_halt_trigger)
        # extra_discovered
        self.assertFalse(at.extra_discovered)
        # meta
        self.assertIn("hints", pg.meta)
        self.assertIn("AT-201", pg.meta["hints"])

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


class TestCrossVersionDenyUnknown(unittest.TestCase):
    """V1 graphs reject V2-only fields; V2 graphs reject truly unknown fields."""

    def test_v1_rejects_meta(self):
        """V1 graph with 'meta' field should be rejected."""
        data = _load("valid_proof_graph.json")
        data["meta"] = {"some": "data"}
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("meta", str(ctx.exception))

    def test_v1_rejects_evidence_entries(self):
        """V1 graph with evidence_entries on enforcement should be rejected."""
        data = _load("valid_proof_graph.json")
        data["ats"][0]["enforcement"]["evidence_entries"] = []
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("evidence_entries", str(ctx.exception))

    def test_v1_rejects_caller_chain(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["wiring"]["caller_chain"] = ["a"]
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("caller_chain", str(ctx.exception))

    def test_v1_rejects_why_causal(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["tests"][0]["causal_proof"]["why_causal"] = "reason"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("why_causal", str(ctx.exception))

    def test_v1_rejects_trading_halt_trigger(self):
        data = _load("valid_proof_graph.json")
        data["story_verdict"]["trading_halt_trigger"] = False
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("trading_halt_trigger", str(ctx.exception))

    def test_v1_rejects_extra_discovered(self):
        data = _load("valid_proof_graph.json")
        data["ats"][0]["extra_discovered"] = False
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("extra_discovered", str(ctx.exception))

    def test_v2_rejects_unknown_top_level(self):
        data = _load("valid_proof_graph_v2.json")
        data["totally_unknown"] = "x"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("totally_unknown", str(ctx.exception))

    def test_v2_rejects_unknown_in_enforcement(self):
        data = _load("valid_proof_graph_v2.json")
        data["ats"][0]["enforcement"]["unknown_field"] = True
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("unknown_field", str(ctx.exception))

    def test_v2_meta_is_opaque(self):
        """Meta dict should NOT be deny-unknown — it's the extensibility point."""
        data = _load("valid_proof_graph_v2.json")
        data["meta"]["arbitrary_key"] = {"nested": True}
        pg = ProofGraph.from_dict(data)
        self.assertIn("arbitrary_key", pg.meta)


class TestV2Defaults(unittest.TestCase):
    """V2 fields default correctly when absent in V2 graph."""

    def test_v2_without_evidence_entries(self):
        data = _load("valid_proof_graph_v2.json")
        del data["ats"][0]["enforcement"]["evidence_entries"]
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.ats[0].enforcement.evidence_entries, [])

    def test_v2_without_caller_chain(self):
        data = _load("valid_proof_graph_v2.json")
        del data["ats"][0]["wiring"]["caller_chain"]
        del data["ats"][0]["wiring"]["entrypoint"]
        del data["ats"][0]["wiring"]["proof_type"]
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.ats[0].wiring.caller_chain, [])
        self.assertEqual(pg.ats[0].wiring.entrypoint, "")

    def test_v2_without_premortem_enums(self):
        data = _load("valid_proof_graph_v2.json")
        del data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"]
        del data["ats"][0]["premortem_checks"]["section4_decision_match"]
        del data["ats"][0]["premortem_checks"]["section2_assumptions"]
        pg = ProofGraph.from_dict(data)
        self.assertIsNone(pg.ats[0].premortem_checks.section5_wrong_impl_blocked)
        self.assertIsNone(pg.ats[0].premortem_checks.section4_decision_match)
        self.assertIsNone(pg.ats[0].premortem_checks.section2_assumptions)

    def test_v2_without_meta(self):
        data = _load("valid_proof_graph_v2.json")
        del data["meta"]
        pg = ProofGraph.from_dict(data)
        self.assertEqual(pg.meta, {})

    def test_v2_without_trading_halt(self):
        data = _load("valid_proof_graph_v2.json")
        del data["story_verdict"]["trading_halt_trigger"]
        pg = ProofGraph.from_dict(data)
        self.assertFalse(pg.story_verdict.trading_halt_trigger)


class TestV2InvalidEnums(unittest.TestCase):
    def test_bad_wrong_impl_status(self):
        data = _load("valid_proof_graph_v2.json")
        data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"] = "INVALID"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("INVALID", str(ctx.exception))

    def test_bad_decision_match(self):
        data = _load("valid_proof_graph_v2.json")
        data["ats"][0]["premortem_checks"]["section4_decision_match"] = "MAYBE"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("MAYBE", str(ctx.exception))

    def test_bad_assumption_status(self):
        data = _load("valid_proof_graph_v2.json")
        data["ats"][0]["premortem_checks"]["section2_assumptions"] = "UNKNOWN"
        with self.assertRaises(ProofGraphParseError) as ctx:
            ProofGraph.from_dict(data)
        self.assertIn("UNKNOWN", str(ctx.exception))


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
