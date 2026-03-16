from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
CONTRACT_TEMPLATE = REPO_ROOT / "autoresearch" / "contract"
RENDER_REVIEW = CONTRACT_TEMPLATE / "render_review.py"


def _write_json(path: Path, payload: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def _extract_hash(markdown: str, field: str) -> str:
    prefix = f"- {field}: `"
    for line in markdown.splitlines():
        if line.startswith(prefix) and line.endswith("`"):
            return line[len(prefix):-1]
    raise AssertionError(f"missing {field} in markdown")


class ContractRenderReviewTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        shutil.copytree(CONTRACT_TEMPLATE, self.root / "autoresearch" / "contract")
        self.phase2 = self.root / "autoresearch" / "contract" / "phase2"

    def tearDown(self) -> None:
        self.temp_dir.cleanup()

    def _render(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            [sys.executable, str(RENDER_REVIEW), "--root", str(self.root), *args],
            cwd=REPO_ROOT,
            capture_output=True,
            text=True,
            check=False,
        )

    def _seed_run(self, diff_preview_two: str | None = None, run_id: str = "run-1") -> None:
        proposals = {
            "generated_at": "2026-03-14T20:00:00Z",
            "validator_version": "test",
            "proposals": [
                {
                    "proposal_id": "P-001",
                    "source_finding": "F-001",
                    "source_finding_category": "cross_ref_broken",
                    "section": "§1",
                    "change_type": "mechanical",
                    "rationale": "Repair broken AT reference.",
                    "status": "proposed",
                    "dedupe_key": "fixture-1/p-001",
                    "mechanical_ok": True,
                    "mechanical_details": "Exact AT token replacement.",
                    "replace_span": {
                        "start_line": 10,
                        "end_line": 10,
                        "old_text": "AT-999 is referenced here",
                        "new_text": "AT-101 is referenced here"
                    },
                    "diff_preview": "\n".join([
                        "diff --git a/specs/CONTRACT.md b/specs/CONTRACT.md",
                        "--- a/specs/CONTRACT.md",
                        "+++ b/specs/CONTRACT.md",
                        "@@ -10,1 +10,1 @@",
                        "-AT-999 is referenced here",
                        "+AT-101 is referenced here",
                    ]),
                }
            ],
        }
        proposals_two = {
            "generated_at": "2026-03-14T20:00:01Z",
            "validator_version": "test",
            "proposals": [
                {
                    "proposal_id": "P-002",
                    "source_finding": "F-002",
                    "source_finding_category": "missing_fail_closed",
                    "section": "§2.2",
                    "change_type": "new_requirement",
                    "rationale": "Add explicit fail-closed clause.",
                    "status": "proposed",
                    "dedupe_key": "fixture-2/p-002",
                    "proposed_text": "PolicyGuard MUST reject when evidence_chain_score is missing.",
                    "diff_preview": diff_preview_two
                    or "\n".join([
                        "diff --git a/specs/CONTRACT.md b/specs/CONTRACT.md",
                        "--- a/specs/CONTRACT.md",
                        "+++ b/specs/CONTRACT.md",
                        "@@ -20,0 +21,1 @@",
                        "+PolicyGuard MUST reject when evidence_chain_score is missing.",
                    ]),
                }
            ],
        }
        _write_json(
            self.phase2 / "outputs" / run_id / "fixture-1" / "proposals.json",
            proposals,
        )
        _write_json(
            self.phase2 / "outputs" / run_id / "fixture-2" / "proposals.json",
            proposals_two,
        )
        _write_json(
            self.phase2 / "proposals_index.json",
            [
                {
                    "run_id": run_id,
                    "timestamp": "2026-03-14T20:00:02Z",
                    "contract_file_hash": "a" * 64,
                    "status": "pending",
                    "proposal_count": 2,
                    "accepted_count": 0,
                    "file_path": f"autoresearch/contract/phase2/proposals/CONTRACT_PROPOSALS_{run_id}.md",
                }
            ],
        )

    def test_render_review_and_accepted_only_patch(self) -> None:
        self._seed_run()

        initial = self._render("--run-id", "run-1")
        self.assertEqual(initial.returncode, 0, msg=initial.stderr)

        review_md = (self.phase2 / "review" / "CONTRACT_REVIEW_run-1.md").read_text(encoding="utf-8")
        self.assertIn("P-001", review_md)
        self.assertIn("P-002", review_md)

        proposals_hash = _extract_hash(review_md, "proposals_file_hash")
        decisions = {
            "run_id": "run-1",
            "reviewed_at": "2026-03-14T21:00:00Z",
            "contract_file_hash": "a" * 64,
            "proposals_file_hash": proposals_hash,
            "decisions": [
                {
                    "proposal_id": "P-001",
                    "decision": "accepted",
                    "reviewer": "tester",
                    "reason_code": "SAFE_MECHANICAL",
                },
                {
                    "proposal_id": "P-002",
                    "decision": "rejected",
                    "reviewer": "tester",
                    "reason_code": "OUT_OF_SCOPE",
                },
            ],
        }
        review_json = self.phase2 / "review" / "REVIEW_DECISIONS_run-1.json"
        _write_json(review_json, decisions)

        accepted = self._render("--run-id", "run-1", "--accepted-only", "--review", str(review_json))
        self.assertEqual(accepted.returncode, 0, msg=accepted.stderr)

        patch_text = (self.phase2 / "review" / "CONTRACT_PATCH_run-1.patch").read_text(encoding="utf-8")
        self.assertIn("AT-101 is referenced here", patch_text)
        self.assertNotIn("evidence_chain_score is missing", patch_text)

    def test_render_review_fails_closed_on_missing_decision(self) -> None:
        self._seed_run()

        initial = self._render("--run-id", "run-1")
        self.assertEqual(initial.returncode, 0, msg=initial.stderr)

        review_md = (self.phase2 / "review" / "CONTRACT_REVIEW_run-1.md").read_text(encoding="utf-8")
        proposals_hash = _extract_hash(review_md, "proposals_file_hash")
        decisions = {
            "run_id": "run-1",
            "reviewed_at": "2026-03-14T21:00:00Z",
            "contract_file_hash": "a" * 64,
            "proposals_file_hash": proposals_hash,
            "decisions": [
                {
                    "proposal_id": "P-001",
                    "decision": "accepted",
                    "reviewer": "tester",
                    "reason_code": "SAFE_MECHANICAL",
                }
            ],
        }
        review_json = self.phase2 / "review" / "REVIEW_DECISIONS_run-1.json"
        _write_json(review_json, decisions)

        accepted = self._render("--run-id", "run-1", "--accepted-only", "--review", str(review_json))
        self.assertNotEqual(accepted.returncode, 0)
        self.assertIn("omitted proposal ids: P-002", accepted.stderr)

    def test_render_review_fails_closed_on_non_patch_diff_preview(self) -> None:
        self._seed_run(diff_preview_two="not a patch")

        initial = self._render("--run-id", "run-1")
        self.assertEqual(initial.returncode, 0, msg=initial.stderr)

        review_md = (self.phase2 / "review" / "CONTRACT_REVIEW_run-1.md").read_text(encoding="utf-8")
        proposals_hash = _extract_hash(review_md, "proposals_file_hash")
        decisions = {
            "run_id": "run-1",
            "reviewed_at": "2026-03-14T21:00:00Z",
            "contract_file_hash": "a" * 64,
            "proposals_file_hash": proposals_hash,
            "decisions": [
                {
                    "proposal_id": "P-001",
                    "decision": "rejected",
                    "reviewer": "tester",
                    "reason_code": "OUT_OF_SCOPE",
                },
                {
                    "proposal_id": "P-002",
                    "decision": "accepted",
                    "reviewer": "tester",
                    "reason_code": "APPROVED",
                },
            ],
        }
        review_json = self.phase2 / "review" / "REVIEW_DECISIONS_run-1.json"
        _write_json(review_json, decisions)

        accepted = self._render("--run-id", "run-1", "--accepted-only", "--review", str(review_json))
        self.assertNotEqual(accepted.returncode, 0)
        self.assertIn("not a git-applicable patch fragment", accepted.stderr)

    def test_render_review_fails_closed_without_index_hash_provenance(self) -> None:
        self._seed_run()
        _write_json(self.phase2 / "proposals_index.json", [])

        result = self._render("--run-id", "run-1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing proposals_index entry for run_id=run-1", result.stderr)

    def test_render_review_rejects_non_contract_patch_target(self) -> None:
        other_patch = "\n".join([
            "diff --git a/plans/progress.txt b/plans/progress.txt",
            "--- a/plans/progress.txt",
            "+++ b/plans/progress.txt",
            "@@ -1,1 +1,1 @@",
            "-old",
            "+new",
        ])
        self._seed_run(diff_preview_two=other_patch)

        initial = self._render("--run-id", "run-1")
        self.assertEqual(initial.returncode, 0, msg=initial.stderr)

        review_md = (self.phase2 / "review" / "CONTRACT_REVIEW_run-1.md").read_text(encoding="utf-8")
        proposals_hash = _extract_hash(review_md, "proposals_file_hash")
        decisions = {
            "run_id": "run-1",
            "reviewed_at": "2026-03-14T21:00:00Z",
            "contract_file_hash": "a" * 64,
            "proposals_file_hash": proposals_hash,
            "decisions": [
                {
                    "proposal_id": "P-001",
                    "decision": "rejected",
                    "reviewer": "tester",
                    "reason_code": "OUT_OF_SCOPE",
                },
                {
                    "proposal_id": "P-002",
                    "decision": "accepted",
                    "reviewer": "tester",
                    "reason_code": "APPROVED",
                },
            ],
        }
        review_json = self.phase2 / "review" / "REVIEW_DECISIONS_run-1.json"
        _write_json(review_json, decisions)

        accepted = self._render("--run-id", "run-1", "--accepted-only", "--review", str(review_json))
        self.assertNotEqual(accepted.returncode, 0)
        self.assertIn("must target only specs/CONTRACT.md", accepted.stderr)

    def test_render_review_discovers_latest_run_by_mtime(self) -> None:
        self._seed_run(run_id="run-10")
        stale_run = self.phase2 / "outputs" / "run-9"
        stale_run.mkdir(parents=True)
        os.utime(stale_run, (1_700_000_000, 1_700_000_000))
        os.utime(self.phase2 / "outputs" / "run-10", (1_800_000_000, 1_800_000_000))

        result = self._render()
        self.assertEqual(result.returncode, 0, msg=result.stderr)
        self.assertTrue((self.phase2 / "review" / "CONTRACT_REVIEW_run-10.md").exists())
        self.assertFalse((self.phase2 / "review" / "CONTRACT_REVIEW_run-9.md").exists())

    def test_render_review_fails_closed_on_git_patch_without_unified_headers(self) -> None:
        partial_patch = "\n".join([
            "diff --git a/specs/CONTRACT.md b/specs/CONTRACT.md",
            "@@ -20,0 +21,1 @@",
            "+PolicyGuard MUST reject when evidence_chain_score is missing.",
        ])
        self._seed_run(diff_preview_two=partial_patch)

        initial = self._render("--run-id", "run-1")
        self.assertEqual(initial.returncode, 0, msg=initial.stderr)

        review_md = (self.phase2 / "review" / "CONTRACT_REVIEW_run-1.md").read_text(encoding="utf-8")
        proposals_hash = _extract_hash(review_md, "proposals_file_hash")
        decisions = {
            "run_id": "run-1",
            "reviewed_at": "2026-03-14T21:00:00Z",
            "contract_file_hash": "a" * 64,
            "proposals_file_hash": proposals_hash,
            "decisions": [
                {
                    "proposal_id": "P-001",
                    "decision": "rejected",
                    "reviewer": "tester",
                    "reason_code": "OUT_OF_SCOPE",
                },
                {
                    "proposal_id": "P-002",
                    "decision": "accepted",
                    "reviewer": "tester",
                    "reason_code": "APPROVED",
                },
            ],
        }
        review_json = self.phase2 / "review" / "REVIEW_DECISIONS_run-1.json"
        _write_json(review_json, decisions)

        accepted = self._render("--run-id", "run-1", "--accepted-only", "--review", str(review_json))
        self.assertNotEqual(accepted.returncode, 0)
        self.assertIn("must include both ---/+++ unified diff headers", accepted.stderr)


if __name__ == "__main__":
    unittest.main()
