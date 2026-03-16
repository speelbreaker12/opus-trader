from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
HARNESS = REPO_ROOT / "autoresearch" / "skills" / "harness.sh"
EVALUATE_PY = REPO_ROOT / "autoresearch" / "skills" / "evaluate.py"


def _write_text(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")


def _write_json(path: Path, payload: object) -> None:
    _write_text(path, json.dumps(payload, indent=2))


class _TempSkillHarnessRepo:
    def __init__(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        temp_harness = self.root / "autoresearch" / "skills" / "harness.sh"
        temp_harness.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(HARNESS, temp_harness)
        shutil.copy2(EVALUATE_PY, self.root / "autoresearch" / "skills" / "evaluate.py")

        _write_text(self.root / "SKILLS" / "example-skill.md", "# example-skill\n")
        _write_text(
            self.root / "autoresearch" / "skills" / "example-skill" / "fixtures" / "fixture.md",
            "# Fixture\n\nExample input.\n",
        )
        _write_json(
            self.root / "autoresearch" / "skills" / "example-skill" / "eval.json",
            {
                "tests": [
                    {
                        "id": "T1",
                        "fixture": "fixtures/fixture.md",
                        "prompt": "Return the current rendered output.",
                        "assertions": [
                            {
                                "id": "T1-A1",
                                "check": "output contains rendered marker",
                                "rule": {"type": "contains", "value": "rendered"},
                                "expected": True,
                            }
                        ],
                    }
                ]
            },
        )

        self.bin_dir = self.root / "bin"
        self.bin_dir.mkdir(parents=True, exist_ok=True)
        _write_text(
            self.bin_dir / "claude",
            "\n".join(
                [
                    "#!/usr/bin/env python3",
                    "import os",
                    "print(os.environ.get('FAKE_CLAUDE_OUTPUT', 'rendered default'))",
                ]
            )
            + "\n",
        )
        _write_text(
            self.bin_dir / "git",
            "\n".join(
                [
                    "#!/usr/bin/env bash",
                    "set -euo pipefail",
                    'if [[ "${1:-}" == "rev-parse" && "${2:-}" == "--short" && "${3:-}" == "HEAD" ]]; then',
                    "  echo deadbee",
                    "  exit 0",
                    "fi",
                    'echo \"unsupported git args: $*\" >&2',
                    "exit 1",
                ]
            )
            + "\n",
        )
        os.chmod(self.bin_dir / "claude", 0o755)
        os.chmod(self.bin_dir / "git", 0o755)

    def close(self) -> None:
        self.temp_dir.cleanup()

    def run(self, *args: str, fake_output: str) -> subprocess.CompletedProcess[str]:
        env = os.environ.copy()
        env["PATH"] = f"{self.bin_dir}{os.pathsep}{env.get('PATH', '')}"
        env["FAKE_CLAUDE_OUTPUT"] = fake_output
        return subprocess.run(
            ["bash", str(self.root / "autoresearch" / "skills" / "harness.sh"), *args],
            cwd=self.root,
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )


class SkillHarnessBaselineTests(unittest.TestCase):
    def setUp(self) -> None:
        self.repo = _TempSkillHarnessRepo()

    def tearDown(self) -> None:
        self.repo.close()

    def test_baseline_regenerates_outputs_when_rerun_with_same_tag(self) -> None:
        first = self.repo.run("baseline", "example-skill", "--tag", "stable", fake_output="rendered first")
        self.assertEqual(first.returncode, 0, msg=first.stderr)

        output_file = (
            self.repo.root
            / "autoresearch"
            / "skills"
            / "example-skill"
            / "outputs"
            / "baseline-stable"
            / "T1.md"
        )
        self.assertEqual(output_file.read_text(encoding="utf-8").strip(), "rendered first")

        second = self.repo.run("baseline", "example-skill", "--tag", "stable", fake_output="rendered second")
        self.assertEqual(second.returncode, 0, msg=second.stderr)
        self.assertEqual(output_file.read_text(encoding="utf-8").strip(), "rendered second")


if __name__ == "__main__":
    unittest.main()
