"""Tests for aggregate.py — fail-closed reviewer merge."""
from __future__ import annotations

import json
import unittest
from copy import deepcopy
from pathlib import Path

from python.proof_graph.aggregate import (
    DEFERRED_VERDICT,
    VERDICT_STRICTNESS,
    _strictest_verdict,
    _verdict_rank,
    aggregate,
)

FIXTURES = Path(__file__).parent / "fixtures"


def _load_fixture(name: str) -> dict:
    return json.loads((FIXTURES / name).read_text(encoding="utf-8"))


class TestVerdictStrictness(unittest.TestCase):
    def test_ordering(self):
        """Strictness increases: PROVEN_INTEGRATED < ... < MISSING."""
        ordered = sorted(VERDICT_STRICTNESS.keys(), key=_verdict_rank)
        self.assertEqual(ordered[0], "PROVEN_INTEGRATED")
        self.assertEqual(ordered[-1], "MISSING")

    def test_unknown_verdict_is_strictest(self):
        """Unknown verdict gets rank 9 (stricter than MISSING=8)."""
        self.assertGreater(_verdict_rank("TOTALLY_UNKNOWN"), _verdict_rank("MISSING"))

    def test_deferred_excluded(self):
        """DEFERRED is excluded from strictness comparison."""
        result = _strictest_verdict(["PROVEN_INTEGRATED", "DEFERRED"])
        self.assertEqual(result, "PROVEN_INTEGRATED")

    def test_all_deferred(self):
        result = _strictest_verdict(["DEFERRED", "DEFERRED"])
        self.assertEqual(result, "DEFERRED")

    def test_strictest_wins(self):
        result = _strictest_verdict(["PROVEN_INTEGRATED", "WEAK_PROOF", "FAIL_OPEN_RISK"])
        self.assertEqual(result, "FAIL_OPEN_RISK")


class TestAggregate(unittest.TestCase):
    def _base(self) -> dict:
        return _load_fixture("v2_with_conflicts.json")

    def test_strictest_verdict_wins(self):
        """When reviewers disagree, strictest verdict wins."""
        base = self._base()
        r1 = deepcopy(base)
        r2 = deepcopy(base)
        # Reviewer 1: AT-201 = PROVEN_INTEGRATED (rank 0)
        r1["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"
        # Reviewer 2: AT-201 = WEAK_PROOF (rank 2)
        r2["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"

        merged = aggregate(base, [r1, r2], review_labels=["codex", "opus"])

        at201 = next(at for at in merged["ats"] if at["at_id"] == "AT-201")
        self.assertEqual(at201["at_verdict"]["verdict"], "WEAK_PROOF")

    def test_conflict_recorded(self):
        """Disagreements are recorded in meta.conflicts."""
        base = self._base()
        r1 = deepcopy(base)
        r2 = deepcopy(base)
        r1["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"
        r2["ats"][0]["at_verdict"]["verdict"] = "WEAK_PROOF"

        merged = aggregate(base, [r1, r2], review_labels=["codex", "opus"])

        self.assertIn("conflicts", merged["meta"])
        self.assertIn("AT-201", merged["meta"]["conflicts"])
        conflict = merged["meta"]["conflicts"]["AT-201"]
        self.assertEqual(conflict["type"], "disagreement")
        self.assertEqual(conflict["selected"], "WEAK_PROOF")

    def test_review_sources_populated(self):
        base = self._base()
        r1 = deepcopy(base)
        merged = aggregate(base, [r1], review_labels=["codex"])
        self.assertEqual(merged["meta"]["review_sources"], ["codex"])

    def test_all_deferred_keeps_base(self):
        """When all reviewers DEFERRED, keep base verdict + record conflict."""
        base = self._base()
        r1 = deepcopy(base)
        r1["ats"][0]["at_verdict"]["verdict"] = "DEFERRED"
        r2 = deepcopy(base)
        r2["ats"][0]["at_verdict"]["verdict"] = "DEFERRED"

        merged = aggregate(base, [r1, r2], review_labels=["codex", "opus"])

        at201 = next(at for at in merged["ats"] if at["at_id"] == "AT-201")
        # Base verdict preserved
        self.assertEqual(at201["at_verdict"]["verdict"], "PROVEN_INTEGRATED")
        # Conflict recorded
        self.assertIn("AT-201", merged["meta"]["conflicts"])
        self.assertEqual(merged["meta"]["conflicts"]["AT-201"]["type"], "all_deferred")

    def test_at_in_reviewer_not_base(self):
        """AT in reviewer but not base → added to merged."""
        base = self._base()
        r1 = deepcopy(base)
        # Add AT-300 only to reviewer
        new_at = deepcopy(r1["ats"][0])
        new_at["at_id"] = "AT-300"
        new_at["at_verdict"]["verdict"] = "WEAK_PROOF"
        r1["ats"].append(new_at)

        merged = aggregate(base, [r1], review_labels=["codex"])

        at_ids = [at["at_id"] for at in merged["ats"]]
        self.assertIn("AT-300", at_ids)

    def test_at_in_base_not_reviewer(self):
        """AT in base but not reviewer → keep base verdict."""
        base = self._base()
        r1 = deepcopy(base)
        # Remove AT-202 from reviewer
        r1["ats"] = [at for at in r1["ats"] if at["at_id"] != "AT-202"]

        merged = aggregate(base, [r1], review_labels=["codex"])

        at_ids = [at["at_id"] for at in merged["ats"]]
        self.assertIn("AT-202", at_ids)

    def test_trading_halt_recomputed(self):
        """Trading halt is recomputed from merged data."""
        base = self._base()
        # Make halt condition true: safety_critical + HIGH + FAIL_OPEN_RISK
        base["story_meta"]["loss_mode"]["level"] = "HIGH"
        r1 = deepcopy(base)
        r1["ats"][0]["at_verdict"]["verdict"] = "FAIL_OPEN_RISK"

        merged = aggregate(base, [r1], review_labels=["codex"])

        self.assertTrue(merged["story_verdict"]["trading_halt_trigger"])

    def test_no_halt_when_condition_not_met(self):
        """No halt when loss_mode is MED (not HIGH/CRITICAL)."""
        base = self._base()
        r1 = deepcopy(base)
        r1["ats"][0]["at_verdict"]["verdict"] = "FAIL_OPEN_RISK"

        merged = aggregate(base, [r1], review_labels=["codex"])

        # MED loss_mode → no halt
        self.assertFalse(merged["story_verdict"]["trading_halt_trigger"])

    def test_unknown_verdict_fail_closed(self):
        """Unknown verdict value treated as rank 9 (stricter than MISSING)."""
        base = self._base()
        r1 = deepcopy(base)
        r1["ats"][0]["at_verdict"]["verdict"] = "TOTALLY_BOGUS"

        merged = aggregate(base, [r1], review_labels=["codex"])

        at201 = next(at for at in merged["ats"] if at["at_id"] == "AT-201")
        self.assertEqual(at201["at_verdict"]["verdict"], "TOTALLY_BOGUS")

    def test_meta_hints_preserved(self):
        """Base meta.hints are preserved in merged output."""
        base = self._base()
        r1 = deepcopy(base)
        merged = aggregate(base, [r1], review_labels=["codex"])
        self.assertIn("hints", merged["meta"])
        self.assertIn("AT-201", merged["meta"]["hints"])

    def test_no_conflicts_when_agreement(self):
        """When all reviewers agree, no conflicts recorded."""
        base = self._base()
        r1 = deepcopy(base)
        r2 = deepcopy(base)
        # Both reviewers agree
        r1["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"
        r2["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"

        merged = aggregate(base, [r1, r2], review_labels=["codex", "opus"])

        # No conflict for AT-201 (agreement)
        conflicts = merged["meta"].get("conflicts", {})
        self.assertNotIn("AT-201", conflicts)

    def test_severity_updated_with_stricter_verdict(self):
        """When a reviewer provides a stricter verdict, severity is adopted too."""
        base = self._base()
        r1 = deepcopy(base)
        # Base: AT-201 = PROVEN_INTEGRATED / INFO
        base["ats"][0]["at_verdict"]["verdict"] = "PROVEN_INTEGRATED"
        base["ats"][0]["at_verdict"]["severity"] = "INFO"
        # Reviewer: AT-201 = MISSING / BLOCKING
        r1["ats"][0]["at_verdict"]["verdict"] = "MISSING"
        r1["ats"][0]["at_verdict"]["severity"] = "BLOCKING"

        merged = aggregate(base, [r1], review_labels=["codex"])

        at201 = next(at for at in merged["ats"] if at["at_id"] == "AT-201")
        self.assertEqual(at201["at_verdict"]["verdict"], "MISSING")
        self.assertEqual(at201["at_verdict"]["severity"], "BLOCKING")
        # Blocking count should reflect the updated severity
        self.assertGreaterEqual(merged["story_verdict"]["blocking_count"], 1)

    def test_label_review_count_mismatch_raises(self):
        """Mismatched label/review counts raise ValueError (fail-fast)."""
        base = self._base()
        r1 = deepcopy(base)
        with self.assertRaises(ValueError):
            aggregate(base, [r1], review_labels=["codex", "opus"])

    def test_default_labels_generated(self):
        """When review_labels is None, auto-generated labels are used."""
        base = self._base()
        r1 = deepcopy(base)
        r2 = deepcopy(base)
        merged = aggregate(base, [r1, r2])
        self.assertEqual(merged["meta"]["review_sources"], ["reviewer_0", "reviewer_1"])


if __name__ == "__main__":
    unittest.main()
