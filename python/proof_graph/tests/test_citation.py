"""Tests for citation.py — file existence and symbol checker."""
from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from python.proof_graph.citation import check_citation
from python.proof_graph.schema import EvidenceEntry


class TestCheckCitation(unittest.TestCase):
    def setUp(self):
        self.tmpdir = tempfile.mkdtemp()
        self.repo = Path(self.tmpdir)
        # Create a test file
        src = self.repo / "src" / "gate.rs"
        src.parent.mkdir(parents=True, exist_ok=True)
        src.write_text(
            "fn check_guard() {\n"
            "    if stale { return Err(Stale) }\n"
            "    Ok(())\n"
            "}\n",
            encoding="utf-8",
        )

    def test_file_not_found(self):
        entry = EvidenceEntry(
            file="nonexistent.rs", line_start=1, line_end=1, symbol="foo"
        )
        result = check_citation(entry, self.repo)
        self.assertFalse(result.valid)
        self.assertFalse(result.file_exists)
        self.assertIn("not found", result.message)

    def test_valid_citation(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=1, line_end=3, symbol="check_guard"
        )
        result = check_citation(entry, self.repo)
        self.assertTrue(result.valid)
        self.assertTrue(result.file_exists)
        self.assertTrue(result.line_range_valid)
        self.assertIsNone(result.symbol_found)

    def test_line_out_of_range(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=1, line_end=100, symbol="check_guard"
        )
        result = check_citation(entry, self.repo)
        self.assertFalse(result.valid)
        self.assertTrue(result.file_exists)
        self.assertFalse(result.line_range_valid)

    def test_invalid_line_range(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=3, line_end=1, symbol="check_guard"
        )
        result = check_citation(entry, self.repo)
        self.assertFalse(result.valid)
        self.assertFalse(result.line_range_valid)

    def test_line_start_zero(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=0, line_end=1, symbol="check_guard"
        )
        result = check_citation(entry, self.repo)
        self.assertFalse(result.valid)
        self.assertFalse(result.line_range_valid)

    def test_symbol_found(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=1, line_end=2, symbol="check_guard"
        )
        result = check_citation(entry, self.repo, check_symbol=True)
        self.assertTrue(result.valid)
        self.assertTrue(result.symbol_found)

    def test_symbol_not_found(self):
        entry = EvidenceEntry(
            file="src/gate.rs", line_start=2, line_end=3, symbol="nonexistent_fn"
        )
        result = check_citation(entry, self.repo, check_symbol=True)
        self.assertFalse(result.valid)
        self.assertFalse(result.symbol_found)
        self.assertIn("not found", result.message)


if __name__ == "__main__":
    unittest.main()
