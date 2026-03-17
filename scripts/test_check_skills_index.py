from __future__ import annotations

import subprocess
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]


class CheckSkillsIndexTests(unittest.TestCase):
    def test_skills_index_validator_succeeds(self) -> None:
        result = subprocess.run(
            ["python3", str(REPO_ROOT / "scripts" / "check_skills_index.py")],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(result.returncode, 0, msg=result.stderr or result.stdout)
        self.assertIn("OK:", result.stdout)


if __name__ == "__main__":
    unittest.main()
