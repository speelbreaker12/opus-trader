import importlib.util
import json
import subprocess
import tempfile
import unittest
from unittest import mock
from pathlib import Path


def load_phase1_compare_module():
    module_path = Path(__file__).resolve().parents[1] / "phase1_compare.py"
    spec = importlib.util.spec_from_file_location("phase1_compare", module_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"failed to load module from {module_path}")
    module = importlib.util.module_from_spec(spec)
    import sys

    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


PHASE1_COMPARE = load_phase1_compare_module()


class AnalyzeConfigMatrixTests(unittest.TestCase):
    def write_payload(self, payload):
        tmpdir = tempfile.TemporaryDirectory()
        self.addCleanup(tmpdir.cleanup)
        path = Path(tmpdir.name) / "missing_keys_matrix.json"
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_results_schema_counts_status_entries(self):
        payload = {
            "results": {
                "INSTRUMENT_TICK_SIZE": {"status": "PASS", "reason": "CONFIG_MISSING"},
                "INSTRUMENT_AMOUNT_STEP": {"status": "FAILED", "reason": "CONFIG_MISSING"},
                "INSTRUMENT_MIN_AMOUNT": {"status": "OK", "reason": "CONFIG_MISSING"},
            }
        }
        path = self.write_payload(payload)
        self.assertEqual(PHASE1_COMPARE.analyze_config_matrix(path), (3, 2, 1))

    def test_keys_schema_counts_result_entries(self):
        payload = {
            "keys": [
                {"key": "tick_size", "result": "PASS", "reason_code": "InstrumentMetadataMissing"},
                {"key": "amount_step", "result": "fail", "reason_code": "InstrumentMetadataMissing"},
                {"key": "gross_edge_usd", "result": "success", "reason_code": "NetEdgeInputMissing"},
            ]
        }
        path = self.write_payload(payload)
        self.assertEqual(PHASE1_COMPARE.analyze_config_matrix(path), (3, 2, 1))

    def test_summary_fallback_when_no_status_or_result_entries(self):
        payload = {
            "summary": {
                "total": 12,
                "passed": 12,
                "failed": 0,
            }
        }
        path = self.write_payload(payload)
        self.assertEqual(PHASE1_COMPARE.analyze_config_matrix(path), (12, 12, 0))


class RefWorkspaceTests(unittest.TestCase):
    def run_git(self, repo: Path, args: list[str]) -> str:
        rc, out, err, _ = PHASE1_COMPARE.run_cmd(["git", "-C", str(repo), *args], cwd=repo)
        if rc != 0:
            raise AssertionError(f"git {' '.join(args)} failed: {err.strip()}")
        return out.strip()

    def test_checkout_ref_worktree_uses_head_without_tempdir(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "repo"
            repo.mkdir()
            self.run_git(repo, ["init", "-q"])
            self.run_git(repo, ["config", "user.email", "test@example.com"])
            self.run_git(repo, ["config", "user.name", "Test User"])

            (repo / "evidence.txt").write_text("v1", encoding="utf-8")
            self.run_git(repo, ["add", "evidence.txt"])
            self.run_git(repo, ["commit", "-q", "-m", "v1"])

            snapshot = PHASE1_COMPARE.checkout_ref_worktree(repo, "HEAD")
            self.assertEqual(snapshot.path, repo)
            self.assertIsNone(snapshot.cleanup_dir)
            self.assertTrue(snapshot.is_ref_head)

    def test_checkout_ref_worktree_creates_detached_path_for_tagged_ref(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "repo"
            repo.mkdir()
            self.run_git(repo, ["init", "-q"])
            self.run_git(repo, ["config", "user.email", "test@example.com"])
            self.run_git(repo, ["config", "user.name", "Test User"])

            (repo / "evidence.txt").write_text("v1", encoding="utf-8")
            self.run_git(repo, ["add", "evidence.txt"])
            self.run_git(repo, ["commit", "-q", "-m", "v1"])
            base_sha = self.run_git(repo, ["rev-parse", "HEAD"])
            self.run_git(repo, ["tag", "phase1-test-base", base_sha])

            (repo / "evidence.txt").write_text("v2", encoding="utf-8")
            self.run_git(repo, ["add", "evidence.txt"])
            self.run_git(repo, ["commit", "-q", "-m", "v2"])

            snapshot = PHASE1_COMPARE.checkout_ref_worktree(repo, "phase1-test-base")
            try:
                self.assertNotEqual(snapshot.path, repo)
                self.assertEqual(snapshot.cleanup_dir, snapshot.path)
                self.assertFalse(snapshot.is_ref_head)
                self.assertEqual((snapshot.path / "evidence.txt").read_text(encoding="utf-8"), "v1")
            finally:
                warnings: list[str] = []
                PHASE1_COMPARE.cleanup_ref_worktree(repo, snapshot, warnings)
                self.assertEqual(warnings, [])
                self.assertFalse(snapshot.path.exists())


class BuildReportMarkdownTests(unittest.TestCase):
    def make_repo_result(
        self,
        name: str,
        path: Path,
        analysis_path: Path,
    ) -> PHASE1_COMPARE.RepoResult:
        path.mkdir(parents=True, exist_ok=True)
        analysis_path.mkdir(parents=True, exist_ok=True)
        return PHASE1_COMPARE.RepoResult(
            name=name,
            path=str(path),
            analysis_path=str(analysis_path),
            ref="HEAD",
            head_branch="HEAD",
            head_sha="abc123",
            resolved_ref_sha="abc123",
            is_ref_head=True,
            dirty_files=0,
            required_source="test",
            required_all=["evidence/phase1/README.md"],
            required_any_of=[["fallback.txt"]],
            required_all_ok=1,
            required_all_total=1,
            required_any_of_ok=1,
            required_any_of_total=1,
            missing_required_all=[],
            failed_any_of=[],
            file_checks=[],
            determinism_line_count=0,
            determinism_unique_hashes=0,
            traceability_line_count=0,
            traceability_unique_intent_ids=0,
            config_matrix_entries=0,
            config_matrix_pass=0,
            config_matrix_fail=0,
            verify_gate_summary=PHASE1_COMPARE.VerifyGateSummary(
                gate_headers=[],
                first_failure="",
                failure_lines=[],
            ),
            prd_phase1=PHASE1_COMPARE.PrdPhase1Stats(
                total_stories=0,
                passed_stories=0,
                remaining_stories=0,
                needs_human_decision_stories=0,
                stories_with_verify=0,
                stories_with_observability=0,
                missing_pass_story_ids=[],
                needs_human_story_ids=[],
            ),
            traceability=PHASE1_COMPARE.TraceabilityStats(
                stories_with_contract_refs=0,
                stories_missing_contract_refs=0,
                stories_with_enforcing_ats=0,
                stories_missing_enforcing_ats=0,
                missing_contract_ref_story_ids=[],
                missing_enforcing_ats_story_ids=[],
                unique_contract_at_refs=[],
                unknown_contract_at_refs=[],
                unique_anchor_refs=[],
                unknown_anchor_refs=[],
                unique_vr_refs=[],
                unknown_vr_refs=[],
            ),
            operational_readiness=PHASE1_COMPARE.OperationalReadinessStats(
                health_doc_exists=True,
                required_status_fields_present=0,
                required_status_fields_total=5,
                missing_required_status_fields=["build_id"],
                required_alert_metrics_present=0,
                required_alert_metrics_total=10,
                missing_required_alert_metrics=["m1"],
            ),
            verify_full=None,
            verify_full_gate_summary=PHASE1_COMPARE.VerifyGateSummary(
                gate_headers=[],
                first_failure="",
                failure_lines=[],
            ),
            verify_artifacts_latest=PHASE1_COMPARE.empty_verify_artifacts_summary(),
            verify_artifacts_quick=None,
            verify_artifacts_full=None,
            flakiness=None,
            scenario_behavior=PHASE1_COMPARE.ScenarioBehaviorSummary(
                reason_codes=[],
                status_fields_seen=[],
                dispatch_counts=[],
                rejection_lines=0,
            ),
            meta_test=None,
            verify_quick=None,
            scenario=None,
            diff_shortstat=None,
            diff_changed_files=None,
            blockers=0,
            warnings=[],
        )

    def test_report_header_includes_analysis_snapshot(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo_a = base / "repo_a"
            repo_b = base / "repo_b"
            analysis_a = base / "analysis_a"
            analysis_b = base / "analysis_b"
            a = self.make_repo_result("opus", repo_a, analysis_a)
            b = self.make_repo_result("ralph", repo_b, analysis_b)

            markdown = PHASE1_COMPARE.build_report_markdown(a, b, "test_run")

            self.assertIn(f"- Repo A analysis snapshot: `{a.analysis_path}`", markdown)
            self.assertIn(f"- Repo B analysis snapshot: `{b.analysis_path}`", markdown)

    def test_evidence_fallback_uses_repo_path_for_head(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo_a = base / "repo_a"
            repo_b = base / "repo_b"
            analysis_a = base / "analysis_a"
            analysis_b = base / "analysis_b"

            (repo_a / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
            (repo_b / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
            (repo_a / "evidence" / "phase1" / "README.md").write_text("alpha", encoding="utf-8")
            (repo_b / "evidence" / "phase1" / "README.md").write_text("alpha", encoding="utf-8")

            a = self.make_repo_result("opus", repo_a, analysis_a)
            b = self.make_repo_result("ralph", repo_b, analysis_b)
            a.required_all = ["evidence/phase1/README.md"]
            b.required_all = ["evidence/phase1/README.md"]
            markdown = PHASE1_COMPARE.build_report_markdown(a, b, "test_run")

            self.assertIn("| `evidence/phase1/README.md` | `ok` | `ok` | `yes` |", markdown)

    def test_reporesult_analysis_path_tracks_non_head_ref_worktree(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "repo"
            repo.mkdir()

            run_git = RefWorkspaceTests().run_git
            run_git(repo, ["init", "-q"])
            run_git(repo, ["config", "user.email", "test@example.com"])
            run_git(repo, ["config", "user.name", "Test User"])
            (repo / "file.txt").write_text("base", encoding="utf-8")
            run_git(repo, ["add", "file.txt"])
            run_git(repo, ["commit", "-q", "-m", "base"])

            base_sha = run_git(repo, ["rev-parse", "HEAD"])
            run_git(repo, ["tag", "phase1-test-base", base_sha])
            (repo / "file.txt").write_text("head", encoding="utf-8")
            run_git(repo, ["add", "file.txt"])
            run_git(repo, ["commit", "-q", "-m", "head"])

            snapshot = PHASE1_COMPARE.checkout_ref_worktree(repo, "phase1-test-base")
            try:
                result = self.make_repo_result("opus", repo, Path(snapshot.path))
                self.assertNotEqual(result.path, result.analysis_path)
                self.assertFalse(snapshot.is_ref_head)
                markdown = PHASE1_COMPARE.build_report_markdown(result, result, "test_run")
                self.assertIn(f"- Repo A analysis snapshot: `{result.analysis_path}`", markdown)
            finally:
                warnings: list[str] = []
                PHASE1_COMPARE.cleanup_ref_worktree(repo, snapshot, warnings)
                self.assertEqual(warnings, [])


class CollectRepoResultTests(unittest.TestCase):
    def run_git(self, repo: Path, args: list[str]) -> str:
        rc, out, err, _ = PHASE1_COMPARE.run_cmd(["git", "-C", str(repo), *args], cwd=repo)
        if rc != 0:
            raise AssertionError(f"git {' '.join(args)} failed: {err.strip()}")
        return out.strip()

    def init_repo(self, repo: Path) -> None:
        repo.mkdir(parents=True, exist_ok=True)
        self.run_git(repo, ["init", "-q"])
        self.run_git(repo, ["config", "user.email", "test@example.com"])
        self.run_git(repo, ["config", "user.name", "Test User"])

    def commit_all(self, repo: Path, message: str) -> None:
        self.run_git(repo, ["add", "."])
        self.run_git(repo, ["commit", "-q", "-m", message])

    def test_collect_repo_result_keeps_any_of_checks_after_snapshot_cleanup(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo = base / "repo"
            run_dir = base / "run"
            self.init_repo(repo)

            (repo / "docs").mkdir(parents=True, exist_ok=True)
            (repo / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
            (repo / "docs" / "PHASE1_CHECKLIST_BLOCK.md").write_text(
                "\n".join(
                    [
                        "<!-- REQUIRED_EVIDENCE: evidence/phase1/README.md -->",
                        "<!-- REQUIRED_EVIDENCE_ANY_OF: evidence/phase1/optionA.txt|evidence/phase1/optionB.txt -->",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (repo / "evidence" / "phase1" / "README.md").write_text("readme", encoding="utf-8")
            (repo / "evidence" / "phase1" / "optionA.txt").write_text("base-only", encoding="utf-8")
            self.commit_all(repo, "base")
            self.run_git(repo, ["tag", "phase1-test-base"])

            (repo / "evidence" / "phase1" / "optionA.txt").unlink()
            (repo / "head.txt").write_text("head", encoding="utf-8")
            self.commit_all(repo, "head")

            result = PHASE1_COMPARE.collect_repo_result(
                name="opus",
                repo_path=repo,
                ref="phase1-test-base",
                base_ref=None,
                run_meta_test=False,
                run_quick_verify=False,
                run_full_verify=False,
                scenario_cmd=None,
                flaky_runs=0,
                flaky_cmd=None,
                run_dir=run_dir,
            )

            self.assertFalse(result.is_ref_head)
            self.assertNotEqual(result.path, result.analysis_path)
            self.assertFalse(Path(result.analysis_path).exists())

            checks_by_path = {check.path: check for check in result.file_checks}
            self.assertIn("evidence/phase1/optionA.txt", checks_by_path)
            self.assertTrue(checks_by_path["evidence/phase1/optionA.txt"].exists)
            self.assertEqual(result.failed_any_of, [])

            markdown = PHASE1_COMPARE.build_report_markdown(result, result, "test_run")
            self.assertIn(
                "| `evidence/phase1/optionA.txt` | `ok` | `ok` | `yes` |",
                markdown,
            )

    def test_collect_repo_result_uses_resolved_sha_for_diff_stats(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo = base / "repo"
            run_dir = base / "run"
            self.init_repo(repo)

            (repo / "file.txt").write_text("v1", encoding="utf-8")
            self.commit_all(repo, "v1")
            (repo / "file.txt").write_text("v2", encoding="utf-8")
            self.commit_all(repo, "v2")

            with mock.patch.object(
                PHASE1_COMPARE,
                "gather_diff_stats",
                return_value=("no diff", 0),
            ) as gather_mock:
                result = PHASE1_COMPARE.collect_repo_result(
                    name="opus",
                    repo_path=repo,
                    ref="HEAD~1",
                    base_ref="HEAD",
                    run_meta_test=False,
                    run_quick_verify=False,
                    run_full_verify=False,
                    scenario_cmd=None,
                    flaky_runs=0,
                    flaky_cmd=None,
                    run_dir=run_dir,
                )

            self.assertEqual(gather_mock.call_count, 1)
            _, _, ref_arg = gather_mock.call_args.args
            self.assertEqual(ref_arg, result.resolved_ref_sha)
            self.assertNotEqual(ref_arg, "HEAD~1")


class EvidenceFallbackTests(unittest.TestCase):
    def run_git(self, repo: Path, args: list[str]) -> str:
        rc, out, err, _ = PHASE1_COMPARE.run_cmd(["git", "-C", str(repo), *args], cwd=repo)
        if rc != 0:
            raise AssertionError(f"git {' '.join(args)} failed: {err.strip()}")
        return out.strip()

    def init_repo(self, repo: Path) -> None:
        repo.mkdir(parents=True, exist_ok=True)
        self.run_git(repo, ["init", "-q"])
        self.run_git(repo, ["config", "user.email", "test@example.com"])
        self.run_git(repo, ["config", "user.name", "Test User"])

    def commit_all(self, repo: Path, message: str) -> None:
        self.run_git(repo, ["add", "."])
        self.run_git(repo, ["commit", "-q", "-m", message])

    def test_report_fallback_reads_non_head_ref_from_git(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo_a = base / "repo_a"
            repo_b = base / "repo_b"
            run_dir = base / "run"
            run_dir.mkdir(parents=True, exist_ok=True)

            self.init_repo(repo_a)
            self.init_repo(repo_b)

            for repo in (repo_a, repo_b):
                (repo / "docs").mkdir(parents=True, exist_ok=True)
                (repo / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
                (repo / "evidence" / "phase1" / "README.md").write_text("readme", encoding="utf-8")
                (repo / "evidence" / "phase1" / "extra.md").write_text(
                    "shared-extra", encoding="utf-8"
                )

            (repo_a / "docs" / "PHASE1_CHECKLIST_BLOCK.md").write_text(
                "<!-- REQUIRED_EVIDENCE: evidence/phase1/README.md -->\n",
                encoding="utf-8",
            )
            (repo_b / "docs" / "PHASE1_CHECKLIST_BLOCK.md").write_text(
                "\n".join(
                    [
                        "<!-- REQUIRED_EVIDENCE: evidence/phase1/README.md -->",
                        "<!-- REQUIRED_EVIDENCE: evidence/phase1/extra.md -->",
                        "",
                    ]
                ),
                encoding="utf-8",
            )

            self.commit_all(repo_a, "base")
            self.commit_all(repo_b, "base")
            self.run_git(repo_a, ["tag", "phase1-test-base"])
            self.run_git(repo_b, ["tag", "phase1-test-base"])

            (repo_a / "evidence" / "phase1" / "extra.md").write_text("head-only", encoding="utf-8")
            self.commit_all(repo_a, "head")
            (repo_b / "evidence" / "phase1" / "extra.md").write_text("head-only", encoding="utf-8")
            self.commit_all(repo_b, "head")

            result_a = PHASE1_COMPARE.collect_repo_result(
                name="opus",
                repo_path=repo_a,
                ref="phase1-test-base",
                base_ref=None,
                run_meta_test=False,
                run_quick_verify=False,
                run_full_verify=False,
                scenario_cmd=None,
                flaky_runs=0,
                flaky_cmd=None,
                run_dir=run_dir,
            )
            result_b = PHASE1_COMPARE.collect_repo_result(
                name="ralph",
                repo_path=repo_b,
                ref="phase1-test-base",
                base_ref=None,
                run_meta_test=False,
                run_quick_verify=False,
                run_full_verify=False,
                scenario_cmd=None,
                flaky_runs=0,
                flaky_cmd=None,
                run_dir=run_dir,
            )

            self.assertFalse(result_a.is_ref_head)
            self.assertNotEqual(result_a.path, result_a.analysis_path)
            self.assertFalse(Path(result_a.analysis_path).exists())
            self.assertNotIn(
                "evidence/phase1/extra.md",
                {check.path for check in result_a.file_checks},
            )

            markdown = PHASE1_COMPARE.build_report_markdown(result_a, result_b, "test_run")
            self.assertIn("| `evidence/phase1/extra.md` | `ok` | `ok` | `yes` |", markdown)

    def test_report_fallback_for_head_ref_uses_workspace_state(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            repo_a = base / "repo_a"
            repo_b = base / "repo_b"
            run_dir = base / "run"
            run_dir.mkdir(parents=True, exist_ok=True)

            self.init_repo(repo_a)
            self.init_repo(repo_b)

            (repo_a / "docs").mkdir(parents=True, exist_ok=True)
            (repo_a / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
            (repo_a / "docs" / "PHASE1_CHECKLIST_BLOCK.md").write_text(
                "<!-- REQUIRED_EVIDENCE: evidence/phase1/README.md -->\n",
                encoding="utf-8",
            )
            (repo_a / "evidence" / "phase1" / "README.md").write_text("readme", encoding="utf-8")
            self.commit_all(repo_a, "base")

            (repo_b / "docs").mkdir(parents=True, exist_ok=True)
            (repo_b / "evidence" / "phase1").mkdir(parents=True, exist_ok=True)
            (repo_b / "docs" / "PHASE1_CHECKLIST_BLOCK.md").write_text(
                "\n".join(
                    [
                        "<!-- REQUIRED_EVIDENCE: evidence/phase1/README.md -->",
                        "<!-- REQUIRED_EVIDENCE: evidence/phase1/extra.md -->",
                        "",
                    ]
                ),
                encoding="utf-8",
            )
            (repo_b / "evidence" / "phase1" / "README.md").write_text("readme", encoding="utf-8")
            (repo_b / "evidence" / "phase1" / "extra.md").write_text("workspace-extra", encoding="utf-8")
            self.commit_all(repo_b, "base")

            # Keep this path uncommitted on repo A to prove HEAD fallback uses workspace state.
            (repo_a / "evidence" / "phase1" / "extra.md").write_text("workspace-extra", encoding="utf-8")

            result_a = PHASE1_COMPARE.collect_repo_result(
                name="opus",
                repo_path=repo_a,
                ref="HEAD",
                base_ref=None,
                run_meta_test=False,
                run_quick_verify=False,
                run_full_verify=False,
                scenario_cmd=None,
                flaky_runs=0,
                flaky_cmd=None,
                run_dir=run_dir,
            )
            result_b = PHASE1_COMPARE.collect_repo_result(
                name="ralph",
                repo_path=repo_b,
                ref="HEAD",
                base_ref=None,
                run_meta_test=False,
                run_quick_verify=False,
                run_full_verify=False,
                scenario_cmd=None,
                flaky_runs=0,
                flaky_cmd=None,
                run_dir=run_dir,
            )

            self.assertTrue(result_a.is_ref_head)
            self.assertGreater(result_a.dirty_files, 0)
            self.assertNotIn(
                "evidence/phase1/extra.md",
                {check.path for check in result_a.file_checks},
            )

            markdown = PHASE1_COMPARE.build_report_markdown(result_a, result_b, "test_run")
            self.assertIn("| `evidence/phase1/extra.md` | `ok` | `ok` | `yes` |", markdown)

    def test_file_check_from_git_ref_records_unexpected_git_errors(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            repo = Path(tmpdir) / "repo"
            self.init_repo(repo)
            (repo / "tracked.txt").write_text("ok\n", encoding="utf-8")
            self.commit_all(repo, "base")

            warnings: list[str] = []
            check = PHASE1_COMPARE.file_check_from_git_ref(
                repo,
                "definitely-missing-ref",
                "tracked.txt",
                warnings=warnings,
            )

            self.assertFalse(check.exists)
            self.assertFalse(check.non_empty)
            self.assertEqual(check.sha256, "")
            self.assertTrue(any("cat-file type failed" in warning for warning in warnings))


class SnapshotIsolationSmokeScriptTests(unittest.TestCase):
    def test_stale_report_json_is_not_reused_when_phase1_compare_fails(self):
        with tempfile.TemporaryDirectory() as tmpdir:
            base = Path(tmpdir)
            output_md = base / "report.md"
            stale_report = base / "report.json"
            stale_report.write_text(
                json.dumps(
                    {
                        "opus": {
                            "is_ref_head": False,
                            "path": "/tmp/stale-opus",
                            "analysis_path": "/tmp/stale-opus-snapshot",
                        },
                        "ralph": {
                            "is_ref_head": False,
                            "path": "/tmp/stale-ralph",
                            "analysis_path": "/tmp/stale-ralph-snapshot",
                        },
                    }
                ),
                encoding="utf-8",
            )

            missing_repo = base / "does-not-exist"
            repo_root = Path(__file__).resolve().parents[2]
            script = repo_root / "scripts" / "check_phase1_compare_snapshot_isolation.sh"

            result = subprocess.run(
                [
                    str(script),
                    "--opus",
                    str(missing_repo),
                    "--ralph",
                    str(missing_repo),
                    "--skip-meta-test",
                    "--output",
                    str(output_md),
                ],
                cwd=repo_root,
                text=True,
                capture_output=True,
            )

            self.assertNotEqual(result.returncode, 0)
            self.assertIn("expected report JSON", result.stderr)


if __name__ == "__main__":
    unittest.main()
