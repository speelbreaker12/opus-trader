#!/usr/bin/env python3
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check_lag_ids.py"


class CheckLagIdsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_checker(self, path: Path) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--file", str(path)],
            cwd=self.root,
            capture_output=True,
            text=True,
            env={**os.environ, "PYTHONUTF8": "1"},
        )

    def test_passes_when_lag_ids_are_unique(self) -> None:
        doc = self.root / "lag.md"
        doc.write_text(
            textwrap.dedent(
                """\
                # Lag
                ## LAG-001 — A
                Body
                ## LAG-002 — B
                Body
                ## LAG-010 — C
                """
            ),
            encoding="utf-8",
        )

        proc = self.run_checker(doc)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("OK: no duplicate LAG IDs found", proc.stdout)

    def test_fails_when_lag_id_is_duplicated(self) -> None:
        doc = self.root / "lag.md"
        doc.write_text(
            textwrap.dedent(
                """\
                # Lag
                ## LAG-003 — first
                Text
                ## LAG-004 — other
                Text
                ## LAG-003 — second
                """
            ),
            encoding="utf-8",
        )

        proc = self.run_checker(doc)
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL: duplicate LAG IDs found", proc.stderr)
        self.assertIn("LAG-003: lines 2, 6", proc.stderr)

    def test_ignores_non_heading_lag_mentions(self) -> None:
        doc = self.root / "lag.md"
        doc.write_text(
            textwrap.dedent(
                """\
                # Lag
                Mention LAG-003 in plain text.
                - Backlog note: LAG-003 remains open.
                ## LAG-003 — only heading occurrence
                """
            ),
            encoding="utf-8",
        )

        proc = self.run_checker(doc)
        self.assertEqual(proc.returncode, 0, proc.stderr)
        self.assertIn("OK: no duplicate LAG IDs found", proc.stdout)

    def test_missing_file_is_setup_error(self) -> None:
        proc = self.run_checker(self.root / "missing.md")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)


if __name__ == "__main__":
    unittest.main()
