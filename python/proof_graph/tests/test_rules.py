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
    r_027, r_028, r_029, r_030, r_031, r_032, r_033, r_034,
    r_035, r_036, r_037, r_038, r_039, r_040, r_041,
    r_042, r_043, r_044, r_045, r_046, r_047,
    r_048, r_049, r_050, r_051,
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


# ── R-027..R-037 Tests (validator-audit findings) ─────────────────────


class TestR027_ProvenButFailingTests(unittest.TestCase):
    def test_fires_on_pass_result_false(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["execution"]["pass_result"] = False
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_027(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-027")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("pass_result=false", findings[0].message)

    def test_clean_on_all_passing(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_027(ctx), [])

    def test_no_fire_on_non_proven_verdict(self):
        """WEAK_PROOF + pass_result=false → no R-027 (rule only for PROVEN)."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "HARDENING"
        data["story_verdict"]["hardening_count"] = 1
        data["ats"][0]["tests"][0]["execution"]["pass_result"] = False
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_027(ctx), [])

    def test_fires_on_proven_unit_too(self):
        """R-027 fires on PROVEN_UNIT as well."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "PROVEN_UNIT"
        data["ats"][0]["tests"][0]["execution"]["pass_result"] = False
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_027(ctx)
        self.assertEqual(len(findings), 1)


class TestR028_MechanismAssertMissing(unittest.TestCase):
    def test_fires_on_missing_dispatch_count_assert(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["dispatch_count_assert"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_028(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-028")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("dispatch_count_assert", findings[0].message)

    def test_fires_on_missing_reject_reason_assert(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["mechanism"] = "reject_reason"
        # Remove the existing reject_reason_assert so it's missing
        data["ats"][0]["tests"][0]["causal_proof"].pop("reject_reason_assert", None)
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_028(ctx)
        self.assertTrue(any(
            f.rule == "R-028" and "reject_reason_assert" in f.message
            for f in findings
        ))

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_028(ctx), [])

    def test_no_fire_on_unmapped_mechanism(self):
        """mode_transition is not in _MECHANISM_ASSERT_MAP → no finding."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["mechanism"] = "mode_transition"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = [f for f in r_028(ctx) if f.at_id == "AT-201"]
        self.assertEqual(len(findings), 0)


class TestR029_StoplightRedPlusProven(unittest.TestCase):
    def test_fires_on_red_proven(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["stoplight"] = "RED"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_029(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-029")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_green(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_029(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_029(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        data["ats"][0]["premortem_checks"]["stoplight"] = "RED"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_029(ctx), [])


class TestR030_AssumptionsNone(unittest.TestCase):
    def test_fires_on_none(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["section2_assumptions"] = "NONE"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_030(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-030")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_on_all_validated(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_030(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_030(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        data["ats"][0]["premortem_checks"]["section2_assumptions"] = "NONE"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_030(ctx), [])


class TestR031_ReconciledWithDebtEmpty(unittest.TestCase):
    def test_fires_on_empty_register(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "RECONCILED_WITH_DEBT"
        data["debt_register"] = []
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_031(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-031")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_with_debt_entries(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "RECONCILED_WITH_DEBT"
        data["debt_register"] = [{
            "at_id": "AT-201",
            "description": "needs improvement",
            "target_slice": "S2",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_031(ctx), [])

    def test_no_fire_on_reconciled(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_031(ctx), [])


class TestR032_BlockedHaltButFalse(unittest.TestCase):
    def test_fires_when_halt_false(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "BLOCKED_TRADING_HALT"
        data["story_verdict"]["trading_halt_trigger"] = False
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_032(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-032")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_when_halt_true(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "BLOCKED_TRADING_HALT"
        data["story_verdict"]["trading_halt_trigger"] = True
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_032(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_032(ctx), [])

    def test_no_fire_on_reconciled(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_032(ctx), [])


class TestR033_NotFoundPlusProvenIntegrated(unittest.TestCase):
    def test_fires_on_contradiction(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["enforcement"]["status"] = "NOT_FOUND"
        data["ats"][0]["enforcement"]["evidence"] = []
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_033(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-033")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_clean_when_found(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_033(ctx), [])

    def test_no_fire_on_proven_unit(self):
        """NOT_FOUND + PROVEN_UNIT → no R-033 (only checks PROVEN_INTEGRATED)."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["enforcement"]["status"] = "NOT_FOUND"
        data["ats"][0]["enforcement"]["evidence"] = []
        data["ats"][0]["at_verdict"]["verdict"] = "PROVEN_UNIT"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_033(ctx), [])


class TestR034_LossModeFieldsEmpty(unittest.TestCase):
    def test_fires_on_empty_worst_case(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["loss_mode"]["worst_case"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_034(ctx)
        self.assertTrue(any(f.rule == "R-034" and "worst_case" in f.message for f in findings))
        self.assertTrue(all(f.severity == Severity.HARDENING for f in findings))

    def test_fires_on_all_three_empty(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["loss_mode"]["worst_case"] = "  "
        data["story_meta"]["loss_mode"]["fail_closed_cap"] = ""
        data["story_meta"]["loss_mode"]["drift_metric"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_034(ctx)
        self.assertEqual(len(findings), 3)

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_034(ctx), [])

    def test_exempt_on_policy(self):
        ctx = _ctx("minimal_policy_story.json")
        self.assertEqual(r_034(ctx), [])


class TestR035_UnknownEnforcementPoint(unittest.TestCase):
    def test_fires_on_unknown(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["enforcement_point"] = "MagicGuard"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_035(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-035")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_known(self):
        ctx = _ctx("valid_proof_graph.json")  # DispatcherChokepoint
        self.assertEqual(r_035(ctx), [])


class TestR036_EmptyObservability(unittest.TestCase):
    def test_fires_on_empty_metric(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["observability"]["metric"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_036(ctx)
        self.assertTrue(any(
            f.rule == "R-036" and "metric" in f.message for f in findings
        ))
        self.assertTrue(all(f.severity == Severity.HARDENING for f in findings))

    def test_fires_on_empty_alert(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["observability"]["alert"] = "  "
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_036(ctx)
        self.assertTrue(any(
            f.rule == "R-036" and "alert" in f.message for f in findings
        ))

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_036(ctx), [])


class TestR037_ReconciledUnitOnlyContradiction(unittest.TestCase):
    def test_fires_on_proven_integrated(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "RECONCILED_UNIT_ONLY"
        # AT-201 has PROVEN_INTEGRATED → contradiction
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_037(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-037")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("RECONCILED_UNIT_ONLY", findings[0].message)

    def test_clean_on_proven_unit(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "RECONCILED_UNIT_ONLY"
        data["ats"][0]["at_verdict"]["verdict"] = "PROVEN_UNIT"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_037(ctx), [])

    def test_no_fire_on_reconciled(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_037(ctx), [])


class TestR008_PlaceholderMutants(unittest.TestCase):
    """R-008 extension: placeholders in equivalent_mutants fields."""

    def test_fires_on_tbd_killed_by(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["equivalent_mutants"] = [{
            "mutant_description": "real mutant",
            "killed_by": "TBD",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        self.assertTrue(any(
            f.rule == "R-008" and "killed_by" in f.field_path for f in findings
        ))

    def test_fires_on_fill_me_description(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["equivalent_mutants"] = [{
            "mutant_description": "<FILL>",
            "killed_by": "test_something",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        self.assertTrue(any(
            f.rule == "R-008" and "mutant_description" in f.field_path
            for f in findings
        ))

    def test_clean_on_no_mutants(self):
        ctx = _ctx("valid_proof_graph.json")
        # No mutants → no R-008 from mutants
        findings = r_008(ctx)
        self.assertFalse(any("mutant" in f.field_path for f in findings))


class TestR038_SectionsFilledMinimum(unittest.TestCase):
    def test_fires_on_safety_critical_below_5(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["sections_filled"] = 3
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_038(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-038")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("minimum 5", findings[0].message)

    def test_fires_on_safety_critical_zero(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["sections_filled"] = 0
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_038(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].severity, Severity.BLOCKING)

    def test_fires_on_non_safety_critical_zero(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        data["ats"][0]["premortem_checks"]["sections_filled"] = 0
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_038(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-038")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_safety_critical_5(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["sections_filled"] = 5
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_038(ctx), [])

    def test_clean_on_valid(self):
        """Valid fixture has sections_filled=10 → no finding."""
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_038(ctx), [])

    def test_exempt_on_policy(self):
        ctx = _ctx("minimal_policy_story.json")
        self.assertEqual(r_038(ctx), [])


class TestR039_PartialEnforcementProvenIntegrated(unittest.TestCase):
    def test_fires_on_partial_proven_integrated(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["enforcement"]["status"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_039(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-039")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_found(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_039(ctx), [])

    def test_no_fire_on_partial_weak_proof(self):
        """PARTIAL + WEAK_PROOF → no contradiction."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["enforcement"]["status"] = "PARTIAL"
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "HARDENING"
        data["story_verdict"]["hardening_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_039(ctx), [])


class TestR040_UnmappedMechanismNoAssertions(unittest.TestCase):
    def test_fires_on_mode_transition_no_asserts(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["mechanism"] = "mode_transition"
        data["ats"][0]["tests"][0]["causal_proof"].pop("dispatch_count_assert", None)
        data["ats"][0]["tests"][0]["causal_proof"].pop("reject_reason_assert", None)
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_040(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-040")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_when_has_assert(self):
        """mode_transition with dispatch_count_assert → no finding."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["tests"][0]["causal_proof"]["mechanism"] = "mode_transition"
        # Keep dispatch_count_assert="0" from fixture
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_040(ctx), [])

    def test_no_fire_on_mapped_mechanism(self):
        """dispatch_count is mapped → R-040 skips, R-028 handles it."""
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_040(ctx), [])


class TestR041_WiringFieldsEmpty(unittest.TestCase):
    def test_fires_on_empty_entrypoint(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["wiring"]["entrypoint"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_041(ctx)
        self.assertTrue(any(
            f.rule == "R-041" and "entrypoint" in f.message for f in findings
        ))
        self.assertTrue(all(f.severity == Severity.HARDENING for f in findings))

    def test_fires_on_empty_proof_type(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["wiring"]["proof_type"] = "  "
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_041(ctx)
        self.assertTrue(any(
            f.rule == "R-041" and "proof_type" in f.message for f in findings
        ))

    def test_clean_on_valid(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_041(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_041(ctx), [])

    def test_no_fire_on_non_proven_integrated_wiring(self):
        """PROVEN_UNIT wiring → not checked by R-041."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["wiring"]["status"] = "PROVEN_UNIT"
        data["ats"][0]["wiring"]["entrypoint"] = ""
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_041(ctx), [])


class TestR008_DebtPlaceholders(unittest.TestCase):
    """R-008 extension: placeholders in debt and debt_register fields."""

    def test_fires_on_debt_description_placeholder(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["debt"] = {
            "description": "TODO fix later",
            "target_slice": "S2",
        }
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        self.assertTrue(any(
            f.rule == "R-008" and "debt.description" in f.field_path
            for f in findings
        ))

    def test_fires_on_debt_register_placeholder(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["debt_register"] = [{
            "at_id": "AT-201",
            "description": "<FILL>",
            "target_slice": "TBD",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_008(ctx)
        debt_findings = [f for f in findings if "debt_register" in f.field_path]
        self.assertEqual(len(debt_findings), 2)


class TestR042_WrongImplPartialSafety(unittest.TestCase):
    def test_fires_on_partial(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_042(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-042")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_all(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_042(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_042(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_042(ctx), [])


class TestR043_DecisionMatchPartial(unittest.TestCase):
    def test_fires_on_partial(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["section4_decision_match"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_043(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-043")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_yes(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_043(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_043(ctx), [])


class TestR044_AssumptionsPartialSafety(unittest.TestCase):
    def test_fires_on_partial(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["premortem_checks"]["section2_assumptions"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_044(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-044")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_all_validated(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_044(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_044(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        data["ats"][0]["premortem_checks"]["section2_assumptions"] = "PARTIAL"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_044(ctx), [])


class TestR045_ReconciledNonProvenVerdict(unittest.TestCase):
    def test_fires_on_weak_proof(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "HARDENING"
        data["story_verdict"]["hardening_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_045(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-045")
        self.assertEqual(findings[0].severity, Severity.HARDENING)
        self.assertIn("WEAK_PROOF", findings[0].message)

    def test_fires_on_claimed_not_proven(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["at_verdict"]["verdict"] = "CLAIMED_NOT_PROVEN"
        data["ats"][0]["at_verdict"]["severity"] = "INFO"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_045(ctx)
        self.assertEqual(len(findings), 1)

    def test_clean_on_proven_integrated(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_045(ctx), [])

    def test_no_fire_on_not_reconciled(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_verdict"]["reconciliation_status"] = "NOT_RECONCILED"
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "HARDENING"
        data["story_verdict"]["hardening_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_045(ctx), [])


class TestR046_GeneratedAtFormat(unittest.TestCase):
    def test_fires_on_invalid_format(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "never"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_046(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-046")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_fires_on_date_only(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "2026-02-21"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(len(r_046(ctx)), 1)

    def test_clean_on_valid_offset(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_046(ctx), [])

    def test_clean_on_zulu(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "2026-02-21T10:00:00Z"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_046(ctx), [])


class TestR047_EmptyScopeTouch(unittest.TestCase):
    def test_fires_on_empty(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["scope_touch"] = []
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_047(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-047")
        self.assertEqual(findings[0].severity, Severity.HARDENING)

    def test_clean_on_non_empty(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_047(ctx), [])

    def test_exempt_on_policy(self):
        ctx = _ctx("minimal_policy_story.json")
        self.assertEqual(r_047(ctx), [])


class TestR046_FractionalSeconds(unittest.TestCase):
    """F5-001: ISO-8601 with fractional seconds must pass."""

    def test_clean_on_fractional_seconds(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "2026-02-21T10:00:00.123Z"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_046(ctx), [])

    def test_clean_on_fractional_seconds_with_offset(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "2026-02-21T10:00:00.999999+05:30"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_046(ctx), [])

    def test_fires_on_missing_timezone(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["generated_at"] = "2026-02-21T10:00:00.123"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(len(r_046(ctx)), 1)


class TestR048_OrphanDebtRegister(unittest.TestCase):
    def test_fires_on_orphan(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["debt_register"] = [{
            "at_id": "AT-999",
            "description": "ghost debt",
            "target_slice": "S2",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_048(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-048")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("AT-999", findings[0].message)

    def test_clean_when_at_exists(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["debt_register"] = [{
            "at_id": "AT-201",
            "description": "real debt",
            "target_slice": "S2",
        }]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_048(ctx), [])

    def test_clean_on_empty_register(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_048(ctx), [])

    def test_multiple_orphans(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph.json").read_text(encoding="utf-8")
        )
        data["debt_register"] = [
            {"at_id": "AT-888", "description": "d1", "target_slice": "S1"},
            {"at_id": "AT-999", "description": "d2", "target_slice": "S2"},
        ]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_048(ctx)
        self.assertEqual(len(findings), 2)


class TestR049_ExtraDiscoveredVisibility(unittest.TestCase):
    def test_fires_on_extra_discovered_info_proven(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["extra_discovered"] = True
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_049(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-049")
        self.assertEqual(findings[0].severity, Severity.HARDENING)
        self.assertIn("extra_discovered", findings[0].message)

    def test_clean_when_not_extra_discovered(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_049(ctx), [])

    def test_no_fire_on_blocking_extra_discovered(self):
        """extra_discovered + BLOCKING severity → already visible, no R-049."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["extra_discovered"] = True
        data["ats"][0]["at_verdict"]["severity"] = "BLOCKING"
        data["story_verdict"]["blocking_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_049(ctx), [])

    def test_no_fire_on_non_proven_verdict(self):
        """extra_discovered + WEAK_PROOF → not in _PROVEN_VERDICTS, skip."""
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["ats"][0]["extra_discovered"] = True
        data["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"
        data["ats"][0]["at_verdict"]["severity"] = "INFO"
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_049(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_049(ctx), [])


class TestR050_DuplicateAtId(unittest.TestCase):
    def test_fires_on_duplicate(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        # Duplicate AT-201
        import copy
        dup = copy.deepcopy(data["ats"][0])
        dup["at_verdict"]["verdict"] = "WEAK_PROOF"
        dup["at_verdict"]["severity"] = "HARDENING"
        data["ats"].append(dup)
        data["story_verdict"]["hardening_count"] = 1
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_050(ctx)
        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].rule, "R-050")
        self.assertEqual(findings[0].severity, Severity.BLOCKING)
        self.assertIn("AT-201", findings[0].message)

    def test_clean_on_unique_ids(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_050(ctx), [])

    def test_clean_on_single_at(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_050(ctx), [])

    def test_fires_on_triple_duplicate(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        import copy
        dup1 = copy.deepcopy(data["ats"][0])
        dup2 = copy.deepcopy(data["ats"][0])
        data["ats"].append(dup1)
        data["ats"].append(dup2)
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_050(ctx)
        # Two findings: ats[1] duplicates ats[0], ats[2] duplicates ats[0]
        self.assertEqual(len(findings), 2)


class TestR051_V2SafetyCriticalPremortemFields(unittest.TestCase):
    def test_fires_on_missing_all_three(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        # Remove all V2 premortem fields
        del data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"]
        del data["ats"][0]["premortem_checks"]["section4_decision_match"]
        del data["ats"][0]["premortem_checks"]["section2_assumptions"]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_051(ctx)
        self.assertEqual(len(findings), 3)
        self.assertTrue(all(f.rule == "R-051" for f in findings))
        self.assertTrue(all(f.severity == Severity.BLOCKING for f in findings))
        fields = {f.message.split(": ")[-1].split(" is")[0] for f in findings}
        self.assertEqual(fields, {
            "section5_wrong_impl_blocked",
            "section4_decision_match",
            "section2_assumptions",
        })

    def test_fires_on_missing_one(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        del data["ats"][0]["premortem_checks"]["section2_assumptions"]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        findings = r_051(ctx)
        self.assertEqual(len(findings), 1)
        self.assertIn("section2_assumptions", findings[0].message)

    def test_clean_on_all_present(self):
        ctx = _ctx("valid_proof_graph_v2.json")
        self.assertEqual(r_051(ctx), [])

    def test_skips_v1(self):
        ctx = _ctx("valid_proof_graph.json")
        self.assertEqual(r_051(ctx), [])

    def test_no_fire_when_not_safety_critical(self):
        data = json.loads(
            (FIXTURES / "valid_proof_graph_v2.json").read_text(encoding="utf-8")
        )
        data["story_meta"]["safety_critical"] = False
        del data["ats"][0]["premortem_checks"]["section5_wrong_impl_blocked"]
        del data["ats"][0]["premortem_checks"]["section4_decision_match"]
        del data["ats"][0]["premortem_checks"]["section2_assumptions"]
        pg = ProofGraph.from_dict(data)
        ctx = ValidationContext(graph=pg)
        self.assertEqual(r_051(ctx), [])


if __name__ == "__main__":
    unittest.main()
