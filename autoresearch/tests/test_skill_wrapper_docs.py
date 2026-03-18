from __future__ import annotations

import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]

REVIEW_STACK_WRAPPER = REPO_ROOT / ".claude" / "skills" / "review-stack" / "SKILL.md"
PREMORTEM_WRAPPER = REPO_ROOT / ".claude" / "skills" / "premortem" / "SKILL.md"
DESIGN_DOC = (
    REPO_ROOT
    / "docs"
    / "superpowers"
    / "specs"
    / "2026-03-14-skills2-review-stack-premortem-design.md"
)
PLAN_DOC = (
    REPO_ROOT
    / "docs"
    / "superpowers"
    / "plans"
    / "2026-03-14-skills2-review-stack-premortem.md"
)
EVALUATE_PY = REPO_ROOT / "autoresearch" / "skills" / "evaluate.py"
CONTRACT_HARNESS_CLI_TEST = (
    REPO_ROOT / "autoresearch" / "tests" / "test_contract_harness_cli.py"
)

REVIEW_STACK_COMMAND = '!`cat "$(git rev-parse --show-toplevel)/SKILLS/review-stack.md"`'
PREMORTEM_COMMAND = '!`cat "$(git rev-parse --show-toplevel)/SKILLS/premortem.md"`'
HOST_LOCAL_PATH = "/Users/admin/Desktop/opus-trader"


class SkillWrapperDocsTests(unittest.TestCase):
    def test_wrappers_resolve_from_git_root_and_fail_closed(self) -> None:
        review_stack = REVIEW_STACK_WRAPPER.read_text(encoding="utf-8")
        premortem = PREMORTEM_WRAPPER.read_text(encoding="utf-8")

        self.assertIn(REVIEW_STACK_COMMAND, review_stack)
        self.assertIn(PREMORTEM_COMMAND, premortem)
        self.assertNotIn("|| echo", review_stack)
        self.assertNotIn("|| echo", premortem)

    def test_docs_match_wrapper_commands_and_avoid_host_local_paths(self) -> None:
        design_doc = DESIGN_DOC.read_text(encoding="utf-8")
        plan_doc = PLAN_DOC.read_text(encoding="utf-8")

        self.assertNotIn(HOST_LOCAL_PATH, design_doc)
        self.assertNotIn(HOST_LOCAL_PATH, plan_doc)

        for content in (design_doc, plan_doc):
            self.assertIn(REVIEW_STACK_COMMAND, content)
            self.assertIn(PREMORTEM_COMMAND, content)

    def test_reviewed_python_files_do_not_keep_flagged_unused_imports(self) -> None:
        evaluate_py = EVALUATE_PY.read_text(encoding="utf-8")
        harness_cli_test = CONTRACT_HARNESS_CLI_TEST.read_text(encoding="utf-8")

        self.assertNotIn("\nimport os\n", evaluate_py)
        self.assertNotIn("\nfrom typing import Any\n", evaluate_py)
        self.assertNotIn("\nimport sys\n", harness_cli_test)


if __name__ == "__main__":
    unittest.main()
