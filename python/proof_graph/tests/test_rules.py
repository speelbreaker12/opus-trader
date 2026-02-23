"""Table-driven tests for proof graph validation rules."""
from __future__ import annotations

import json
import unittest
from pathlib import Path

from python.proof_graph.rules import (
    ValidationContext,
    r_001, r_002, r_003, r_004, r_005, r_006, r_007, r_008,
    r_009, r_010, r_011, r_012, r_013, r_014, r_015, r_016,
    r_016b, r_017,
    r_006b, r_018, r_019, r_020, r_021, r_022, r_023, r_024,
    r_024b, r_025, r_026,
    validate,
)
from python.proof_graph.schema import ProofGraph
from python.proof_graph.enums import Severity

FIXTURES = Path(__file__).parent / "fixtures"


def _load(name: str) -> ProofGraph:
    data = json.loads((FIXTURES / name).read_text(encoding="utf-8"))
    return ProofGraph.from_dict(data)


def _ctx(name: str, contract_ats: set[str] | None = None,
         prd_items: dict | None = None) -> ValidationContext:
    return ValidationContext(
        graph=_load(name),
        contract_ats=contract_ats or set(),
        prd_items=prd_items or {},
    )


class TestR001_ReconciledWithBlocking(unittest.TestCase):
    def test_fires_on_blocking_at(self):
        ctx = _ctx("invalid_blocking.json")
        findings = r_001(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-001")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_001(ctx), [])


class TestR002_WeakProofSafetyCritical(unittest.TestCase):
    def test_fires_on_weak_proof(self):
        # Modify valid graph to have WEAK_PROOF
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "HARDENING"
        data["story_verdict"]["hardening_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_002(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-002")

    def test_no_fire_on_non_safety_critical(self):
        ctx = _ctx("invalid_stale_sha.json")  # safety_critical=false
        self.assertEqual(r_002(ctx), [])


class TestR003_WiringContradiction(unittest.TestCase):
    def test_fires_on_contradiction(self):
        data = json.loads(
            (FIXTURES / "invalid_fail_open_risk.json").read_text(encoding="utf-8")
        )
        # Set NOT_WIRED + PROVEN_INTEGRATED
        data["ats"][0]["wiring"]["status"] = "NOT_WIRED"
        data["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_003(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-003")

    def test_no_fire_when_consistent(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_003(ctx), [])


class TestR004_StaleSha(unittest.TestCase):
    def test_fires_on_stale_sha(self):
        ctx = _ctx("invalid_stale_sha.json")
        findings = r_004(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-004")

    def test_clean_on_matching_sha(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_004(ctx), [])


class TestR005_EmptyTargetSlice(unittest.TestCase):
    def test_fires_on_empty_target_slice(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["debt"] = {
            "description": "some debt",
            "target_slice": "",
        }
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_005(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-005")


class TestR006_EmptyEvidence(unittest.TestCase):
    def test_fires_on_empty_evidence(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["enforcement"]["evidence"] = []
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_006(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-006")
        self.assertEqual(findings[0].severity, Severity.HARDENING)


class TestR007_PhantomAt(unittest.TestCase):
    def test_fires_on_phantom_at(self):
        contract_ats = {"AT-201", "AT-905"}
        ctx = _ctx("invalid_phantom_at.json", contract_ats=contract_ats)
        findings = r_007(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-007")
        self.assertIn("AT-99999", findings[0].message)

    def test_no_fire_when_at_exists(self):
        contract_ats = {"AT-201"}
        ctx = _ctx("valid_proof_graph.json", contract_ats=contract_ats)
        self.assertEqual(r_007(ctx), [])

    def test_skipped_when_no_contract_ats(self):
        ctx = _ctx("invalid_phantom_at.json")
        self.assertEqual(r_007(ctx), [])


class TestR008_Placeholders(unittest.TestCase):
    def test_fires_on_fill_me(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["rationale"] = "<FILL>"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        self.assertTrue(any(f.rule == "R-008" for f in findings))

    def test_fires_on_tbd(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["summary"] = "TBD - need to fill in"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        self.assertTrue(any(f.rule == "R-008" for f in findings))


class TestR009_BlockingCount(unittest.TestCase):
    def test_fires_on_mismatch(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["blocking_count"] = 5
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_009(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-009")

    def test_clean_on_match(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_009(ctx), [])


class TestR010_HardeningCount(unittest.TestCase):
    def test_fires_on_mismatch(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["hardening_count"] = 3
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_010(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-010")


class TestR011_DebtRegisterMismatch(unittest.TestCase):
    def test_fires_when_debt_not_registered(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["debt"] = {
            "description": "needs fix",
            "target_slice": "S2",
        }
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_011(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-011")

    def test_clean_when_registered(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["debt"] = {
            "description": "needs fix",
            "target_slice": "S2",
        }
        data["debt_register"] = [{
            "at_id": "AT-201",
            "description": "needs fix",
            "target_slice": "S2",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_011(ctx), [])


class TestR012_NoTests(unittest.TestCase):
    def test_fires_on_enforcement_found_no_tests(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"] = []
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_012(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-012")
        self.assertEqual(findings[0].severity, Severity.HARDENING)


class TestR013_InvalidSha(unittest.TestCase):
    def test_fires_on_short_sha(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["head_sha"] = "abc123"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_013(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-013")

    def test_fires_on_uppercase_sha(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["head_sha"] = "AABBCCDDEE00112233445566778899AABBCCDDEE"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_013(ctx)
        self.assertEqual(len(findings), 1)

    def test_clean_on_valid_sha(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_013(ctx), [])


class TestR014_StoryNotInPrd(unittest.TestCase):
    def test_fires_when_missing(self):
        ctx = _ctx("valid_proof_graph.json", prd_items={"S2-000": {}})
        findings = r_014(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-014")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_when_present(self):
        ctx = _ctx("valid_proof_graph.json", prd_items={"S1-007": {}})
        self.assertEqual(r_014(ctx), [])

    def test_skipped_when_no_prd(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_014(ctx), [])


class TestR015_FailOpenRisk(unittest.TestCase):
    def test_fires_on_fail_open_risk(self):
        ctx = _ctx("invalid_fail_open_risk.json")
        findings = r_015(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-015")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_015(ctx), [])


class TestR016_NoTripTests(unittest.TestCase):
    def test_fires_on_no_trip_tests(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        # Remove TRIP test, keep only NON-TRIP
        data["ats"][0]["tests"] = [data["ats"][0]["tests"][1]]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_016(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-016")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_with_trip_test(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_016(ctx), [])


class TestR016b_SafetyCriticalNoTrip(unittest.TestCase):
    def test_fires_on_safety_critical_no_trip(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        # Remove TRIP test
        data["ats"][0]["tests"] = [data["ats"][0]["tests"][1]]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_016b(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-016b")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_no_fire_on_non_safety_critical(self):
        data = json.loads(
            (FIXTURES / "invalid_stale_sha.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"] = []  # No tests, but not safety_critical
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_016b(ctx), [])


class TestR017_EmptyAts(unittest.TestCase):
    def test_no_fire_on_policy(self):
        ctx = _ctx("minimal_policy_story.json")
        self.assertEqual(r_017(ctx), [])

    def test_fires_on_non_policy_empty_ats(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"] = []
        data["story_verdict"]["blocking_count"] = 0
        data["story_verdict"]["hardening_count"] = 0
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_017(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-017")
        self.assertEqual(findings[0].severity, Severity.HARDENING)


class TestValidateAll(unittest.TestCase):
    def test_valid_graph_no_errors(self):
        """Valid fixture with matching contract ATs → 0 errors."""
        ctx = _ctx(
            "valid_proof_graph.json",
            contract_ats={"AT-201"},
            prd_items={"S1-007": {}},
        )
        findings = validate(ctx)
        errors = [f for f in findings if f.severity == Severity.BLOCKING]
        self.assertEqual(len(errors), 0, f"Unexpected errors: {errors}")

    def test_invalid_blocking_has_errors(self):
        ctx = _ctx(
            "invalid_blocking.json",
            contract_ats={"AT-201"},
            prd_items={"S1-007": {}},
        )
        findings = validate(ctx)
        rules = {f.rule for f in findings if f.severity == Severity.BLOCKING}
        self.assertIn("R-001", rules)


# ── V2 Rule Tests ────────────────────────────────────────────────────


class TestR006b_EmptyEvidenceEntries(unittest.TestCase):
    def test_fires_on_v2_empty_entries(self):
        ctx = _ctx("v2_no_enrichment.json")
        findings = r_006b(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-006b")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_v2_with_entries(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_006b(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_006b(ctx), [])


class TestR018_InvalidCitation(unittest.TestCase):
    def test_fires_on_bad_citation(self):
        ctx = _ctx("v2_bad_citation.json")
        findings = r_018(ctx)
        # empty file, line_start < 1, line_end < line_start, empty symbol
        self.assertTrue(len(findings) >= 4)
        self.assertTrue(all(f.rule == "R-018" for f in findings))
        self.assertTrue(all(f.severity == Severity.BLOCKING for f in findings))

    def test_clean_on_valid_v2(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_018(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_018(ctx), [])


class TestR019_WrongImplSafetyCritical(unittest.TestCase):
    def test_fires_on_wrong_impl(self):
        ctx = _ctx("v2_wrong_impl_safety.json")
        findings = r_019(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-019")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_019(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        ctx = _ctx("v2_no_enrichment.json")  # safety_critical=false
        self.assertEqual(r_019(ctx), [])

    def test_fires_on_v1_too(self):
        """R-019 works on V1 graphs (V1+V2 rule)."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "WRONG_IMPL_UNBLOCKED"
        data["ats"][0]["at_verdict"]["severity"] = "BLOCKING"
        data["story_verdict"]["blocking_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_019(ctx)
        self.assertEqual(len(findings), 1)


class TestR020_EmptyCallerChain(unittest.TestCase):
    def test_fires_on_blank_chain(self):
        ctx = _ctx("v2_missing_caller_chain.json")
        findings = r_020(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-020")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_valid_chain(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_020(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_020(ctx), [])


class TestR021_WrongImplNotBlocked(unittest.TestCase):
    def test_fires_on_none(self):
        ctx = _ctx("v2_premortem_gap.json")
        findings = r_021(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-021")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_all(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_021(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_021(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        ctx = _ctx("v2_no_enrichment.json")  # safety_critical=false
        self.assertEqual(r_021(ctx), [])


class TestR022_DecisionMismatch(unittest.TestCase):
    def test_fires_on_no(self):
        ctx = _ctx("v2_premortem_gap.json")
        findings = r_022(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-022")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_yes(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_022(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_022(ctx), [])


class TestR023_InvalidRef(unittest.TestCase):
    def test_fires_on_invalid_ref(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "INVALID_REF"
        data["ats"][0]["at_verdict"]["severity"] = "BLOCKING"
        data["story_verdict"]["blocking_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_023(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-023")

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_023(ctx), [])

    def test_works_on_v1(self):
        """R-023 is V1+V2 — fires if INVALID_REF appears in V1 graph."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "INVALID_REF"
        data["ats"][0]["at_verdict"]["severity"] = "BLOCKING"
        data["story_verdict"]["blocking_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_023(ctx)
        self.assertEqual(len(findings), 1)


class TestR024_EmptyWhyCausal(unittest.TestCase):
    def test_fires_on_empty_why_causal(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["why_causal"] = ""
        data["ats"][0]["tests"][1]["causal_proof"]["why_causal"] = "  "
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_024(ctx)
        self.assertEqual(len(findings), 2)
        self.assertTrue(all(f.rule == "R-024" for f in findings))

    def test_clean_on_populated(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_024(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_024(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        ctx = _ctx("v2_no_enrichment.json")  # safety_critical=false
        self.assertEqual(r_024(ctx), [])


class TestR024b_NonStandardMechanism(unittest.TestCase):
    def test_fires_on_non_standard(self):
        ctx = _ctx("v2_no_enrichment.json")  # mechanism=dispatch_count_assert
        findings = r_024b(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-024b")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_standard(self):
        ctx = _ctx("valid_proof_graph_v2.json")  # mechanism=dispatch_count
        self.assertEqual(r_024b(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_024b(ctx), [])


class TestR025_TradingHaltConsistency(unittest.TestCase):
    def test_fires_when_recomputed_true_stored_false(self):
        ctx = _ctx("v2_trading_halt.json")
        findings = r_025(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-025")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_info_when_stored_true_recomputed_false(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["trading_halt_trigger"] = True
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_025(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, Severity.INFO)

    def test_clean_when_consistent(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_025(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_025(ctx), [])


class TestR026_NoV2Enrichment(unittest.TestCase):
    def test_fires_on_zero_enrichment(self):
        ctx = _ctx("v2_no_enrichment.json")
        findings = r_026(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-026")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_enriched(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_026(ctx), [])

    def test_clean_on_partial_enrichment(self):
        """Only evidence_entries populated — not zero enrichment."""
        ctx = _ctx("v2_no_enrichment.json")
        # Patch: add one evidence entry to first AT
        at = ctx.graph.ats[0]
        from python.proof_graph.schema import EvidenceEntry, Enforcement
        patched_enforcement = Enforcement(
            status=at.enforcement.status,
            evidence=at.enforcement.evidence,
            evidence_entries=[EvidenceEntry(
                file="build_order_intent.rs",
                line_start=1, line_end=10, symbol="check",
            )],
        )
        import dataclasses
        patched_at = dataclasses.replace(at, enforcement=patched_enforcement)
        patched_graph = dataclasses.replace(
            ctx.graph, ats=[patched_at],
        )
        ctx.graph = patched_graph
        # Should NOT fire — has evidence_entries (partial enrichment)
        self.assertEqual(r_026(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_026(ctx), [])


if __name__ == "__main__":
    unittest.main()
