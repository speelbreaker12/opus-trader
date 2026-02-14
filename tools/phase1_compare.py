#!/usr/bin/env python3
"""
Cross-repo Phase 1 comparison tool.

Compares outcome signals between two repositories (default: opus-trader vs ralph):
- Git snapshot metadata (branch/ref/sha/dirty state)
- Phase 1 evidence pack coverage from checklist markers
- Phase 1 meta-test result
- Optional verify quick result
- Optional verify full result
- Optional per-repo verify toggles (run quick/full on opus and/or ralph)
- Verify gate-by-gate parity (headers + first failure line)
- Verify artifact parity from `artifacts/verify/*/*.rc` and `*.time`
- Phase 1 PRD completion parity (pass/remaining/needs_human_decision)
- Phase 1 traceability parity (contract refs + enforcing AT coverage)
- Operational readiness signal parity (status fields + alert metrics footprint)
- Optional identical scenario command timing/result
- Optional scenario behavior diff (reason codes/status fields/dispatch counters)
- Optional flakiness runs (repeat command N times; compare variance)
- Optional implementation churn stats from base refs
- Weighted decision scoring (correctness/safety, performance, maintainability)

Outputs:
- Markdown report
- JSON report
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import re
import shlex
import subprocess
import tempfile
import sys
import time
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Sequence, Tuple


DEFAULT_REQUIRED_EVIDENCE: List[str] = [
    "evidence/phase1/README.md",
    "evidence/phase1/ci_links.md",
    "evidence/phase1/determinism/intent_hashes.txt",
    "evidence/phase1/no_side_effects/rejection_cases.md",
    "evidence/phase1/traceability/sample_rejection_log.txt",
    "evidence/phase1/config_fail_closed/missing_keys_matrix.json",
    "evidence/phase1/restart_loop/restart_100_cycles.log",
]

DEFAULT_REQUIRED_ANY_OF: List[List[str]] = [
    [
        "evidence/phase1/crash_mid_intent/auto_test_passed.txt",
        "evidence/phase1/crash_mid_intent/drill.md",
    ]
]

REQUIRED_RE = re.compile(r"<!--\s*REQUIRED_EVIDENCE:\s*(.*?)\s*-->")
REQUIRED_ANY_OF_RE = re.compile(r"<!--\s*REQUIRED_EVIDENCE_ANY_OF:\s*(.*?)\s*-->")
INTENT_ID_RE = re.compile(r"intent_id(?:=|:|\s+)([A-Za-z0-9_.:-]+)")
ANSI_RE = re.compile(r"\x1b\[[0-9;]*m")
AT_ID_RE = re.compile(r"\bAT-\d+\b")
ANCHOR_ID_RE = re.compile(r"\bAnchor-\d+\b")
VR_ID_RE = re.compile(r"\bVR-\d+\b")

REQUIRED_STATUS_FIELDS: List[str] = [
    "build_id",
    "contract_version",
    "trading_mode",
    "is_trading_allowed",
    "risk_state",
]

REQUIRED_ALERT_METRICS: List[str] = [
    "atomic_naked_events",
    "429_count_5m",
    "10028_count_5m",
    "truth_capsule_write_errors",
    "decision_snapshot_write_errors",
    "wal_write_errors",
    "parquet_write_errors",
    "parquet_queue_overflow_count",
    "evidence_guard_blocked_opens_count",
    "policy_age_sec",
]


@dataclass
class CommandResult:
    command: str
    exit_code: int
    elapsed_s: float
    log_path: str


@dataclass
class VerifyGateSummary:
    gate_headers: List[str]
    first_failure: str
    failure_lines: List[str]


@dataclass
class RefWorkspace:
    path: Path
    resolved_ref_sha: str
    is_ref_head: bool
    cleanup_dir: Optional[Path]


@dataclass
class PrdPhase1Stats:
    total_stories: int
    passed_stories: int
    remaining_stories: int
    needs_human_decision_stories: int
    stories_with_verify: int
    stories_with_observability: int
    missing_pass_story_ids: List[str]
    needs_human_story_ids: List[str]


@dataclass
class TraceabilityStats:
    stories_with_contract_refs: int
    stories_missing_contract_refs: int
    stories_with_enforcing_ats: int
    stories_missing_enforcing_ats: int
    missing_contract_ref_story_ids: List[str]
    missing_enforcing_ats_story_ids: List[str]
    unique_contract_at_refs: List[str]
    unknown_contract_at_refs: List[str]
    unique_anchor_refs: List[str]
    unknown_anchor_refs: List[str]
    unique_vr_refs: List[str]
    unknown_vr_refs: List[str]


@dataclass
class OperationalReadinessStats:
    health_doc_exists: bool
    required_status_fields_present: int
    required_status_fields_total: int
    missing_required_status_fields: List[str]
    required_alert_metrics_present: int
    required_alert_metrics_total: int
    missing_required_alert_metrics: List[str]


@dataclass
class FileCheck:
    path: str
    exists: bool
    non_empty: bool
    size_bytes: int
    sha256: str


@dataclass
class VerifyArtifactsSummary:
    run_id: str
    run_dir: str
    gate_rc: Dict[str, int]
    gate_time_s: Dict[str, float]
    pass_gates: int
    fail_gates: int


@dataclass
class FlakinessSummary:
    command: str
    runs: int
    success_runs: int
    fail_runs: int
    exit_codes_seen: List[int]
    min_elapsed_s: float
    max_elapsed_s: float
    avg_elapsed_s: float
    log_paths: List[str]


@dataclass
class ScenarioBehaviorSummary:
    reason_codes: List[str]
    status_fields_seen: List[str]
    dispatch_counts: List[int]
    rejection_lines: int


@dataclass
class RepoResult:
    name: str
    path: str
    analysis_path: str
    ref: str
    head_branch: str
    head_sha: str
    resolved_ref_sha: str
    is_ref_head: bool
    dirty_files: int
    required_source: str
    required_all: List[str]
    required_any_of: List[List[str]]
    required_all_ok: int
    required_all_total: int
    required_any_of_ok: int
    required_any_of_total: int
    missing_required_all: List[str]
    failed_any_of: List[List[str]]
    file_checks: List[FileCheck]
    determinism_line_count: int
    determinism_unique_hashes: int
    traceability_line_count: int
    traceability_unique_intent_ids: int
    config_matrix_entries: int
    config_matrix_pass: int
    config_matrix_fail: int
    verify_gate_summary: VerifyGateSummary
    prd_phase1: PrdPhase1Stats
    traceability: TraceabilityStats
    operational_readiness: OperationalReadinessStats
    verify_full: Optional[CommandResult]
    verify_full_gate_summary: VerifyGateSummary
    verify_artifacts_latest: VerifyArtifactsSummary
    verify_artifacts_quick: Optional[VerifyArtifactsSummary]
    verify_artifacts_full: Optional[VerifyArtifactsSummary]
    flakiness: Optional[FlakinessSummary]
    scenario_behavior: ScenarioBehaviorSummary
    meta_test: Optional[CommandResult]
    verify_quick: Optional[CommandResult]
    scenario: Optional[CommandResult]
    diff_shortstat: Optional[str]
    diff_changed_files: Optional[int]
    blockers: int
    warnings: List[str]


def run_cmd(
    command: Sequence[str],
    cwd: Path,
    log_path: Optional[Path] = None,
    env: Optional[Dict[str, str]] = None,
) -> Tuple[int, str, str, float]:
    started = time.time()
    result = subprocess.run(
        command,
        cwd=str(cwd),
        text=True,
        capture_output=True,
        env=env,
    )
    elapsed = time.time() - started
    if log_path is not None:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        payload = [
            f"$ {' '.join(shlex.quote(x) for x in command)}",
            f"[exit={result.returncode}] [elapsed_s={elapsed:.3f}]",
            "",
            "=== STDOUT ===",
            result.stdout,
            "",
            "=== STDERR ===",
            result.stderr,
            "",
        ]
        log_path.write_text("\n".join(payload), encoding="utf-8")
    return result.returncode, result.stdout, result.stderr, elapsed


def resolve_ref_sha(repo_path: Path, ref: str) -> str:
    try:
        return git_read(repo_path, ["rev-parse", f"{ref}^{{}}"])
    except RuntimeError:
        return git_read(repo_path, ["rev-parse", ref])


def checkout_ref_worktree(repo_path: Path, ref: str) -> RefWorkspace:
    if not repo_path.exists():
        raise RuntimeError(f"repo path does not exist: {repo_path}")

    resolved_ref_sha = resolve_ref_sha(repo_path, ref)
    head_sha = git_read(repo_path, ["rev-parse", "HEAD"])
    is_ref_head = resolved_ref_sha == head_sha
    if is_ref_head:
        return RefWorkspace(
            path=repo_path,
            resolved_ref_sha=resolved_ref_sha,
            is_ref_head=True,
            cleanup_dir=None,
        )

    worktree_dir = Path(tempfile.mkdtemp(prefix="phase1-compare-wt-"))
    rc, _, err, _ = run_cmd(
        ["git", "-C", str(repo_path), "worktree", "add", "--detach", str(worktree_dir), resolved_ref_sha],
        cwd=repo_path,
    )
    if rc != 0:
        shutil.rmtree(worktree_dir, ignore_errors=True)
        raise RuntimeError(f"git worktree add --detach for {repo_path} at {ref} failed: {err.strip()}")

    return RefWorkspace(
        path=worktree_dir,
        resolved_ref_sha=resolved_ref_sha,
        is_ref_head=False,
        cleanup_dir=worktree_dir,
    )


def cleanup_ref_worktree(repo_path: Path, snapshot: RefWorkspace, warnings: List[str]) -> None:
    if snapshot.cleanup_dir is None:
        return
    if snapshot.cleanup_dir == repo_path:
        return
    rc, _, err, _ = run_cmd(
        ["git", "-C", str(repo_path), "worktree", "remove", "--force", str(snapshot.cleanup_dir)],
        cwd=repo_path,
    )
    if rc != 0:
        warnings.append(f"failed to remove temporary worktree {snapshot.cleanup_dir}: {err.strip()}")
    shutil.rmtree(snapshot.cleanup_dir, ignore_errors=True)


def git_read(repo: Path, args: Sequence[str]) -> str:
    rc, out, err, _ = run_cmd(["git", "-C", str(repo), *args], cwd=repo)
    if rc != 0:
        raise RuntimeError(f"git {' '.join(args)} failed for {repo}: {err.strip()}")
    return out.strip()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        while True:
            chunk = fh.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def parse_required_evidence(repo: Path) -> Tuple[List[str], List[List[str]], str]:
    candidates = [
        repo / "docs" / "PHASE1_CHECKLIST_BLOCK.md",
        repo / "docs" / "ROADMAP.md",
        repo / "docs" / "phase1_acceptance.md",
    ]

    required_all: List[str] = []
    required_any_of: List[List[str]] = []
    source = "fallback defaults"

    for candidate in candidates:
        if not candidate.exists():
            continue
        text = candidate.read_text(encoding="utf-8", errors="replace")
        found = False
        for match in REQUIRED_RE.finditer(text):
            path = match.group(1).strip()
            if path:
                required_all.append(path)
                found = True
        for match in REQUIRED_ANY_OF_RE.finditer(text):
            raw = match.group(1).strip()
            if raw:
                options = [part.strip() for part in raw.split("|") if part.strip()]
                if options:
                    required_any_of.append(options)
                    found = True
        if found:
            source = str(candidate.relative_to(repo))
            break

    if not required_all:
        required_all = list(DEFAULT_REQUIRED_EVIDENCE)
    if not required_any_of:
        required_any_of = [list(group) for group in DEFAULT_REQUIRED_ANY_OF]

    # Deterministic unique ordering.
    required_all = sorted(set(required_all))
    normalized_groups = []
    seen_group_keys = set()
    for group in required_any_of:
        key = tuple(sorted(set(group)))
        if not key:
            continue
        if key in seen_group_keys:
            continue
        seen_group_keys.add(key)
        normalized_groups.append(list(key))

    return required_all, normalized_groups, source


def analyze_config_matrix(path: Path) -> Tuple[int, int, int]:
    if not path.exists() or not path.is_file():
        return 0, 0, 0
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return 0, 0, 0

    def extract_entry_status(node: object) -> Optional[str]:
        if not isinstance(node, dict):
            return None
        for key in ("status", "result"):
            value = node.get(key)
            if isinstance(value, str):
                return value
        return None

    def walk(node: object) -> Iterable[str]:
        if isinstance(node, dict):
            status = extract_entry_status(node)
            if status is not None:
                yield status
            for value in node.values():
                yield from walk(value)
        elif isinstance(node, list):
            for item in node:
                yield from walk(item)

    statuses: List[str] = []
    if isinstance(payload, dict):
        results = payload.get("results")
        if isinstance(results, dict):
            for item in results.values():
                status = extract_entry_status(item)
                if status is not None:
                    statuses.append(status)

        keys = payload.get("keys")
        if isinstance(keys, list):
            for item in keys:
                status = extract_entry_status(item)
                if status is not None:
                    statuses.append(status)

    if not statuses:
        statuses = [value.upper() for value in walk(payload)]

    if not statuses and isinstance(payload, dict):
        summary = payload.get("summary")
        if isinstance(summary, dict):
            total = summary.get("total")
            passed = summary.get("passed")
            failed = summary.get("failed")
            if all(isinstance(value, int) for value in (total, passed, failed)):
                return int(total), int(passed), int(failed)

    statuses = [value.upper() for value in statuses if value.strip()]
    entries = len(statuses)
    pass_count = sum(1 for s in statuses if s in {"PASS", "PASSED", "OK", "SUCCESS"})
    fail_count = sum(1 for s in statuses if s in {"FAIL", "FAILED", "ERROR"})
    return entries, pass_count, fail_count


def file_check(repo: Path, rel_path: str) -> FileCheck:
    full = repo / rel_path
    if not full.exists() or not full.is_file():
        return FileCheck(
            path=rel_path,
            exists=False,
            non_empty=False,
            size_bytes=0,
            sha256="",
        )
    size = full.stat().st_size
    return FileCheck(
        path=rel_path,
        exists=True,
        non_empty=size > 0,
        size_bytes=size,
        sha256=sha256_file(full),
    )


def file_check_from_git_ref(
    repo: Path,
    resolved_ref_sha: str,
    rel_path: str,
    warnings: Optional[List[str]] = None,
) -> FileCheck:
    object_spec = f"{resolved_ref_sha}:{rel_path}"
    rc, out, err, _ = run_cmd(
        ["git", "-C", str(repo), "cat-file", "-t", object_spec],
        cwd=repo,
    )
    if rc != 0:
        err_text = err.strip()
        expected_missing = (
            "does not exist in" in err_text or "Not a valid object name" in err_text
        )
        if warnings is not None and err_text and not expected_missing:
            warning = f"git cat-file type failed for {object_spec!r}: {err_text}"
            if warning not in warnings:
                warnings.append(warning)
        return FileCheck(
            path=rel_path,
            exists=False,
            non_empty=False,
            size_bytes=0,
            sha256="",
        )
    if out.strip() != "blob":
        return FileCheck(
            path=rel_path,
            exists=False,
            non_empty=False,
            size_bytes=0,
            sha256="",
        )

    digest = hashlib.sha256()
    size = 0
    proc = subprocess.Popen(
        ["git", "-C", str(repo), "cat-file", "blob", object_spec],
        cwd=str(repo),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if proc.stdout is None:
        if warnings is not None:
            warning = f"git cat-file did not provide stdout for {object_spec!r}"
            if warning not in warnings:
                warnings.append(warning)
        proc.kill()
        proc.wait()
        return FileCheck(
            path=rel_path,
            exists=False,
            non_empty=False,
            size_bytes=0,
            sha256="",
        )
    while True:
        chunk = proc.stdout.read(65536)
        if not chunk:
            break
        size += len(chunk)
        digest.update(chunk)
    _, stderr_bytes = proc.communicate()
    if proc.returncode != 0:
        if warnings is not None:
            err_text = stderr_bytes.decode("utf-8", errors="replace").strip()
            warning = f"git cat-file blob failed for {object_spec!r}: {err_text}"
            if warning not in warnings:
                warnings.append(warning)
        return FileCheck(
            path=rel_path,
            exists=False,
            non_empty=False,
            size_bytes=0,
            sha256="",
        )

    return FileCheck(
        path=rel_path,
        exists=True,
        non_empty=size > 0,
        size_bytes=size,
        sha256=digest.hexdigest(),
    )


def file_check_for_result(repo_result: RepoResult, rel_path: str) -> FileCheck:
    if repo_result.is_ref_head:
        return file_check(Path(repo_result.path), rel_path)
    return file_check_from_git_ref(
        Path(repo_result.path),
        repo_result.resolved_ref_sha,
        rel_path,
        warnings=repo_result.warnings,
    )


def count_non_empty_lines(path: Path) -> int:
    if not path.exists() or not path.is_file():
        return 0
    text = path.read_text(encoding="utf-8", errors="replace")
    return sum(1 for line in text.splitlines() if line.strip())


def count_unique_intent_ids(path: Path) -> int:
    if not path.exists() or not path.is_file():
        return 0
    text = path.read_text(encoding="utf-8", errors="replace")
    ids = {m.group(1) for m in INTENT_ID_RE.finditer(text)}
    return len(ids)


def run_named_command(
    name: str,
    command: Sequence[str],
    repo_path: Path,
    logs_dir: Path,
) -> CommandResult:
    slug = name.lower().replace(" ", "_")
    log_path = logs_dir / f"{slug}.log"
    rc, _, _, elapsed = run_cmd(command, cwd=repo_path, log_path=log_path)
    return CommandResult(
        command=" ".join(shlex.quote(x) for x in command),
        exit_code=rc,
        elapsed_s=round(elapsed, 3),
        log_path=str(log_path),
    )


def strip_ansi(text: str) -> str:
    return ANSI_RE.sub("", text)


def unique_preserve_order(values: Iterable[str]) -> List[str]:
    seen = set()
    out: List[str] = []
    for value in values:
        if value in seen:
            continue
        seen.add(value)
        out.append(value)
    return out


def analyze_verify_quick_log(log_path: Path) -> VerifyGateSummary:
    if not log_path.exists():
        return VerifyGateSummary(gate_headers=[], first_failure="", failure_lines=[])

    text = strip_ansi(log_path.read_text(encoding="utf-8", errors="replace"))
    gate_headers: List[str] = []
    for match in re.finditer(r"===\s*(.*?)\s*===", text):
        raw = match.group(1).strip()
        if raw in {"STDOUT", "STDERR"}:
            continue
        normalized = re.sub(r"^\d+[a-z]?\)\s*", "", raw, flags=re.IGNORECASE).strip()
        if normalized:
            gate_headers.append(normalized)

    failure_lines: List[str] = []
    for line in text.splitlines():
        stripped = line.strip()
        if not stripped:
            continue
        if "FAIL:" in stripped or stripped.startswith("ERROR:"):
            failure_lines.append(stripped)

    failure_lines = unique_preserve_order(failure_lines)
    first_failure = failure_lines[0] if failure_lines else ""
    return VerifyGateSummary(
        gate_headers=unique_preserve_order(gate_headers),
        first_failure=first_failure,
        failure_lines=failure_lines[:6],
    )


def empty_verify_artifacts_summary() -> VerifyArtifactsSummary:
    return VerifyArtifactsSummary(
        run_id="",
        run_dir="",
        gate_rc={},
        gate_time_s={},
        pass_gates=0,
        fail_gates=0,
    )


def parse_int_token(raw: str) -> Optional[int]:
    token = raw.strip().split()
    if not token:
        return None
    try:
        return int(token[0])
    except ValueError:
        return None


def parse_float_token(raw: str) -> Optional[float]:
    token = raw.strip().split()
    if not token:
        return None
    try:
        return float(token[0])
    except ValueError:
        return None


def extract_verify_run_id_from_log(log_path: Path) -> str:
    if not log_path.exists():
        return ""
    text = log_path.read_text(encoding="utf-8", errors="replace")
    match = re.search(r"\bverify_run_id=([A-Za-z0-9_.-]+)\b", text)
    if match:
        return match.group(1)
    match = re.search(r"artifacts/verify/([A-Za-z0-9_.-]+)", text)
    if match:
        return match.group(1)
    return ""


def latest_verify_run_dir(repo_path: Path) -> Optional[Path]:
    verify_root = repo_path / "artifacts" / "verify"
    if not verify_root.exists() or not verify_root.is_dir():
        return None
    run_dirs = [entry for entry in verify_root.iterdir() if entry.is_dir()]
    if not run_dirs:
        return None
    return max(run_dirs, key=lambda p: p.stat().st_mtime)


def parse_verify_artifacts(repo_path: Path, run_id: str = "") -> VerifyArtifactsSummary:
    verify_root = repo_path / "artifacts" / "verify"
    run_dir: Optional[Path] = None
    if run_id:
        candidate = verify_root / run_id
        if candidate.exists() and candidate.is_dir():
            run_dir = candidate
    if run_dir is None:
        run_dir = latest_verify_run_dir(repo_path)
    if run_dir is None:
        return empty_verify_artifacts_summary()

    gate_rc: Dict[str, int] = {}
    gate_time_s: Dict[str, float] = {}

    for path in sorted(run_dir.glob("*.rc")):
        gate = path.stem
        value = parse_int_token(path.read_text(encoding="utf-8", errors="replace"))
        if value is not None:
            gate_rc[gate] = value

    for path in sorted(run_dir.glob("*.time")):
        gate = path.stem
        value = parse_float_token(path.read_text(encoding="utf-8", errors="replace"))
        if value is not None:
            gate_time_s[gate] = value

    pass_gates = sum(1 for value in gate_rc.values() if value == 0)
    fail_gates = sum(1 for value in gate_rc.values() if value != 0)
    return VerifyArtifactsSummary(
        run_id=run_dir.name,
        run_dir=str(run_dir),
        gate_rc=gate_rc,
        gate_time_s=gate_time_s,
        pass_gates=pass_gates,
        fail_gates=fail_gates,
    )


def analyze_scenario_behavior(log_path: Path) -> ScenarioBehaviorSummary:
    if not log_path.exists():
        return ScenarioBehaviorSummary(
            reason_codes=[],
            status_fields_seen=[],
            dispatch_counts=[],
            rejection_lines=0,
        )

    text = strip_ansi(log_path.read_text(encoding="utf-8", errors="replace"))
    reason_codes: set[str] = set()
    for match in re.finditer(r"reason[_ ]?code(?:=|:|\s+)[\"']?([A-Z0-9_]+)", text):
        reason_codes.add(match.group(1))
    for match in re.finditer(r"ModeReasonCode::([A-Z0-9_]+)", text):
        reason_codes.add(match.group(1))
    for match in re.finditer(r"\b(?:REJECT_[A-Z0-9_]+|CONFIG_[A-Z0-9_]+|POLICY_[A-Z0-9_]+|RISK_[A-Z0-9_]+)\b", text):
        reason_codes.add(match.group(0))

    status_seen = [field for field in REQUIRED_STATUS_FIELDS if field in text]

    dispatch_numbers = []
    for pattern in [
        r"(?:dispatch_count|dispatches|dispatched)\D+(\d+)",
        r"dispatch\s+count\D+(\d+)",
    ]:
        dispatch_numbers.extend(int(match.group(1)) for match in re.finditer(pattern, text, flags=re.IGNORECASE))
    dispatch_counts = sorted(set(dispatch_numbers))

    rejection_lines = sum(
        1 for line in text.splitlines() if "reject" in line.lower() or "blocked" in line.lower()
    )
    return ScenarioBehaviorSummary(
        reason_codes=sorted(reason_codes),
        status_fields_seen=status_seen,
        dispatch_counts=dispatch_counts,
        rejection_lines=rejection_lines,
    )


def run_flakiness_series(
    repo_path: Path,
    logs_dir: Path,
    command_text: str,
    runs: int,
) -> FlakinessSummary:
    run_results: List[CommandResult] = []
    for idx in range(1, runs + 1):
        run_results.append(
            run_named_command(
                name=f"flaky_run_{idx:02d}",
                command=["bash", "-lc", command_text],
                repo_path=repo_path,
                logs_dir=logs_dir,
            )
        )

    elapsed = [item.elapsed_s for item in run_results]
    exit_codes = sorted({item.exit_code for item in run_results})
    success_runs = sum(1 for item in run_results if item.exit_code == 0)
    fail_runs = runs - success_runs
    avg_elapsed = round(sum(elapsed) / len(elapsed), 3) if elapsed else 0.0
    return FlakinessSummary(
        command=command_text,
        runs=runs,
        success_runs=success_runs,
        fail_runs=fail_runs,
        exit_codes_seen=exit_codes,
        min_elapsed_s=min(elapsed) if elapsed else 0.0,
        max_elapsed_s=max(elapsed) if elapsed else 0.0,
        avg_elapsed_s=avg_elapsed,
        log_paths=[item.log_path for item in run_results],
    )


def phase_value(item: Dict[str, object]) -> Optional[int]:
    raw = item.get("phase")
    if isinstance(raw, int):
        return raw
    if isinstance(raw, str):
        try:
            return int(raw)
        except ValueError:
            return None
    return None


def read_prd_items(repo_path: Path) -> List[Dict[str, object]]:
    prd_path = repo_path / "plans" / "prd.json"
    if not prd_path.exists():
        return []
    try:
        payload = json.loads(prd_path.read_text(encoding="utf-8"))
    except Exception:
        return []
    items = payload.get("items", [])
    if not isinstance(items, list):
        return []
    normalized: List[Dict[str, object]] = []
    for item in items:
        if isinstance(item, dict):
            normalized.append(item)
    return normalized


def analyze_phase1_prd(prd_items: List[Dict[str, object]]) -> PrdPhase1Stats:
    phase1_items = [item for item in prd_items if phase_value(item) == 1]
    total = len(phase1_items)
    passed = 0
    needs_human = 0
    with_verify = 0
    with_observability = 0
    missing_pass_story_ids: List[str] = []
    needs_human_story_ids: List[str] = []

    for item in phase1_items:
        story_id = item.get("id")
        story_id_str = str(story_id) if isinstance(story_id, str) else "<unknown>"
        if item.get("passes") is True:
            passed += 1
        else:
            missing_pass_story_ids.append(story_id_str)

        if item.get("needs_human_decision") is True:
            needs_human += 1
            needs_human_story_ids.append(story_id_str)

        verify = item.get("verify")
        if isinstance(verify, list) and len(verify) > 0:
            with_verify += 1

        observability = item.get("observability")
        if isinstance(observability, dict):
            metrics = observability.get("metrics")
            status_fields = observability.get("status_fields")
            if (isinstance(metrics, list) and len(metrics) > 0) or (
                isinstance(status_fields, list) and len(status_fields) > 0
            ):
                with_observability += 1

    return PrdPhase1Stats(
        total_stories=total,
        passed_stories=passed,
        remaining_stories=max(0, total - passed),
        needs_human_decision_stories=needs_human,
        stories_with_verify=with_verify,
        stories_with_observability=with_observability,
        missing_pass_story_ids=sorted(set(missing_pass_story_ids)),
        needs_human_story_ids=sorted(set(needs_human_story_ids)),
    )


def analyze_traceability(
    repo_path: Path,
    prd_items: List[Dict[str, object]],
) -> TraceabilityStats:
    phase1_items = [item for item in prd_items if phase_value(item) == 1]
    contract_path = repo_path / "specs" / "CONTRACT.md"
    contract_text = ""
    if contract_path.exists():
        contract_text = contract_path.read_text(encoding="utf-8", errors="replace")

    known_at = set(AT_ID_RE.findall(contract_text))
    known_anchor = set(ANCHOR_ID_RE.findall(contract_text))
    known_vr = set(VR_ID_RE.findall(contract_text))

    stories_with_contract_refs = 0
    stories_with_enforcing_ats = 0
    missing_contract_ref_story_ids: List[str] = []
    missing_enforcing_ats_story_ids: List[str] = []
    at_refs: set[str] = set()
    anchor_refs: set[str] = set()
    vr_refs: set[str] = set()

    for item in phase1_items:
        story_id = item.get("id")
        story_id_str = story_id if isinstance(story_id, str) else "<unknown>"
        contract_refs = item.get("contract_refs")
        refs_list: List[str] = []
        if isinstance(contract_refs, list):
            refs_list = [str(x) for x in contract_refs if isinstance(x, str)]
        has_contract_refs = len(refs_list) > 0
        if has_contract_refs:
            stories_with_contract_refs += 1
            joined = "\n".join(refs_list)
            at_refs.update(AT_ID_RE.findall(joined))
            anchor_refs.update(ANCHOR_ID_RE.findall(joined))
            vr_refs.update(VR_ID_RE.findall(joined))
        else:
            missing_contract_ref_story_ids.append(story_id_str)

        enforcing = item.get("enforcing_contract_ats")
        has_enforcing = isinstance(enforcing, list) and len(enforcing) > 0
        if has_enforcing:
            stories_with_enforcing_ats += 1
            enforcing_joined = "\n".join(str(x) for x in enforcing if isinstance(x, str))
            at_refs.update(AT_ID_RE.findall(enforcing_joined))
        elif has_contract_refs:
            missing_enforcing_ats_story_ids.append(story_id_str)

    unknown_at = sorted(ref for ref in at_refs if ref not in known_at)
    unknown_anchor = sorted(ref for ref in anchor_refs if ref not in known_anchor)
    unknown_vr = sorted(ref for ref in vr_refs if ref not in known_vr)

    return TraceabilityStats(
        stories_with_contract_refs=stories_with_contract_refs,
        stories_missing_contract_refs=len(missing_contract_ref_story_ids),
        stories_with_enforcing_ats=stories_with_enforcing_ats,
        stories_missing_enforcing_ats=len(missing_enforcing_ats_story_ids),
        missing_contract_ref_story_ids=sorted(set(missing_contract_ref_story_ids)),
        missing_enforcing_ats_story_ids=sorted(set(missing_enforcing_ats_story_ids)),
        unique_contract_at_refs=sorted(at_refs),
        unknown_contract_at_refs=unknown_at,
        unique_anchor_refs=sorted(anchor_refs),
        unknown_anchor_refs=unknown_anchor,
        unique_vr_refs=sorted(vr_refs),
        unknown_vr_refs=unknown_vr,
    )


def token_exists_in_repo(repo_path: Path, token: str) -> Tuple[bool, Optional[str]]:
    rc, _, err, _ = run_cmd(
        ["git", "-C", str(repo_path), "grep", "-n", "-F", token],
        cwd=repo_path,
    )
    if rc == 0:
        return True, None
    if rc == 1:
        return False, None
    return False, f"git grep failed for token {token!r}: {err.strip()}"


def analyze_operational_readiness(repo_path: Path, warnings: List[str]) -> OperationalReadinessStats:
    health_doc = repo_path / "docs" / "health_endpoint.md"
    health_doc_exists = health_doc.exists() and health_doc.is_file() and health_doc.stat().st_size > 0

    status_present: List[str] = []
    status_missing: List[str] = []
    for field in REQUIRED_STATUS_FIELDS:
        exists, error = token_exists_in_repo(repo_path, field)
        if error:
            warnings.append(error)
        if exists:
            status_present.append(field)
        else:
            status_missing.append(field)

    metrics_present: List[str] = []
    metrics_missing: List[str] = []
    for metric in REQUIRED_ALERT_METRICS:
        exists, error = token_exists_in_repo(repo_path, metric)
        if error:
            warnings.append(error)
        if exists:
            metrics_present.append(metric)
        else:
            metrics_missing.append(metric)

    return OperationalReadinessStats(
        health_doc_exists=health_doc_exists,
        required_status_fields_present=len(status_present),
        required_status_fields_total=len(REQUIRED_STATUS_FIELDS),
        missing_required_status_fields=status_missing,
        required_alert_metrics_present=len(metrics_present),
        required_alert_metrics_total=len(REQUIRED_ALERT_METRICS),
        missing_required_alert_metrics=metrics_missing,
    )


def gather_diff_stats(repo_path: Path, base: str, ref: str) -> Tuple[Optional[str], Optional[int]]:
    try:
        shortstat = git_read(repo_path, ["diff", "--shortstat", f"{base}..{ref}"])
        changed_raw = git_read(repo_path, ["diff", "--name-only", f"{base}..{ref}"])
        changed_files = len([line for line in changed_raw.splitlines() if line.strip()])
        return shortstat if shortstat else "no diff", changed_files
    except RuntimeError:
        return None, None


def collect_repo_result(
    name: str,
    repo_path: Path,
    ref: str,
    base_ref: Optional[str],
    run_meta_test: bool,
    run_quick_verify: bool,
    run_full_verify: bool,
    scenario_cmd: Optional[str],
    flaky_runs: int,
    flaky_cmd: Optional[str],
    run_dir: Path,
) -> RepoResult:
    if not repo_path.exists():
        raise RuntimeError(f"repo path does not exist: {repo_path}")

    warnings: List[str] = []
    snapshot = checkout_ref_worktree(repo_path, ref)
    active_repo = snapshot.path
    try:
        head_branch = git_read(active_repo, ["rev-parse", "--abbrev-ref", "HEAD"])
        head_sha = git_read(active_repo, ["rev-parse", "HEAD"])
        resolved_ref_sha = snapshot.resolved_ref_sha
        is_ref_head = snapshot.is_ref_head
        status_lines = git_read(active_repo, ["status", "--porcelain"]).splitlines()
        dirty_files = len(status_lines)

        required_all, required_any_of, required_source = parse_required_evidence(active_repo)
        all_required_paths = set(required_all)
        for group in required_any_of:
            all_required_paths.update(group)
        file_checks = [file_check(active_repo, path) for path in sorted(all_required_paths)]
        file_checks_by_path = {check.path: check for check in file_checks}
        missing_required_all = [
            path
            for path in required_all
            if not (
                path in file_checks_by_path
                and file_checks_by_path[path].exists
                and file_checks_by_path[path].non_empty
            )
        ]
        required_all_ok = len(required_all) - len(missing_required_all)

        failed_any_of: List[List[str]] = []
        for group in required_any_of:
            checks = [file_checks_by_path[path] for path in group if path in file_checks_by_path]
            if not any(check.exists and check.non_empty for check in checks):
                failed_any_of.append(group)

        required_any_of_ok = len(required_any_of) - len(failed_any_of)

        determinism_path = (
            active_repo / "evidence" / "phase1" / "determinism" / "intent_hashes.txt"
        )
        traceability_path = (
            active_repo / "evidence" / "phase1" / "traceability" / "sample_rejection_log.txt"
        )
        config_path = (
            active_repo
            / "evidence"
            / "phase1"
            / "config_fail_closed"
            / "missing_keys_matrix.json"
        )

        determinism_line_count = count_non_empty_lines(determinism_path)
        determinism_unique_hashes = 0
        if determinism_path.exists():
            lines = [
                line.strip()
                for line in determinism_path.read_text(encoding="utf-8", errors="replace").splitlines()
                if line.strip()
            ]
            determinism_unique_hashes = len(set(lines))

        traceability_line_count = count_non_empty_lines(traceability_path)
        traceability_unique_intent_ids = count_unique_intent_ids(traceability_path)
        config_entries, config_pass, config_fail = analyze_config_matrix(config_path)
        prd_items = read_prd_items(active_repo)
        prd_phase1 = analyze_phase1_prd(prd_items)
        traceability = analyze_traceability(active_repo, prd_items)
        operational_readiness = analyze_operational_readiness(active_repo, warnings)

        logs_dir = run_dir / name / "logs"
        meta_test_result: Optional[CommandResult] = None
        verify_result: Optional[CommandResult] = None
        verify_full_result: Optional[CommandResult] = None
        scenario_result: Optional[CommandResult] = None
        verify_gate_summary = VerifyGateSummary(gate_headers=[], first_failure="", failure_lines=[])
        verify_full_gate_summary = VerifyGateSummary(
            gate_headers=[], first_failure="", failure_lines=[]
        )
        verify_artifacts_latest = parse_verify_artifacts(active_repo)
        verify_artifacts_quick: Optional[VerifyArtifactsSummary] = None
        verify_artifacts_full: Optional[VerifyArtifactsSummary] = None
        flakiness: Optional[FlakinessSummary] = None
        scenario_behavior = ScenarioBehaviorSummary(
            reason_codes=[],
            status_fields_seen=[],
            dispatch_counts=[],
            rejection_lines=0,
        )

        if run_meta_test:
            meta_script = active_repo / "tools" / "phase1_meta_test.py"
            if meta_script.exists():
                meta_test_result = run_named_command(
                    "phase1_meta_test",
                    ["python3", str(meta_script)],
                    repo_path=active_repo,
                    logs_dir=logs_dir,
                )
            else:
                warnings.append("meta test skipped: tools/phase1_meta_test.py not found")

        if run_quick_verify:
            verify_script = active_repo / "plans" / "verify.sh"
            if verify_script.exists():
                verify_result = run_named_command(
                    "verify_quick",
                    ["./plans/verify.sh", "quick"],
                    repo_path=active_repo,
                    logs_dir=logs_dir,
                )
                verify_gate_summary = analyze_verify_quick_log(Path(verify_result.log_path))
                quick_run_id = extract_verify_run_id_from_log(Path(verify_result.log_path))
                verify_artifacts_quick = parse_verify_artifacts(active_repo, run_id=quick_run_id)
                if quick_run_id and verify_artifacts_quick.run_id != quick_run_id:
                    warnings.append(
                        f"quick verify artifacts for run_id {quick_run_id!r} not found; used latest run {verify_artifacts_quick.run_id!r}"
                    )
            else:
                warnings.append("quick verify skipped: plans/verify.sh not found")

        if run_full_verify:
            verify_script = active_repo / "plans" / "verify.sh"
            if verify_script.exists():
                verify_full_result = run_named_command(
                    "verify_full",
                    ["./plans/verify.sh", "full"],
                    repo_path=active_repo,
                    logs_dir=logs_dir,
                )
                verify_full_gate_summary = analyze_verify_quick_log(
                    Path(verify_full_result.log_path)
                )
                full_run_id = extract_verify_run_id_from_log(Path(verify_full_result.log_path))
                verify_artifacts_full = parse_verify_artifacts(active_repo, run_id=full_run_id)
                if full_run_id and verify_artifacts_full.run_id != full_run_id:
                    warnings.append(
                        f"full verify artifacts for run_id {full_run_id!r} not found; used latest run {verify_artifacts_full.run_id!r}"
                    )
            else:
                warnings.append("full verify skipped: plans/verify.sh not found")

        if scenario_cmd:
            scenario_result = run_named_command(
                "scenario",
                ["bash", "-lc", scenario_cmd],
                repo_path=active_repo,
                logs_dir=logs_dir,
            )
            scenario_behavior = analyze_scenario_behavior(Path(scenario_result.log_path))

        if flaky_runs > 0:
            cmd_text = (flaky_cmd or "").strip()
            if not cmd_text:
                if scenario_cmd:
                    cmd_text = scenario_cmd
                else:
                    cmd_text = "./plans/verify.sh quick"
            flakiness = run_flakiness_series(
                repo_path=active_repo,
                logs_dir=logs_dir,
                command_text=cmd_text,
                runs=flaky_runs,
            )

        # Keep "latest artifact" reporting authoritative when this invocation
        # produced new verify artifacts.
        if run_quick_verify or run_full_verify:
            verify_artifacts_latest = parse_verify_artifacts(active_repo)

        diff_shortstat: Optional[str] = None
        diff_changed_files: Optional[int] = None
        if base_ref:
            diff_shortstat, diff_changed_files = gather_diff_stats(
                active_repo, base_ref, resolved_ref_sha
            )
            if diff_shortstat is None:
                warnings.append(f"diff stats unavailable for base ref {base_ref!r}")

        blockers = (
            len(missing_required_all)
            + len(failed_any_of)
            + (1 if meta_test_result and meta_test_result.exit_code != 0 else 0)
            + (1 if verify_result and verify_result.exit_code != 0 else 0)
            + (1 if verify_full_result and verify_full_result.exit_code != 0 else 0)
            + (1 if scenario_result and scenario_result.exit_code != 0 else 0)
        )

        return RepoResult(
            name=name,
            path=str(repo_path),
            analysis_path=str(active_repo),
            ref=ref,
            head_branch=head_branch,
            head_sha=head_sha,
            resolved_ref_sha=resolved_ref_sha,
            is_ref_head=is_ref_head,
            dirty_files=dirty_files,
            required_source=required_source,
            required_all=required_all,
            required_any_of=required_any_of,
            required_all_ok=required_all_ok,
            required_all_total=len(required_all),
            required_any_of_ok=required_any_of_ok,
            required_any_of_total=len(required_any_of),
            missing_required_all=missing_required_all,
            failed_any_of=failed_any_of,
            file_checks=file_checks,
            determinism_line_count=determinism_line_count,
            determinism_unique_hashes=determinism_unique_hashes,
            traceability_line_count=traceability_line_count,
            traceability_unique_intent_ids=traceability_unique_intent_ids,
            config_matrix_entries=config_entries,
            config_matrix_pass=config_pass,
            config_matrix_fail=config_fail,
            verify_gate_summary=verify_gate_summary,
            prd_phase1=prd_phase1,
            traceability=traceability,
            operational_readiness=operational_readiness,
            verify_full=verify_full_result,
            verify_full_gate_summary=verify_full_gate_summary,
            verify_artifacts_latest=verify_artifacts_latest,
            verify_artifacts_quick=verify_artifacts_quick,
            verify_artifacts_full=verify_artifacts_full,
            flakiness=flakiness,
            scenario_behavior=scenario_behavior,
            meta_test=meta_test_result,
            verify_quick=verify_result,
            scenario=scenario_result,
            diff_shortstat=diff_shortstat,
            diff_changed_files=diff_changed_files,
            blockers=blockers,
            warnings=warnings,
        )
    finally:
        if snapshot:
            cleanup_ref_worktree(repo_path, snapshot, warnings)


def command_status(result: Optional[CommandResult]) -> str:
    if result is None:
        return "not run"
    if result.exit_code == 0:
        return f"pass ({result.elapsed_s:.2f}s)"
    return f"FAIL ({result.elapsed_s:.2f}s)"


def render_evidence_cell(check: Optional[FileCheck]) -> str:
    if check is None:
        return "missing"
    if check.exists and check.non_empty:
        return "ok"
    if check.exists and not check.non_empty:
        return "empty"
    return "missing"


def common_paths(a: RepoResult, b: RepoResult) -> List[str]:
    paths = set(a.required_all) | set(b.required_all)
    for group in a.required_any_of + b.required_any_of:
        paths.update(group)
    return sorted(paths)


def safe_ratio(numer: int, denom: int) -> float:
    if denom <= 0:
        return 1.0
    return max(0.0, min(1.0, float(numer) / float(denom)))


def parse_shortstat_loc(shortstat: Optional[str]) -> Optional[int]:
    if not shortstat:
        return None
    ins_match = re.search(r"(\d+)\s+insertion", shortstat)
    del_match = re.search(r"(\d+)\s+deletion", shortstat)
    insertions = int(ins_match.group(1)) if ins_match else 0
    deletions = int(del_match.group(1)) if del_match else 0
    if insertions == 0 and deletions == 0 and "changed" not in shortstat:
        return None
    return insertions + deletions


def pair_score_higher_better(
    a_value: Optional[float],
    b_value: Optional[float],
    missing_score: float = 40.0,
) -> Tuple[float, float]:
    if a_value is None and b_value is None:
        return 100.0, 100.0
    if a_value is None:
        return missing_score, 100.0
    if b_value is None:
        return 100.0, missing_score
    if abs(a_value - b_value) < 1e-12:
        return 100.0, 100.0
    high = max(a_value, b_value)
    if high <= 0:
        return 100.0, 100.0
    a_score = max(0.0, min(100.0, (a_value / high) * 100.0))
    b_score = max(0.0, min(100.0, (b_value / high) * 100.0))
    return a_score, b_score


def pair_score_lower_better(
    a_value: Optional[float],
    b_value: Optional[float],
    missing_score: float = 40.0,
) -> Tuple[float, float]:
    if a_value is None and b_value is None:
        return 100.0, 100.0
    if a_value is None:
        return missing_score, 100.0
    if b_value is None:
        return 100.0, missing_score
    if abs(a_value - b_value) < 1e-12:
        return 100.0, 100.0
    low = min(a_value, b_value)
    if low <= 0:
        # One side can be exactly zero (best), keep pair deterministic.
        return (100.0 if a_value <= b_value else 0.0, 100.0 if b_value <= a_value else 0.0)
    a_score = max(0.0, min(100.0, (low / a_value) * 100.0))
    b_score = max(0.0, min(100.0, (low / b_value) * 100.0))
    return a_score, b_score


def normalize_weights(
    correctness: float,
    performance: float,
    maintainability: float,
) -> Tuple[float, float, float]:
    total = correctness + performance + maintainability
    if total <= 0:
        raise ValueError("weight sum must be > 0")
    return correctness / total, performance / total, maintainability / total


def compute_weighted_decision(
    a: RepoResult,
    b: RepoResult,
    weight_correctness: float,
    weight_performance: float,
    weight_maintainability: float,
) -> Dict[str, object]:
    wc, wp, wm = normalize_weights(weight_correctness, weight_performance, weight_maintainability)
    notes: List[str] = []

    a_evidence_ratio = safe_ratio(a.required_all_ok, a.required_all_total)
    b_evidence_ratio = safe_ratio(b.required_all_ok, b.required_all_total)
    a_prd_pass_ratio = safe_ratio(a.prd_phase1.passed_stories, a.prd_phase1.total_stories)
    b_prd_pass_ratio = safe_ratio(b.prd_phase1.passed_stories, b.prd_phase1.total_stories)
    a_status_ratio = safe_ratio(
        a.operational_readiness.required_status_fields_present,
        a.operational_readiness.required_status_fields_total,
    )
    b_status_ratio = safe_ratio(
        b.operational_readiness.required_status_fields_present,
        b.operational_readiness.required_status_fields_total,
    )
    a_enforcing_ratio = safe_ratio(
        a.traceability.stories_with_enforcing_ats,
        a.traceability.stories_with_contract_refs,
    )
    b_enforcing_ratio = safe_ratio(
        b.traceability.stories_with_enforcing_ats,
        b.traceability.stories_with_contract_refs,
    )

    blockers_a, blockers_b = pair_score_lower_better(float(a.blockers), float(b.blockers))
    evidence_a, evidence_b = pair_score_higher_better(a_evidence_ratio, b_evidence_ratio)
    prd_a, prd_b = pair_score_higher_better(a_prd_pass_ratio, b_prd_pass_ratio)
    status_a, status_b = pair_score_higher_better(a_status_ratio, b_status_ratio)
    enforcing_a, enforcing_b = pair_score_higher_better(a_enforcing_ratio, b_enforcing_ratio)

    correctness_a = (
        0.35 * blockers_a
        + 0.15 * evidence_a
        + 0.20 * prd_a
        + 0.15 * status_a
        + 0.15 * enforcing_a
    )
    correctness_b = (
        0.35 * blockers_b
        + 0.15 * evidence_b
        + 0.20 * prd_b
        + 0.15 * status_b
        + 0.15 * enforcing_b
    )

    a_scenario_elapsed = (
        a.scenario.elapsed_s if a.scenario is not None and a.scenario.exit_code == 0 else None
    )
    b_scenario_elapsed = (
        b.scenario.elapsed_s if b.scenario is not None and b.scenario.exit_code == 0 else None
    )
    a_flaky_avg = (
        a.flakiness.avg_elapsed_s
        if a.flakiness is not None and a.flakiness.success_runs == a.flakiness.runs
        else None
    )
    b_flaky_avg = (
        b.flakiness.avg_elapsed_s
        if b.flakiness is not None and b.flakiness.success_runs == b.flakiness.runs
        else None
    )
    a_flaky_spread = (
        (a.flakiness.max_elapsed_s - a.flakiness.min_elapsed_s) if a.flakiness is not None else None
    )
    b_flaky_spread = (
        (b.flakiness.max_elapsed_s - b.flakiness.min_elapsed_s) if b.flakiness is not None else None
    )
    a_scenario_pass = (
        1.0 if a.scenario is not None and a.scenario.exit_code == 0 else (0.0 if a.scenario is not None else None)
    )
    b_scenario_pass = (
        1.0 if b.scenario is not None and b.scenario.exit_code == 0 else (0.0 if b.scenario is not None else None)
    )

    scenario_time_a, scenario_time_b = pair_score_lower_better(a_scenario_elapsed, b_scenario_elapsed)
    flaky_avg_a, flaky_avg_b = pair_score_lower_better(a_flaky_avg, b_flaky_avg)
    flaky_spread_a, flaky_spread_b = pair_score_lower_better(a_flaky_spread, b_flaky_spread)
    scenario_pass_a, scenario_pass_b = pair_score_higher_better(a_scenario_pass, b_scenario_pass)

    performance_a = (
        0.45 * scenario_time_a
        + 0.30 * flaky_avg_a
        + 0.15 * flaky_spread_a
        + 0.10 * scenario_pass_a
    )
    performance_b = (
        0.45 * scenario_time_b
        + 0.30 * flaky_avg_b
        + 0.15 * flaky_spread_b
        + 0.10 * scenario_pass_b
    )

    a_loc_churn = parse_shortstat_loc(a.diff_shortstat)
    b_loc_churn = parse_shortstat_loc(b.diff_shortstat)
    a_changed_files = float(a.diff_changed_files) if a.diff_changed_files is not None else None
    b_changed_files = float(b.diff_changed_files) if b.diff_changed_files is not None else None
    a_missing_enforcing = float(a.traceability.stories_missing_enforcing_ats)
    b_missing_enforcing = float(b.traceability.stories_missing_enforcing_ats)
    a_warning_count = float(len(a.warnings))
    b_warning_count = float(len(b.warnings))

    changed_files_a, changed_files_b = pair_score_lower_better(a_changed_files, b_changed_files)
    loc_churn_a, loc_churn_b = pair_score_lower_better(
        float(a_loc_churn) if a_loc_churn is not None else None,
        float(b_loc_churn) if b_loc_churn is not None else None,
    )
    missing_enforcing_a, missing_enforcing_b = pair_score_lower_better(
        a_missing_enforcing, b_missing_enforcing
    )
    warning_count_a, warning_count_b = pair_score_lower_better(a_warning_count, b_warning_count)

    maintainability_a = (
        0.40 * changed_files_a
        + 0.30 * loc_churn_a
        + 0.20 * missing_enforcing_a
        + 0.10 * warning_count_a
    )
    maintainability_b = (
        0.40 * changed_files_b
        + 0.30 * loc_churn_b
        + 0.20 * missing_enforcing_b
        + 0.10 * warning_count_b
    )

    if (
        a_changed_files is not None
        and b_changed_files is not None
        and min(a_changed_files, b_changed_files) <= 1.0
        and max(a_changed_files, b_changed_files) >= 10.0
    ):
        notes.append(
            "Large changed-file asymmetry detected; verify both refs represent equivalent Phase1 scope before final selection."
        )

    total_a = wc * correctness_a + wp * performance_a + wm * maintainability_a
    total_b = wc * correctness_b + wp * performance_b + wm * maintainability_b
    margin = abs(total_a - total_b)
    if margin < 0.01:
        winner = "tie"
    else:
        winner = "repo_a" if total_a > total_b else "repo_b"

    return {
        "weights": {
            "correctness_safety": round(weight_correctness, 3),
            "performance": round(weight_performance, 3),
            "maintainability": round(weight_maintainability, 3),
            "normalized_correctness_safety": round(wc, 6),
            "normalized_performance": round(wp, 6),
            "normalized_maintainability": round(wm, 6),
        },
        "repo_a": {
            "correctness_safety": round(correctness_a, 3),
            "performance": round(performance_a, 3),
            "maintainability": round(maintainability_a, 3),
            "total": round(total_a, 3),
        },
        "repo_b": {
            "correctness_safety": round(correctness_b, 3),
            "performance": round(performance_b, 3),
            "maintainability": round(maintainability_b, 3),
            "total": round(total_b, 3),
        },
        "winner": winner,
        "margin": round(margin, 3),
        "notes": notes,
    }


def build_report_markdown(
    a: RepoResult,
    b: RepoResult,
    run_id: str,
    weighted_decision: Optional[Dict[str, object]] = None,
) -> str:
    path_to_a = {check.path: check for check in a.file_checks}
    path_to_b = {check.path: check for check in b.file_checks}
    lines: List[str] = []
    lines.append("# Phase 1 Cross-Repo Comparison")
    lines.append("")
    lines.append(f"- Run ID: `{run_id}`")
    lines.append(f"- Generated (UTC): `{datetime.now(timezone.utc).isoformat()}`")
    lines.append(f"- Repo A: `{a.name}` at `{a.path}`")
    lines.append(f"- Repo A analysis snapshot: `{a.analysis_path}`")
    lines.append(f"- Repo B: `{b.name}` at `{b.path}`")
    lines.append(f"- Repo B analysis snapshot: `{b.analysis_path}`")
    lines.append("")
    lines.append("## Snapshot")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(f"| branch | `{a.head_branch}` | `{b.head_branch}` |")
    lines.append(f"| ref | `{a.ref}` | `{b.ref}` |")
    lines.append(f"| ref sha | `{a.resolved_ref_sha}` | `{b.resolved_ref_sha}` |")
    lines.append(f"| dirty files | `{a.dirty_files}` | `{b.dirty_files}` |")
    lines.append(
        f"| required evidence coverage | `{a.required_all_ok}/{a.required_all_total}` | `{b.required_all_ok}/{b.required_all_total}` |"
    )
    lines.append(
        f"| any-of groups satisfied | `{a.required_any_of_ok}/{a.required_any_of_total}` | `{b.required_any_of_ok}/{b.required_any_of_total}` |"
    )
    lines.append(f"| phase1_meta_test | `{command_status(a.meta_test)}` | `{command_status(b.meta_test)}` |")
    lines.append(
        f"| verify quick | `{command_status(a.verify_quick)}` | `{command_status(b.verify_quick)}` |"
    )
    lines.append(
        f"| verify full | `{command_status(a.verify_full)}` | `{command_status(b.verify_full)}` |"
    )
    lines.append(f"| scenario cmd | `{command_status(a.scenario)}` | `{command_status(b.scenario)}` |")
    lines.append(
        f"| flakiness runs | `{a.flakiness.runs if a.flakiness else 0}` | `{b.flakiness.runs if b.flakiness else 0}` |"
    )
    lines.append(f"| blockers | `{a.blockers}` | `{b.blockers}` |")
    lines.append("")
    lines.append("## Outcome Signals")
    lines.append("")
    lines.append("| Signal | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| determinism file non-empty lines | `{a.determinism_line_count}` | `{b.determinism_line_count}` |"
    )
    lines.append(
        f"| determinism unique hashes | `{a.determinism_unique_hashes}` | `{b.determinism_unique_hashes}` |"
    )
    lines.append(
        f"| traceability log non-empty lines | `{a.traceability_line_count}` | `{b.traceability_line_count}` |"
    )
    lines.append(
        f"| traceability unique intent_id count | `{a.traceability_unique_intent_ids}` | `{b.traceability_unique_intent_ids}` |"
    )
    lines.append(
        f"| config matrix status entries | `{a.config_matrix_entries}` | `{b.config_matrix_entries}` |"
    )
    lines.append(f"| config matrix PASS statuses | `{a.config_matrix_pass}` | `{b.config_matrix_pass}` |")
    lines.append(f"| config matrix FAIL statuses | `{a.config_matrix_fail}` | `{b.config_matrix_fail}` |")
    lines.append("")
    lines.append("## Verify Gate Parity")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| verify gate headers detected | `{len(a.verify_gate_summary.gate_headers)}` | `{len(b.verify_gate_summary.gate_headers)}` |"
    )
    lines.append(
        f"| first verify failure | `{a.verify_gate_summary.first_failure or 'n/a'}` | `{b.verify_gate_summary.first_failure or 'n/a'}` |"
    )
    shared_gates = sorted(set(a.verify_gate_summary.gate_headers) & set(b.verify_gate_summary.gate_headers))
    only_a_gates = sorted(set(a.verify_gate_summary.gate_headers) - set(b.verify_gate_summary.gate_headers))
    only_b_gates = sorted(set(b.verify_gate_summary.gate_headers) - set(a.verify_gate_summary.gate_headers))
    lines.append(f"| shared verify gates | `{len(shared_gates)}` | `{len(shared_gates)}` |")
    lines.append(f"| gates only in Repo A | `{len(only_a_gates)}` | `n/a` |")
    lines.append(f"| gates only in Repo B | `n/a` | `{len(only_b_gates)}` |")
    if only_a_gates:
        lines.append(f"- Repo A-only gates: `{', '.join(only_a_gates)}`")
    if only_b_gates:
        lines.append(f"- Repo B-only gates: `{', '.join(only_b_gates)}`")
    if a.verify_gate_summary.failure_lines:
        lines.append(f"- Repo A failure lines: `{'; '.join(a.verify_gate_summary.failure_lines[:3])}`")
    if b.verify_gate_summary.failure_lines:
        lines.append(f"- Repo B failure lines: `{'; '.join(b.verify_gate_summary.failure_lines[:3])}`")

    lines.append("")
    lines.append("## Verify Full Gate Parity")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| full verify gate headers detected | `{len(a.verify_full_gate_summary.gate_headers)}` | `{len(b.verify_full_gate_summary.gate_headers)}` |"
    )
    lines.append(
        f"| first full verify failure | `{a.verify_full_gate_summary.first_failure or 'n/a'}` | `{b.verify_full_gate_summary.first_failure or 'n/a'}` |"
    )
    shared_full = sorted(
        set(a.verify_full_gate_summary.gate_headers) & set(b.verify_full_gate_summary.gate_headers)
    )
    only_a_full = sorted(
        set(a.verify_full_gate_summary.gate_headers) - set(b.verify_full_gate_summary.gate_headers)
    )
    only_b_full = sorted(
        set(b.verify_full_gate_summary.gate_headers) - set(a.verify_full_gate_summary.gate_headers)
    )
    lines.append(f"| shared full verify gates | `{len(shared_full)}` | `{len(shared_full)}` |")
    lines.append(f"| full gates only in Repo A | `{len(only_a_full)}` | `n/a` |")
    lines.append(f"| full gates only in Repo B | `n/a` | `{len(only_b_full)}` |")
    if only_a_full:
        lines.append(f"- Repo A-only full gates: `{', '.join(only_a_full)}`")
    if only_b_full:
        lines.append(f"- Repo B-only full gates: `{', '.join(only_b_full)}`")
    if a.verify_full_gate_summary.failure_lines:
        lines.append(
            f"- Repo A full verify failure lines: `{'; '.join(a.verify_full_gate_summary.failure_lines[:3])}`"
        )
    if b.verify_full_gate_summary.failure_lines:
        lines.append(
            f"- Repo B full verify failure lines: `{'; '.join(b.verify_full_gate_summary.failure_lines[:3])}`"
        )

    lines.append("")
    lines.append("## Verify Artifact Gate+Timing Parity")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| latest artifact run id | `{a.verify_artifacts_latest.run_id or 'n/a'}` | `{b.verify_artifacts_latest.run_id or 'n/a'}` |"
    )
    lines.append(
        f"| latest artifact passing gates | `{a.verify_artifacts_latest.pass_gates}` | `{b.verify_artifacts_latest.pass_gates}` |"
    )
    lines.append(
        f"| latest artifact failing gates | `{a.verify_artifacts_latest.fail_gates}` | `{b.verify_artifacts_latest.fail_gates}` |"
    )
    lines.append(
        f"| latest artifact gates with time | `{len(a.verify_artifacts_latest.gate_time_s)}` | `{len(b.verify_artifacts_latest.gate_time_s)}` |"
    )
    shared_latest_gates = sorted(
        set(a.verify_artifacts_latest.gate_rc.keys()) & set(b.verify_artifacts_latest.gate_rc.keys())
    )
    lines.append(f"| shared latest artifact gates | `{len(shared_latest_gates)}` | `{len(shared_latest_gates)}` |")
    rc_mismatch = sum(
        1
        for gate in shared_latest_gates
        if a.verify_artifacts_latest.gate_rc.get(gate) != b.verify_artifacts_latest.gate_rc.get(gate)
    )
    lines.append(f"| shared gates with different rc | `{rc_mismatch}` | `{rc_mismatch}` |")
    shared_timed = [
        gate
        for gate in shared_latest_gates
        if gate in a.verify_artifacts_latest.gate_time_s and gate in b.verify_artifacts_latest.gate_time_s
    ]
    if shared_timed:
        avg_abs_delta = sum(
            abs(a.verify_artifacts_latest.gate_time_s[gate] - b.verify_artifacts_latest.gate_time_s[gate])
            for gate in shared_timed
        ) / len(shared_timed)
        lines.append(
            f"| avg abs time delta over shared timed gates (s) | `{avg_abs_delta:.3f}` | `{avg_abs_delta:.3f}` |"
        )
    if a.verify_artifacts_quick:
        lines.append(
            f"- Repo A quick-run artifact: `{a.verify_artifacts_quick.run_id}` ({a.verify_artifacts_quick.pass_gates} pass / {a.verify_artifacts_quick.fail_gates} fail)"
        )
    if b.verify_artifacts_quick:
        lines.append(
            f"- Repo B quick-run artifact: `{b.verify_artifacts_quick.run_id}` ({b.verify_artifacts_quick.pass_gates} pass / {b.verify_artifacts_quick.fail_gates} fail)"
        )
    if a.verify_artifacts_full:
        lines.append(
            f"- Repo A full-run artifact: `{a.verify_artifacts_full.run_id}` ({a.verify_artifacts_full.pass_gates} pass / {a.verify_artifacts_full.fail_gates} fail)"
        )
    if b.verify_artifacts_full:
        lines.append(
            f"- Repo B full-run artifact: `{b.verify_artifacts_full.run_id}` ({b.verify_artifacts_full.pass_gates} pass / {b.verify_artifacts_full.fail_gates} fail)"
        )

    lines.append("")
    lines.append("## Phase 1 PRD Completion")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(f"| Phase 1 stories | `{a.prd_phase1.total_stories}` | `{b.prd_phase1.total_stories}` |")
    lines.append(f"| Phase 1 stories passed | `{a.prd_phase1.passed_stories}` | `{b.prd_phase1.passed_stories}` |")
    lines.append(
        f"| Phase 1 stories remaining | `{a.prd_phase1.remaining_stories}` | `{b.prd_phase1.remaining_stories}` |"
    )
    lines.append(
        f"| needs_human_decision stories | `{a.prd_phase1.needs_human_decision_stories}` | `{b.prd_phase1.needs_human_decision_stories}` |"
    )
    lines.append(
        f"| stories with verify[] commands | `{a.prd_phase1.stories_with_verify}` | `{b.prd_phase1.stories_with_verify}` |"
    )
    lines.append(
        f"| stories with observability fields | `{a.prd_phase1.stories_with_observability}` | `{b.prd_phase1.stories_with_observability}` |"
    )
    if a.prd_phase1.missing_pass_story_ids:
        lines.append(
            f"- Repo A missing pass stories: `{', '.join(a.prd_phase1.missing_pass_story_ids[:12])}`"
        )
    if b.prd_phase1.missing_pass_story_ids:
        lines.append(
            f"- Repo B missing pass stories: `{', '.join(b.prd_phase1.missing_pass_story_ids[:12])}`"
        )

    lines.append("")
    lines.append("## Phase 1 Traceability")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| stories with contract refs | `{a.traceability.stories_with_contract_refs}` | `{b.traceability.stories_with_contract_refs}` |"
    )
    lines.append(
        f"| stories missing contract refs | `{a.traceability.stories_missing_contract_refs}` | `{b.traceability.stories_missing_contract_refs}` |"
    )
    lines.append(
        f"| stories with enforcing_contract_ats | `{a.traceability.stories_with_enforcing_ats}` | `{b.traceability.stories_with_enforcing_ats}` |"
    )
    lines.append(
        f"| stories missing enforcing_contract_ats | `{a.traceability.stories_missing_enforcing_ats}` | `{b.traceability.stories_missing_enforcing_ats}` |"
    )
    lines.append(
        f"| unique AT refs seen | `{len(a.traceability.unique_contract_at_refs)}` | `{len(b.traceability.unique_contract_at_refs)}` |"
    )
    lines.append(
        f"| unknown AT refs vs CONTRACT | `{len(a.traceability.unknown_contract_at_refs)}` | `{len(b.traceability.unknown_contract_at_refs)}` |"
    )
    lines.append(
        f"| unknown Anchor refs vs CONTRACT | `{len(a.traceability.unknown_anchor_refs)}` | `{len(b.traceability.unknown_anchor_refs)}` |"
    )
    lines.append(
        f"| unknown VR refs vs CONTRACT | `{len(a.traceability.unknown_vr_refs)}` | `{len(b.traceability.unknown_vr_refs)}` |"
    )
    if a.traceability.missing_enforcing_ats_story_ids:
        lines.append(
            f"- Repo A stories missing enforcing AT refs: `{', '.join(a.traceability.missing_enforcing_ats_story_ids[:12])}`"
        )
    if b.traceability.missing_enforcing_ats_story_ids:
        lines.append(
            f"- Repo B stories missing enforcing AT refs: `{', '.join(b.traceability.missing_enforcing_ats_story_ids[:12])}`"
        )

    lines.append("")
    lines.append("## Operational Readiness Signals")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| health endpoint doc present | `{'yes' if a.operational_readiness.health_doc_exists else 'no'}` | `{'yes' if b.operational_readiness.health_doc_exists else 'no'}` |"
    )
    lines.append(
        f"| required status fields present | `{a.operational_readiness.required_status_fields_present}/{a.operational_readiness.required_status_fields_total}` | `{b.operational_readiness.required_status_fields_present}/{b.operational_readiness.required_status_fields_total}` |"
    )
    lines.append(
        f"| required alert metrics present | `{a.operational_readiness.required_alert_metrics_present}/{a.operational_readiness.required_alert_metrics_total}` | `{b.operational_readiness.required_alert_metrics_present}/{b.operational_readiness.required_alert_metrics_total}` |"
    )
    if a.operational_readiness.missing_required_status_fields:
        lines.append(
            f"- Repo A missing status fields: `{', '.join(a.operational_readiness.missing_required_status_fields)}`"
        )
    if b.operational_readiness.missing_required_status_fields:
        lines.append(
            f"- Repo B missing status fields: `{', '.join(b.operational_readiness.missing_required_status_fields)}`"
        )
    if a.operational_readiness.missing_required_alert_metrics:
        lines.append(
            f"- Repo A missing alert metrics: `{', '.join(a.operational_readiness.missing_required_alert_metrics[:8])}`"
        )
    if b.operational_readiness.missing_required_alert_metrics:
        lines.append(
            f"- Repo B missing alert metrics: `{', '.join(b.operational_readiness.missing_required_alert_metrics[:8])}`"
        )

    lines.append("")
    lines.append("## Flakiness & Stability")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(f"| flakiness command runs | `{a.flakiness.runs if a.flakiness else 0}` | `{b.flakiness.runs if b.flakiness else 0}` |")
    lines.append(f"| flakiness success runs | `{a.flakiness.success_runs if a.flakiness else 0}` | `{b.flakiness.success_runs if b.flakiness else 0}` |")
    lines.append(f"| flakiness failed runs | `{a.flakiness.fail_runs if a.flakiness else 0}` | `{b.flakiness.fail_runs if b.flakiness else 0}` |")
    lines.append(f"| flakiness exit code set | `{a.flakiness.exit_codes_seen if a.flakiness else []}` | `{b.flakiness.exit_codes_seen if b.flakiness else []}` |")
    lines.append(
        f"| flakiness avg elapsed (s) | `{a.flakiness.avg_elapsed_s if a.flakiness else 0.0}` | `{b.flakiness.avg_elapsed_s if b.flakiness else 0.0}` |"
    )
    lines.append(
        f"| flakiness min..max elapsed (s) | `{(str(a.flakiness.min_elapsed_s) + '..' + str(a.flakiness.max_elapsed_s)) if a.flakiness else '0..0'}` | `{(str(b.flakiness.min_elapsed_s) + '..' + str(b.flakiness.max_elapsed_s)) if b.flakiness else '0..0'}` |"
    )

    lines.append("")
    lines.append("## Scenario Behavioral Output Parity")
    lines.append("")
    lines.append("| Metric | Repo A | Repo B |")
    lines.append("|---|---:|---:|")
    lines.append(
        f"| scenario reason code count | `{len(a.scenario_behavior.reason_codes)}` | `{len(b.scenario_behavior.reason_codes)}` |"
    )
    lines.append(
        f"| scenario status fields seen | `{len(a.scenario_behavior.status_fields_seen)}` | `{len(b.scenario_behavior.status_fields_seen)}` |"
    )
    lines.append(
        f"| scenario dispatch count values seen | `{a.scenario_behavior.dispatch_counts}` | `{b.scenario_behavior.dispatch_counts}` |"
    )
    lines.append(
        f"| scenario rejection/blocked lines | `{a.scenario_behavior.rejection_lines}` | `{b.scenario_behavior.rejection_lines}` |"
    )
    shared_reason_codes = sorted(
        set(a.scenario_behavior.reason_codes) & set(b.scenario_behavior.reason_codes)
    )
    lines.append(f"| shared scenario reason codes | `{len(shared_reason_codes)}` | `{len(shared_reason_codes)}` |")
    only_a_reason = sorted(set(a.scenario_behavior.reason_codes) - set(b.scenario_behavior.reason_codes))
    only_b_reason = sorted(set(b.scenario_behavior.reason_codes) - set(a.scenario_behavior.reason_codes))
    if only_a_reason:
        lines.append(f"- Repo A-only scenario reason codes: `{', '.join(only_a_reason[:12])}`")
    if only_b_reason:
        lines.append(f"- Repo B-only scenario reason codes: `{', '.join(only_b_reason[:12])}`")
    lines.append("")
    lines.append("## Evidence File Comparison")
    lines.append("")
    lines.append("| Path | Repo A | Repo B | same sha256 |")
    lines.append("|---|---:|---:|---:|")
    for path in common_paths(a, b):
        check_a = path_to_a.get(path)
        check_b = path_to_b.get(path)
        if check_a is None:
            check_a = file_check_for_result(a, path)
        if check_b is None:
            check_b = file_check_for_result(b, path)
        same_hash = (
            "yes"
            if check_a.exists
            and check_b.exists
            and check_a.non_empty
            and check_b.non_empty
            and check_a.sha256 == check_b.sha256
            else "no"
        )
        lines.append(
            f"| `{path}` | `{render_evidence_cell(check_a)}` | `{render_evidence_cell(check_b)}` | `{same_hash}` |"
        )

    if a.diff_shortstat is not None or b.diff_shortstat is not None:
        lines.append("")
        lines.append("## Churn (Base→Ref)")
        lines.append("")
        lines.append("| Metric | Repo A | Repo B |")
        lines.append("|---|---:|---:|")
        lines.append(
            f"| diff shortstat | `{a.diff_shortstat or 'n/a'}` | `{b.diff_shortstat or 'n/a'}` |"
        )
        lines.append(
            f"| changed files | `{a.diff_changed_files if a.diff_changed_files is not None else 'n/a'}` | `{b.diff_changed_files if b.diff_changed_files is not None else 'n/a'}` |"
        )

    if weighted_decision:
        weights = weighted_decision.get("weights", {})
        repo_a_scores = weighted_decision.get("repo_a", {})
        repo_b_scores = weighted_decision.get("repo_b", {})
        winner = str(weighted_decision.get("winner", "tie"))
        margin = weighted_decision.get("margin", 0.0)
        notes = weighted_decision.get("notes", [])

        winner_label = "tie"
        if winner == "repo_a":
            winner_label = a.name
        elif winner == "repo_b":
            winner_label = b.name

        lines.append("")
        lines.append("## Weighted Decision (Auto)")
        lines.append("")
        lines.append("| Category | Weight | Repo A | Repo B |")
        lines.append("|---|---:|---:|---:|")
        lines.append(
            f"| correctness/safety | `{weights.get('correctness_safety', 0)}%` | `{repo_a_scores.get('correctness_safety', 0)}` | `{repo_b_scores.get('correctness_safety', 0)}` |"
        )
        lines.append(
            f"| performance | `{weights.get('performance', 0)}%` | `{repo_a_scores.get('performance', 0)}` | `{repo_b_scores.get('performance', 0)}` |"
        )
        lines.append(
            f"| maintainability | `{weights.get('maintainability', 0)}%` | `{repo_a_scores.get('maintainability', 0)}` | `{repo_b_scores.get('maintainability', 0)}` |"
        )
        lines.append(
            f"| total weighted score | `100%` | `{repo_a_scores.get('total', 0)}` | `{repo_b_scores.get('total', 0)}` |"
        )
        lines.append(f"- Winner: `{winner_label}` (margin `{margin}` points)")
        if isinstance(notes, list) and notes:
            for note in notes[:5]:
                lines.append(f"- Note: {note}")

    lines.append("")
    lines.append("## Warnings")
    lines.append("")
    warn_rows = []
    warn_rows.extend([f"- Repo A: {w}" for w in a.warnings])
    warn_rows.extend([f"- Repo B: {w}" for w in b.warnings])
    if warn_rows:
        lines.extend(warn_rows)
    else:
        lines.append("- none")

    lines.append("")
    lines.append("## Logs")
    lines.append("")
    for label, result in [
        ("Repo A meta test", a.meta_test),
        ("Repo B meta test", b.meta_test),
        ("Repo A verify quick", a.verify_quick),
        ("Repo B verify quick", b.verify_quick),
        ("Repo A verify full", a.verify_full),
        ("Repo B verify full", b.verify_full),
        ("Repo A scenario", a.scenario),
        ("Repo B scenario", b.scenario),
    ]:
        if result:
            lines.append(f"- {label}: `{result.log_path}`")
    if a.flakiness:
        lines.append(f"- Repo A flakiness logs: `{', '.join(a.flakiness.log_paths[:5])}`")
    if b.flakiness:
        lines.append(f"- Repo B flakiness logs: `{', '.join(b.flakiness.log_paths[:5])}`")

    lines.append("")
    lines.append("## Decision Rule")
    lines.append("")
    lines.append(
        "Pick the implementation with fewer blockers first; if tied, prefer green full/quick verify parity, then higher evidence and traceability coverage. Use flakiness, scenario behavior parity, churn, and timing as tie-breakers."
    )
    return "\n".join(lines) + "\n"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Compare Phase 1 outcomes between opus-trader and ralph repositories.",
    )
    parser.add_argument(
        "--opus",
        required=True,
        help="Path to opus-trader repo.",
    )
    parser.add_argument(
        "--ralph",
        required=True,
        help="Path to ralph repo.",
    )
    parser.add_argument("--opus-ref", default="HEAD", help="Git ref for opus snapshot (default: HEAD).")
    parser.add_argument("--ralph-ref", default="HEAD", help="Git ref for ralph snapshot (default: HEAD).")
    parser.add_argument(
        "--opus-base",
        default="",
        help="Optional base ref for churn stats in opus (e.g. origin/main).",
    )
    parser.add_argument(
        "--ralph-base",
        default="",
        help="Optional base ref for churn stats in ralph (e.g. origin/main).",
    )
    parser.add_argument(
        "--run-quick-verify",
        action="store_true",
        help="Run ./plans/verify.sh quick in each repo.",
    )
    parser.add_argument(
        "--run-quick-verify-opus",
        action="store_true",
        help="Run ./plans/verify.sh quick in opus only.",
    )
    parser.add_argument(
        "--run-quick-verify-ralph",
        action="store_true",
        help="Run ./plans/verify.sh quick in ralph only.",
    )
    parser.add_argument(
        "--run-full-verify",
        action="store_true",
        help="Run ./plans/verify.sh full in each repo (can be slow).",
    )
    parser.add_argument(
        "--run-full-verify-opus",
        action="store_true",
        help="Run ./plans/verify.sh full in opus only.",
    )
    parser.add_argument(
        "--run-full-verify-ralph",
        action="store_true",
        help="Run ./plans/verify.sh full in ralph only.",
    )
    parser.add_argument(
        "--skip-meta-test",
        action="store_true",
        help="Skip python3 tools/phase1_meta_test.py.",
    )
    parser.add_argument(
        "--scenario-cmd",
        default="",
        help="Optional command to run in both repos for apples-to-apples timing and pass/fail comparison.",
    )
    parser.add_argument(
        "--flaky-runs",
        type=int,
        default=0,
        help="Optional flakiness repetitions per repo (0 disables).",
    )
    parser.add_argument(
        "--flaky-cmd",
        default="",
        help="Command for flakiness runs. Defaults to --scenario-cmd when set, else ./plans/verify.sh quick.",
    )
    parser.add_argument(
        "--output",
        default="",
        help="Output markdown report path (default: artifacts/phase1_compare/<run_id>/report.md).",
    )
    parser.add_argument(
        "--weight-correctness",
        type=float,
        default=60.0,
        help="Weighted decision category weight for correctness/safety (default: 60).",
    )
    parser.add_argument(
        "--weight-performance",
        type=float,
        default=25.0,
        help="Weighted decision category weight for performance (default: 25).",
    )
    parser.add_argument(
        "--weight-maintainability",
        type=float,
        default=15.0,
        help="Weighted decision category weight for maintainability (default: 15).",
    )
    return parser.parse_args()


def default_run_dir() -> Path:
    run_id = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
    return Path("artifacts") / "phase1_compare" / run_id


def main() -> int:
    args = parse_args()
    run_dir = default_run_dir()
    if args.output:
        out_md = Path(args.output).resolve()
        run_dir = out_md.parent
    else:
        out_md = (run_dir / "report.md").resolve()
    out_json = (run_dir / "report.json").resolve()

    run_dir.mkdir(parents=True, exist_ok=True)
    run_id = run_dir.name

    opus_path = Path(args.opus).resolve()
    ralph_path = Path(args.ralph).resolve()
    run_quick_opus = args.run_quick_verify or args.run_quick_verify_opus
    run_quick_ralph = args.run_quick_verify or args.run_quick_verify_ralph
    run_full_opus = args.run_full_verify or args.run_full_verify_opus
    run_full_ralph = args.run_full_verify or args.run_full_verify_ralph

    try:
        opus = collect_repo_result(
            name="opus",
            repo_path=opus_path,
            ref=args.opus_ref,
            base_ref=args.opus_base.strip() or None,
            run_meta_test=not args.skip_meta_test,
            run_quick_verify=run_quick_opus,
            run_full_verify=run_full_opus,
            scenario_cmd=args.scenario_cmd.strip() or None,
            flaky_runs=max(0, args.flaky_runs),
            flaky_cmd=args.flaky_cmd.strip() or None,
            run_dir=run_dir,
        )
        ralph = collect_repo_result(
            name="ralph",
            repo_path=ralph_path,
            ref=args.ralph_ref,
            base_ref=args.ralph_base.strip() or None,
            run_meta_test=not args.skip_meta_test,
            run_quick_verify=run_quick_ralph,
            run_full_verify=run_full_ralph,
            scenario_cmd=args.scenario_cmd.strip() or None,
            flaky_runs=max(0, args.flaky_runs),
            flaky_cmd=args.flaky_cmd.strip() or None,
            run_dir=run_dir,
        )
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    try:
        weighted_decision = compute_weighted_decision(
            opus,
            ralph,
            weight_correctness=args.weight_correctness,
            weight_performance=args.weight_performance,
            weight_maintainability=args.weight_maintainability,
        )
    except Exception as exc:
        print(f"ERROR: invalid weighted-decision parameters: {exc}", file=sys.stderr)
        return 2

    markdown = build_report_markdown(opus, ralph, run_id=run_id, weighted_decision=weighted_decision)
    out_md.write_text(markdown, encoding="utf-8")
    out_json.write_text(
        json.dumps(
            {
                "run_id": run_id,
                "generated_utc": datetime.now(timezone.utc).isoformat(),
                "options": {
                    "run_meta_test": not args.skip_meta_test,
                    "run_quick_verify_opus": run_quick_opus,
                    "run_quick_verify_ralph": run_quick_ralph,
                    "run_full_verify_opus": run_full_opus,
                    "run_full_verify_ralph": run_full_ralph,
                    "scenario_cmd": args.scenario_cmd.strip() or "",
                    "flaky_runs": max(0, args.flaky_runs),
                    "flaky_cmd": args.flaky_cmd.strip() or "",
                    "opus_ref": args.opus_ref,
                    "ralph_ref": args.ralph_ref,
                    "opus_base": args.opus_base.strip() or "",
                    "ralph_base": args.ralph_base.strip() or "",
                },
                "weighted_decision": weighted_decision,
                "opus": asdict(opus),
                "ralph": asdict(ralph),
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )

    print(f"Wrote report: {out_md}")
    print(f"Wrote json:   {out_json}")
    print(f"Blockers -> opus: {opus.blockers}, ralph: {ralph.blockers}")

    # Non-zero if either repo has blockers, so this can be CI-gated if desired.
    return 0 if opus.blockers == 0 and ralph.blockers == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
