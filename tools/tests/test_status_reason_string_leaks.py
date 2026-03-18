#!/usr/bin/env python3
import json
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "check_status_reason_string_leaks.py"


def write_manifest(path: Path, *, malformed: bool = False) -> None:
    if malformed:
        path.write_text('{"registries": {"ModeReasonCode": []}}', encoding="utf-8")
        return

    manifest = {
        "registries": {
            "ModeReasonCode": {
                "Kill": [
                    {"code": "KILL_ALPHA"},
                    {"code": "KILL_BETA"},
                ],
                "ReduceOnly": [
                    {"code": "REDUCEONLY_GAMMA"},
                ],
                "description": "test",
            },
            "OpenPermissionReasonCode": {
                "values": [
                    {"code": "RESTART_RECONCILE_REQUIRED"},
                ],
                "description": "test",
            },
            "RejectReasonCode": {
                "values": [
                    {"code": "TOO_SMALL_AFTER_QUANTIZATION"},
                ]
            },
        }
    }
    path.write_text(json.dumps(manifest), encoding="utf-8")


def write_rs(path: Path, body: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(body, encoding="utf-8")


class StatusReasonStringLeakTests(unittest.TestCase):
    maxDiff = None

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "specs" / "status").mkdir(parents=True, exist_ok=True)
        (self.root / "crates").mkdir(parents=True, exist_ok=True)
        write_manifest(self.root / "specs" / "status" / "status_reason_registries_manifest.json")

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def run_checker(self, *extra_args: str) -> subprocess.CompletedProcess[str]:
        cmd = [
            sys.executable,
            str(SCRIPT),
            "--manifest",
            "specs/status/status_reason_registries_manifest.json",
            "--scan-root",
            "crates",
            *extra_args,
        ]
        return subprocess.run(
            cmd,
            cwd=self.root,
            capture_output=True,
            text=True,
            env={**os.environ, "PYTHONUTF8": "1"},
        )

    def test_passes_when_no_forbidden_literals(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "main.rs",
            'const MSG: &str = "hello world";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_fails_for_standard_string_literal_match(self) -> None:
        write_rs(
            self.root / "crates" / "bad" / "one.rs",
            'const REASON: &str = "KILL_ALPHA";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("FAIL: /status mode/open-permission reason code literals leaked into Rust source", proc.stderr)
        self.assertIn("crates/bad/one.rs:1:KILL_ALPHA", proc.stderr)

    def test_fails_for_raw_string_literal_match(self) -> None:
        write_rs(
            self.root / "crates" / "bad" / "raw.rs",
            'const REASON: &str = r#"KILL_BETA"#;\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("crates/bad/raw.rs:1:KILL_BETA", proc.stderr)

    def test_fails_for_escaped_literal_match(self) -> None:
        write_rs(
            self.root / "crates" / "bad" / "escaped.rs",
            'const REASON: &str = "\\x4bILL_ALPHA";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("crates/bad/escaped.rs:1:KILL_ALPHA", proc.stderr)

    def test_fails_for_unicode_escaped_literal_match(self) -> None:
        write_rs(
            self.root / "crates" / "bad" / "unicode_escaped.rs",
            'const REASON: &str = "\\u{4b}ILL_BETA";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 1)
        self.assertIn("crates/bad/unicode_escaped.rs:1:KILL_BETA", proc.stderr)

    def test_ignores_comment_mentions(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "comments.rs",
            textwrap.dedent(
                """\
                // KILL_ALPHA
                /* RESTART_RECONCILE_REQUIRED */
                fn main() {}
                """
            ),
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_ignores_substring_inside_longer_literal(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "substring.rs",
            'const MSG: &str = "prefix KILL_ALPHA suffix";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_reject_reason_code_is_excluded(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "reject.rs",
            'const REJECT: &str = "TOO_SMALL_AFTER_QUANTIZATION";\n',
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 0, proc.stderr)

    def test_manifest_missing_returns_setup_error(self) -> None:
        proc = subprocess.run(
            [
                sys.executable,
                str(SCRIPT),
                "--manifest",
                "specs/status/missing.json",
                "--scan-root",
                "crates",
            ],
            cwd=self.root,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)

    def test_manifest_malformed_returns_setup_error(self) -> None:
        write_manifest(
            self.root / "specs" / "status" / "status_reason_registries_manifest.json",
            malformed=True,
        )
        proc = self.run_checker()
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)

    def test_invalid_allow_path_returns_setup_error(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "main.rs",
            'const MSG: &str = "hello world";\n',
        )
        proc = self.run_checker("--allow-path", "../escape.rs")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)

    def test_absolute_allow_path_returns_setup_error(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "main.rs",
            'const MSG: &str = "hello world";\n',
        )
        proc = self.run_checker("--allow-path", "/tmp/abs.rs")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)

    def test_nonexistent_allow_path_returns_setup_error(self) -> None:
        write_rs(
            self.root / "crates" / "ok" / "main.rs",
            'const MSG: &str = "hello world";\n',
        )
        proc = self.run_checker("--allow-path", "crates/missing.rs")
        self.assertEqual(proc.returncode, 2)
        self.assertIn("FAIL: SETUP ERROR:", proc.stderr)

    def test_output_is_sorted_and_deterministic(self) -> None:
        write_rs(
            self.root / "crates" / "z_mod" / "z.rs",
            textwrap.dedent(
                """\
                fn one() {
                    let _ = "REDUCEONLY_GAMMA";
                }
                """
            ),
        )
        write_rs(
            self.root / "crates" / "a_mod" / "a.rs",
            textwrap.dedent(
                """\
                fn two() {
                    let _ = "KILL_ALPHA";
                    let _ = "RESTART_RECONCILE_REQUIRED";
                }
                """
            ),
        )

        proc = self.run_checker()
        self.assertEqual(proc.returncode, 1)
        hit_lines = [line.strip() for line in proc.stderr.splitlines() if line.startswith("crates/")]
        self.assertEqual(
            hit_lines,
            [
                "crates/a_mod/a.rs:2:KILL_ALPHA",
                "crates/a_mod/a.rs:3:RESTART_RECONCILE_REQUIRED",
                "crates/z_mod/z.rs:2:REDUCEONLY_GAMMA",
            ],
        )


if __name__ == "__main__":
    unittest.main()
