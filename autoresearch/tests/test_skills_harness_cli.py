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


class SkillHarnessCliTests(unittest.TestCase):
    def test_baseline_regenerates_outputs_when_reusing_same_tag(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            harness = root / "autoresearch" / "skills" / "harness.sh"
            harness.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(HARNESS, harness)

            skill_dir = root / "autoresearch" / "skills" / "demo"
            (skill_dir / "fixtures").mkdir(parents=True, exist_ok=True)
            (skill_dir / "outputs").mkdir(parents=True, exist_ok=True)
            (root / "SKILLS").mkdir(parents=True, exist_ok=True)
            (root / "SKILLS" / "demo.md").write_text("# Demo skill\n", encoding="utf-8")
            (skill_dir / "fixtures" / "example.diff").write_text(
                "diff --git a/example.txt b/example.txt\n",
                encoding="utf-8",
            )
            (skill_dir / "eval.json").write_text(
                json.dumps(
                    {
                        "skill": "SKILLS/demo.md",
                        "description": "demo",
                        "total_assertions": 0,
                        "tests": [
                            {
                                "id": "T1",
                                "fixture": "fixtures/example.diff",
                                "prompt": "Review this diff.",
                                "assertions": [],
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            (root / "autoresearch" / "skills" / "evaluate.py").write_text(
                "import json\nprint(json.dumps({'score': 1.0, 'passed': 1, 'total': 1}))\n",
                encoding="utf-8",
            )

            bin_dir = root / "bin"
            bin_dir.mkdir(parents=True, exist_ok=True)
            claude = bin_dir / "claude"
            claude.write_text(
                "\n".join(
                    [
                        "#!/usr/bin/env bash",
                        "set -euo pipefail",
                        "count_file=\"$(dirname \"$0\")/../claude_count.txt\"",
                        "count=0",
                        "[[ -f \"$count_file\" ]] && count=\"$(cat \"$count_file\")\"",
                        "count=$((count + 1))",
                        "printf '%s' \"$count\" > \"$count_file\"",
                        "printf 'generated-%s\\n' \"$count\"",
                    ]
                )
                + "\n",
                encoding="utf-8",
            )
            claude.chmod(0o755)

            subprocess.run(["git", "init"], cwd=root, check=True, capture_output=True, text=True)
            subprocess.run(
                ["git", "config", "user.email", "test@example.com"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(
                ["git", "config", "user.name", "Test User"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )
            subprocess.run(["git", "add", "."], cwd=root, check=True, capture_output=True, text=True)
            subprocess.run(
                ["git", "commit", "-m", "init"],
                cwd=root,
                check=True,
                capture_output=True,
                text=True,
            )

            env = os.environ.copy()
            env["PATH"] = f"{bin_dir}:{env['PATH']}"
            command = ["bash", str(harness), "baseline", "demo", "--tag", "fixed"]

            first = subprocess.run(
                command,
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(first.returncode, 0, msg=first.stderr)

            output_file = skill_dir / "outputs" / "baseline-fixed" / "T1.md"
            self.assertEqual(output_file.read_text(encoding="utf-8"), "generated-1\n")

            second = subprocess.run(
                command,
                cwd=root,
                env=env,
                capture_output=True,
                text=True,
                check=False,
            )
            self.assertEqual(second.returncode, 0, msg=second.stderr)
            self.assertEqual(output_file.read_text(encoding="utf-8"), "generated-2\n")


if __name__ == "__main__":
    unittest.main()
