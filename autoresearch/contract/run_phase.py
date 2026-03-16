#!/usr/bin/env python3
from __future__ import annotations

import argparse
import fcntl
import hashlib
import json
import os
import shutil
import subprocess
import sys
from contextlib import contextmanager
from datetime import datetime, timezone
from pathlib import Path
from tempfile import NamedTemporaryFile
from typing import Any, NoReturn
from uuid import uuid4

from jsonschema import Draft202012Validator

# Ensure sibling modules resolve regardless of invocation CWD.
sys.path.insert(0, str(Path(__file__).parent))

from apply_proposals import apply_fixture_proposals, validate_mechanical_proposals
from check_contradictions import evaluate_proposals as evaluate_contradictions
from check_enforcement import validate_weak_normative, validate_missing_fail_closed


RESULTS_HEADER = "commit\tscore\tpassed\ttotal\tstatus\tdescription"


def fail(message: str, exit_code: int = 1) -> NoReturn:
    print(f"FAIL: {message}", file=sys.stderr)
    raise SystemExit(exit_code)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"missing JSON file: {path}")
    except json.JSONDecodeError as exc:
        fail(f"invalid JSON in {path}: {exc}")


def load_text(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        fail(f"missing file: {path}")


def load_schema(path: Path) -> dict[str, Any]:
    schema = load_json(path)
    if not isinstance(schema, dict):
        fail(f"schema must be a JSON object: {path}")
    return schema


def validate_json(instance: Any, schema: dict[str, Any], label: str) -> None:
    validator = Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(instance), key=lambda error: list(error.absolute_path))
    if errors:
        first = errors[0]
        location = ".".join(str(part) for part in first.absolute_path) or "<root>"
        fail(f"{label} schema validation failed at {location}: {first.message}")


def write_text_atomic(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with NamedTemporaryFile("w", encoding="utf-8", dir=path.parent, delete=False) as handle:
        handle.write(text)
        temp_path = Path(handle.name)
    temp_path.replace(path)


def write_json_atomic(path: Path, payload: Any) -> None:
    write_text_atomic(path, json.dumps(payload, indent=2) + "\n")


def ensure_results_header(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists() or not path.read_text(encoding="utf-8").strip():
        write_text_atomic(path, RESULTS_HEADER + "\n")
        return
    first_line = path.read_text(encoding="utf-8").splitlines()[0]
    if first_line != RESULTS_HEADER:
        fail(f"unexpected results.tsv header in {path}")


def append_results_row(
    results_file: Path,
    commit: str,
    score: float,
    passed: int,
    total: int,
    status: str,
    description: str,
) -> None:
    ensure_results_header(results_file)
    with results_file.open("a", encoding="utf-8") as handle:
        handle.write(
            f"{commit}\t{score:.3f}\t{passed}\t{total}\t{status}\t{description.replace(chr(9), ' ')}\n"
        )


def short_head(root: Path) -> str:
    result = subprocess.run(
        ["git", "rev-parse", "--short", "HEAD"],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        return "nogit"
    return result.stdout.strip() or "nogit"


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_text(load_text(path))


def now_utc() -> datetime:
    return datetime.now(timezone.utc)


def iso_now() -> str:
    return now_utc().isoformat().replace("+00:00", "Z")


def generate_run_id(prefix: str, tag: str, outputs_dir: Path) -> str:
    base = f"{prefix}-{tag}-{now_utc().strftime('%Y%m%d_%H%M%S')}-{uuid4().hex[:8]}"
    candidate = base
    counter = 1
    while (outputs_dir / candidate).exists() or (outputs_dir / f".tmp-{candidate}").exists():
        counter += 1
        candidate = f"{base}-{counter}"
    return candidate


def parse_json_object(raw_output: str, label: str) -> dict[str, Any]:
    stripped = raw_output.strip()
    if not stripped:
        fail(f"{label} produced empty output")
    try:
        payload = json.loads(stripped)
    except json.JSONDecodeError as exc:
        fail(f"{label} did not return a single JSON object: {exc}")
    if not isinstance(payload, dict):
        fail(f"{label} must return a JSON object")
    return payload


def contract_paths(root: Path) -> dict[str, Path]:
    contract_dir = root / "autoresearch" / "contract"
    return {
        "root": contract_dir,
        "common": contract_dir / "common",
        "phase1": contract_dir / "phase1",
        "phase2": contract_dir / "phase2",
        "evaluate": root / "autoresearch" / "skills" / "evaluate.py",
        "render_review": contract_dir / "render_review.py",
        "skills_dir": root / "SKILLS",
        "contract_file": root / "specs" / "CONTRACT.md",
    }


def require_skill_file(skills_dir: Path, name: str) -> Path:
    path = skills_dir / f"{name}.md"
    if not path.exists():
        fail(f"missing required skill file: {path}")
    return path


def resolve_model_cwd(contract_dir: Path, workdir: str | None) -> Path:
    if workdir:
        path = Path(workdir)
        if not path.is_absolute():
            path = (contract_dir / path).resolve()
        else:
            path = path.resolve()
        try:
            path.relative_to(contract_dir.resolve())
        except ValueError:
            fail(f"--workdir must stay under {contract_dir}")
        path.mkdir(parents=True, exist_ok=True)
        return path
    return contract_dir


def validate_context_manifest(root: Path, contract_dir: Path, *, require_snapshots: bool) -> None:
    manifest_path = contract_dir / "common" / "context_manifest.json"
    manifest = load_json(manifest_path)
    if not isinstance(manifest, dict):
        fail(f"context manifest must be a JSON object: {manifest_path}")
    tracked_files = manifest.get("tracked_files", {})
    if not isinstance(tracked_files, dict):
        fail(f"context manifest tracked_files must be an object: {manifest_path}")

    contract_path = root / "specs" / "CONTRACT.md"
    if not contract_path.exists():
        fail(f"missing contract file: {contract_path}")

    legacy_hash = manifest.get("contract_content_hash", "")
    common_contract_hash = manifest.get("common_contract_hash", legacy_hash)
    if not isinstance(common_contract_hash, str) or len(common_contract_hash) != 64:
        fail(
            "Stale context: CONTRACT.md hash missing. Run 'harness.sh contract refresh-common' first",
            exit_code=2,
        )
    try:
        int(common_contract_hash, 16)
    except ValueError:
        fail(
            "Stale context: CONTRACT.md hash invalid. Run 'harness.sh contract refresh-common' first",
            exit_code=2,
        )
    current_hash = sha256_file(contract_path)
    if current_hash != common_contract_hash:
        fail(
            "Stale context: CONTRACT.md changed. Run 'harness.sh contract refresh-common' first",
            exit_code=2,
        )

    if require_snapshots:
        snapshot_entries = [
            rel_path
            for rel_path in tracked_files
            if isinstance(rel_path, str) and rel_path.startswith("phase2/fixtures/snapshot/")
        ]
        snapshot_contract_hash = manifest.get("snapshot_contract_hash", legacy_hash)
        if not isinstance(snapshot_contract_hash, str) or len(snapshot_contract_hash) != 64:
            fail(
                "Stale context: snapshot fixture hash missing. Run 'harness.sh contract refresh-fixtures' first",
                exit_code=2,
            )
        try:
            int(snapshot_contract_hash, 16)
        except ValueError:
            fail(
                "Stale context: snapshot fixture hash invalid. Run 'harness.sh contract refresh-fixtures' first",
                exit_code=2,
            )
        if current_hash != snapshot_contract_hash or not snapshot_entries:
            fail(
                "Stale context: snapshot fixtures changed. Run 'harness.sh contract refresh-fixtures' first",
                exit_code=2,
            )

    for rel_path, expected_hash in tracked_files.items():
        if not isinstance(rel_path, str) or not isinstance(expected_hash, str):
            fail(f"context manifest contains non-string tracked file entry: {manifest_path}")
        if rel_path.startswith("phase2/fixtures/snapshot/") and not require_snapshots:
            continue
        current_path = contract_dir / rel_path
        if not current_path.exists() or sha256_file(current_path) != expected_hash:
            if rel_path.startswith("common/"):
                fail(
                    f"Stale context: {Path(rel_path).name} changed. Run 'harness.sh contract refresh-common' first",
                    exit_code=2,
                )
            if rel_path.startswith("phase2/fixtures/snapshot/"):
                fail(
                    f"Stale context: snapshot/{Path(rel_path).name} changed. Run 'harness.sh contract refresh-fixtures' first",
                    exit_code=2,
                )
            fail(f"Stale context: {rel_path} changed", exit_code=2)


def fixture_list_from_eval(phase_dir: Path, eval_path: Path, phase: str) -> list[Path]:
    payload = load_json(eval_path)
    tests = payload.get("tests", [])
    if not isinstance(tests, list):
        fail(f"{eval_path} must contain a tests array")
    fixture_paths: list[Path] = []
    seen_paths: set[Path] = set()
    if phase == "phase1":
        allowed_roots = [(phase_dir / "fixtures").resolve()]
    else:
        allowed_roots = [
            (phase_dir / "fixtures" / "static").resolve(),
            (phase_dir / "fixtures" / "snapshot").resolve(),
        ]
    for test in tests:
        if not isinstance(test, dict):
            fail(f"{eval_path} contains a non-object test entry")
        fixture = test.get("fixture")
        if not isinstance(fixture, str) or not fixture.strip():
            fail(f"{eval_path} contains a test entry with missing fixture")
        fixture_path = (phase_dir / fixture).resolve()
        if not fixture_path.exists():
            fail(f"{eval_path} references missing fixture: {fixture}")
        if not any(
            fixture_path == allowed_root or allowed_root in fixture_path.parents
            for allowed_root in allowed_roots
        ):
            fail(f"{eval_path} fixture escapes allowed roots: {fixture}")
        if fixture_path in seen_paths:
            continue
        seen_paths.add(fixture_path)
        fixture_paths.append(fixture_path)
    return fixture_paths


def collect_phase_fixtures(phase_dir: Path, eval_path: Path, phase: str) -> list[tuple[str, Path]]:
    fixture_paths = fixture_list_from_eval(phase_dir, eval_path, phase)
    if not fixture_paths:
        fail(f"{eval_path} does not declare any fixtures for {phase} run")

    seen: dict[str, Path] = {}
    fixtures: list[tuple[str, Path]] = []
    for path in fixture_paths:
        fixture_id = path.stem
        if fixture_id in seen:
            fail(f"duplicate fixture id '{fixture_id}' from {seen[fixture_id]} and {path}")
        seen[fixture_id] = path
        fixtures.append((fixture_id, path))
    return fixtures


def run_claude(prompt: str, model: str, cwd: Path) -> str:
    claude_bin = os.environ.get("CLAUDE_BIN", "claude")
    result = subprocess.run(
        [claude_bin, "--model", model, "-p", prompt],
        cwd=cwd,
        capture_output=True,
        text=True,
        check=False,
        env={**os.environ, "CONTRACT_READONLY": "1"},
    )
    if result.returncode != 0:
        message = result.stderr.strip() or result.stdout.strip() or f"{claude_bin} exited {result.returncode}"
        fail(f"claude invocation failed: {message}")
    return result.stdout


def build_phase1_prompt(skill_text: str, fixture_id: str, fixture_path: Path, fixture_text: str, schema_text: str) -> str:
    return f"""TASK_KIND: contract-gap-detector
RETURN_FORMAT: single JSON object only, no markdown fences
FIXTURE_ID: {fixture_id}
FIXTURE_PATH: {fixture_path}

Skill instructions:
{skill_text}

Required schema:
{schema_text}

Fixture contents:
{fixture_text}
"""


def build_phase2_prompt(
    skill_text: str,
    fixture_id: str,
    fixture_path: Path,
    fixture_text: str,
    findings_payload: dict[str, Any],
    schema_text: str,
) -> str:
    return f"""TASK_KIND: contract-patch
RETURN_FORMAT: single JSON object only, no markdown fences
FIXTURE_ID: {fixture_id}
FIXTURE_PATH: {fixture_path}

Skill instructions:
{skill_text}

Required schema:
{schema_text}

Fixture contents:
{fixture_text}

Detector findings JSON:
{json.dumps(findings_payload, indent=2)}
"""


def ensure_unique(field_name: str, values: list[str], label: str) -> None:
    if len(values) != len(set(values)):
        fail(f"{label} contains duplicate {field_name} values")


def validate_findings_payload(payload: dict[str, Any], schema: dict[str, Any], label: str) -> None:
    validate_json(payload, schema, label)
    findings = payload.get("findings", [])
    ensure_unique("finding_id", [finding["finding_id"] for finding in findings], label)


def validate_initial_proposals(
    payload: dict[str, Any],
    schema: dict[str, Any],
    label: str,
    fixture_text: str,
    findings_payload: dict[str, Any],
    registry_path: Path | None = None,
) -> None:
    validate_json(payload, schema, label)
    proposals = payload.get("proposals", [])
    ensure_unique("proposal_id", [proposal["proposal_id"] for proposal in proposals], label)
    ensure_unique("dedupe_key", [proposal["dedupe_key"] for proposal in proposals], label)

    # Cross-reference new_ats.at_id values against at_registry.json to detect
    # collisions with existing acceptance tests.
    known_at_ids: set[str] = set()
    if registry_path is not None and registry_path.exists():
        registry = load_json(registry_path)
        known_at_ids = {entry["at_id"] for entry in registry if isinstance(entry, dict) and "at_id" in entry}
    proposed_at_ids: list[str] = []
    for proposal in proposals:
        for at_entry in proposal.get("new_ats") or []:
            at_id = at_entry.get("at_id", "")
            if at_id in known_at_ids:
                fail(
                    f"{label} proposal {proposal['proposal_id']!r} proposes "
                    f"at_id {at_id!r} that already exists in at_registry.json"
                )
            proposed_at_ids.append(at_id)
    ensure_unique("at_id in new_ats", proposed_at_ids, label)

    findings = {finding["finding_id"]: finding for finding in findings_payload.get("findings", [])}
    for proposal in proposals:
        if proposal.get("status") != "proposed":
            fail(f"{label} contains non-proposed status before validation: {proposal['proposal_id']}")
        source_finding = proposal["source_finding"]
        finding = findings.get(source_finding)
        if finding is None:
            fail(f"{label} source_finding does not resolve in sibling findings.json: {source_finding}")
        if proposal["source_finding_category"] != finding["category"]:
            fail(
                f"{label} source_finding_category mismatch for {proposal['proposal_id']}: "
                f"{proposal['source_finding_category']} != {finding['category']}"
            )
        if proposal["section"] != finding["section"]:
            fail(
                f"{label} section mismatch for {proposal['proposal_id']}: "
                f"{proposal['section']} != {finding['section']}"
            )

    validate_mechanical_proposals(fixture_text, proposals)


def apply_status_results(
    payload: dict[str, Any],
    contradiction_results: dict[str, Any],
    enforcement_results: list[dict[str, str]],
) -> dict[str, Any]:
    updated = json.loads(json.dumps(payload))
    index: dict[str, dict[str, Any]] = {
        proposal["proposal_id"]: proposal for proposal in updated.get("proposals", [])
    }

    for result in contradiction_results.get("results", []):
        proposal = index.get(result["proposal_id"])
        if proposal is None:
            fail(f"contradiction checker returned unknown proposal_id: {result['proposal_id']}")
        if result["status"] != "proposed":
            proposal["status"] = result["status"]

    for result in enforcement_results:
        proposal = index.get(result["proposal_id"])
        if proposal is None:
            fail(f"enforcement checker returned unknown proposal_id: {result['proposal_id']}")
        # Contradiction rejections remain terminal. Scope-review holds are softer:
        # enforcement may still escalate them to `rejected`, but must not relax
        # them back to `proposed`.
        if proposal["status"] == "rejected":
            continue
        if proposal["status"] == "pending_scope_review" and result["status"] != "rejected":
            continue
        if result["status"] != "proposed":
            proposal["status"] = result["status"]

    return updated


def load_index_container(index_path: Path) -> tuple[list[dict[str, Any]], str | None, dict[str, Any] | None]:
    if index_path.exists():
        payload = load_json(index_path)
        if isinstance(payload, list):
            entries = payload
            wrapper_key = None
            wrapper_payload = None
        elif isinstance(payload, dict) and isinstance(payload.get("entries"), list):
            entries = payload["entries"]
            wrapper_key = "entries"
            wrapper_payload = payload
        elif isinstance(payload, dict) and isinstance(payload.get("runs"), list):
            entries = payload["runs"]
            wrapper_key = "runs"
            wrapper_payload = payload
        else:
            fail(f"{index_path} must be a JSON array or object with entries/runs array")
    else:
        entries = []
        wrapper_key = None
        wrapper_payload = None

    for existing in entries:
        if not isinstance(existing, dict):
            fail(f"{index_path} contains a non-object entry")
    return list(entries), wrapper_key, wrapper_payload


def write_index_container(
    index_path: Path,
    entries: list[dict[str, Any]],
    wrapper_key: str | None,
    wrapper_payload: dict[str, Any] | None,
) -> None:
    if wrapper_key is None:
        write_json_atomic(index_path, entries)
        return
    if wrapper_payload is None:
        fail(f"missing wrapper payload for {index_path}")
    updated_payload = dict(wrapper_payload)
    updated_payload[wrapper_key] = entries
    write_json_atomic(index_path, updated_payload)


@contextmanager
def _index_lock(index_path: Path):  # type: ignore[return]
    """Exclusive flock on a companion .lock file to serialise concurrent writers.

    Caveat: fcntl.flock is advisory on Linux and macOS local filesystems.
    On NFS and some macOS network mounts it may silently succeed without
    providing mutual exclusion — do not rely on this lock for correctness
    across NFS-mounted paths.  For local CI/dev use this is safe.
    """
    lock_path = index_path.with_suffix(".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    with lock_path.open("a") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lf, fcntl.LOCK_UN)


def append_index_entry(index_path: Path, entry: dict[str, Any]) -> list[dict[str, Any]]:
    with _index_lock(index_path):
        entries, wrapper_key, wrapper_payload = load_index_container(index_path)
        for existing in entries:
            if existing.get("run_id") == entry["run_id"]:
                fail(f"duplicate run_id in proposals index: {entry['run_id']}")
        entries = list(entries) + [entry]
        write_index_container(index_path, entries, wrapper_key, wrapper_payload)
    return entries


def score_outputs(
    root: Path,
    eval_path: Path,
    output_dir: Path,
) -> dict[str, Any]:
    evaluate_path = root / "autoresearch" / "skills" / "evaluate.py"
    if not evaluate_path.exists():
        fail(f"missing evaluator: {evaluate_path}")
    result = subprocess.run(
        [
            sys.executable,
            str(evaluate_path),
            "--eval",
            str(eval_path),
            "--output-dir",
            str(output_dir),
            "--skill-dir",
            str(root),
            "--json",
        ],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode not in (0, 1):
        message = result.stderr.strip() or result.stdout.strip() or "evaluate.py failed"
        fail(message)
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail(f"evaluate.py did not return JSON: {exc}")
    if not isinstance(payload, dict):
        fail("evaluate.py returned a non-object JSON payload")
    missing_outputs = payload.get("missing_outputs")
    if not isinstance(missing_outputs, int):
        fail("evaluate.py returned invalid missing_outputs value")
    if missing_outputs > 0:
        fail(f"evaluate.py reported missing outputs for {missing_outputs} test(s)")
    return payload


def append_scored_results_row(
    results_file: Path,
    commit: str,
    payload: dict[str, Any],
    status: str,
    description: str,
) -> None:
    score = payload.get("score")
    passed = payload.get("passed")
    total = payload.get("total")
    if not isinstance(score, (int, float)) or not isinstance(passed, int) or not isinstance(total, int):
        fail("evaluate.py returned invalid score payload")
    append_results_row(
        results_file,
        commit,
        float(score),
        passed,
        total,
        status,
        description,
    )


def update_index_review_paths(index_path: Path, run_id: str, review_package_path: str) -> None:
    entries, wrapper_key, wrapper_payload = load_index_container(index_path)
    updated = False
    for entry in entries:
        if entry.get("run_id") == run_id:
            entry["review_package_path"] = review_package_path
            updated = True
            break
    if not updated:
        fail(f"missing proposals_index entry for run_id={run_id}")
    write_index_container(index_path, entries, wrapper_key, wrapper_payload)


def phase1_run(root: Path, tag: str, model: str, eval_path: Path, workdir: str | None, mode: str) -> int:
    paths = contract_paths(root)
    contract_dir = paths["root"]
    phase_dir = paths["phase1"]
    skill_path = require_skill_file(paths["skills_dir"], "contract-gap-detector")
    fixtures = collect_phase_fixtures(phase_dir, eval_path, "phase1")
    if mode in {"run", "baseline"}:
        validate_context_manifest(root, contract_dir, require_snapshots=False)
    schema = load_schema(phase_dir / "findings.schema.json")
    schema_text = load_text(phase_dir / "findings.schema.json")
    model_cwd = resolve_model_cwd(contract_dir, workdir)
    if mode == "eval":
        fail("phase1_run does not support eval mode directly")
    run_id = generate_run_id("phase1" if mode == "run" else "phase1-baseline", tag, phase_dir / "outputs")
    tmp_run_dir = phase_dir / "outputs" / f".tmp-{run_id}"
    final_run_dir = phase_dir / "outputs" / run_id
    skill_text = load_text(skill_path)
    passed_checks = 0
    total_checks = len(fixtures) * 2

    try:
        tmp_run_dir.mkdir(parents=True, exist_ok=False)
        for fixture_id, fixture_path in fixtures:
            fixture_text = load_text(fixture_path)
            prompt = build_phase1_prompt(skill_text, fixture_id, fixture_path, fixture_text, schema_text)
            payload = parse_json_object(run_claude(prompt, model, model_cwd), f"phase1 {fixture_id}")
            validate_findings_payload(payload, schema, f"{fixture_id}/findings.json")
            passed_checks += 2
            write_json_atomic(tmp_run_dir / fixture_id / "findings.json", payload)
        tmp_run_dir.replace(final_run_dir)
    except BaseException:
        shutil.rmtree(tmp_run_dir, ignore_errors=True)
        raise

    if mode == "run":
        score = 0.0 if total_checks == 0 else passed_checks / total_checks
        append_results_row(
            phase_dir / "results.tsv",
            short_head(root),
            score,
            passed_checks,
            total_checks,
            "keep",
            f"phase1 run {run_id} (execution checks)",
        )
        print(
            "phase1 run complete: "
            f"run_id={run_id} fixtures={len(fixtures)} checks={passed_checks}/{total_checks} score={score:.3f}"
        )
        return 0

    score_payload = score_outputs(root, eval_path, final_run_dir)
    append_scored_results_row(
        phase_dir / "results.tsv",
        short_head(root),
        score_payload,
        "baseline",
        f"phase1 baseline {run_id}",
    )
    print(
        "phase1 baseline complete: "
        f"run_id={run_id} score={score_payload['score']:.3f} "
        f"passed={score_payload['passed']}/{score_payload['total']}"
    )
    return 0


def phase2_run(root: Path, tag: str, model: str, eval_path: Path, workdir: str | None, mode: str) -> int:
    paths = contract_paths(root)
    contract_dir = paths["root"]
    phase_dir = paths["phase2"]
    detector_skill_path = require_skill_file(paths["skills_dir"], "contract-gap-detector")
    patch_skill_path = require_skill_file(paths["skills_dir"], "contract-patch")
    fixtures = collect_phase_fixtures(phase_dir, eval_path, "phase2")
    if mode in {"run", "baseline"}:
        snapshot_root = (phase_dir / "fixtures" / "snapshot").resolve()
        require_snapshots = any(
            fixture_path == snapshot_root or snapshot_root in fixture_path.parents
            for _, fixture_path in fixtures
        )
        validate_context_manifest(root, contract_dir, require_snapshots=require_snapshots)
    findings_schema = load_schema(paths["phase1"] / "findings.schema.json")
    findings_schema_text = load_text(paths["phase1"] / "findings.schema.json")
    proposals_schema = load_schema(phase_dir / "proposals.schema.json")
    proposals_schema_text = load_text(phase_dir / "proposals.schema.json")
    model_cwd = resolve_model_cwd(contract_dir, workdir)
    if mode == "eval":
        fail("phase2_run does not support eval mode directly")
    run_id = generate_run_id("phase2" if mode == "run" else "phase2-baseline", tag, phase_dir / "outputs")
    tmp_run_dir = phase_dir / "outputs" / f".tmp-{run_id}"
    final_run_dir = phase_dir / "outputs" / run_id
    detector_skill_text = load_text(detector_skill_path)
    patch_skill_text = load_text(patch_skill_path)
    contract_text = load_text(paths["contract_file"])
    contract_hash = sha256_text(contract_text)
    proposal_count = 0
    passed_checks = 0
    # 6 per-fixture checks: findings-valid, proposals-valid, contradictions,
    # enforcement, final-validate, patched-write.  Plus 2 run-mode checks:
    # index-append, render-review-paths.  Total = N*6 + 2 → score 1.0 on clean run.
    total_checks = len(fixtures) * 6 + 2

    try:
        tmp_run_dir.mkdir(parents=True, exist_ok=False)
        for fixture_id, fixture_path in fixtures:
            fixture_text = load_text(fixture_path)

            findings_prompt = build_phase1_prompt(
                detector_skill_text,
                fixture_id,
                fixture_path,
                fixture_text,
                findings_schema_text,
            )
            findings_payload = parse_json_object(
                run_claude(findings_prompt, model, model_cwd),
                f"phase2 detect {fixture_id}",
            )
            validate_findings_payload(findings_payload, findings_schema, f"{fixture_id}/findings.json")
            passed_checks += 1
            write_json_atomic(tmp_run_dir / fixture_id / "findings.json", findings_payload)

            proposals_prompt = build_phase2_prompt(
                patch_skill_text,
                fixture_id,
                fixture_path,
                fixture_text,
                findings_payload,
                proposals_schema_text,
            )
            proposals_payload = parse_json_object(
                run_claude(proposals_prompt, model, model_cwd),
                f"phase2 patch {fixture_id}",
            )
            validate_initial_proposals(
                proposals_payload,
                proposals_schema,
                f"{fixture_id}/proposals.json",
                fixture_text,
                findings_payload,
                registry_path=paths["common"] / "at_registry.json",
            )
            passed_checks += 1

            contradiction_results = evaluate_contradictions(contract_text, proposals_payload.get("proposals", []))
            passed_checks += 1
            enforcement_results = validate_weak_normative(proposals_payload)
            enforcement_results += validate_missing_fail_closed(proposals_payload)
            passed_checks += 1
            validated_payload = apply_status_results(
                proposals_payload,
                contradiction_results,
                enforcement_results,
            )
            validate_json(validated_payload, proposals_schema, f"{fixture_id}/validated proposals.json")
            passed_checks += 1
            write_json_atomic(tmp_run_dir / fixture_id / "proposals.json", validated_payload)

            patched_text, applied_count = apply_fixture_proposals(
                fixture_text,
                validated_payload.get("proposals", []),
            )
            if applied_count > 0 and patched_text == fixture_text:
                fail(f"{fixture_id} proposal application produced no fixture diff")
            write_text_atomic(tmp_run_dir / fixture_id / "patched" / f"{fixture_id}.patched.md", patched_text)
            passed_checks += 1
            proposal_count += len(validated_payload.get("proposals", []))

        if mode == "run":
            # Write the index entry BEFORE the atomic rename so that a SIGKILL
            # between this point and the rename leaves an index entry pointing to
            # a missing directory (detectable) rather than an orphaned directory
            # with no index entry (silent).
            index_entry = {
                "run_id": run_id,
                "timestamp": iso_now(),
                "contract_file_hash": contract_hash,
                "status": "pending",
                "proposal_count": proposal_count,
                "accepted_count": 0,
                "file_path": f"autoresearch/contract/phase2/proposals/CONTRACT_PROPOSALS_{run_id}.md",
            }
            index_path = phase_dir / "proposals_index.json"
            previous_index = index_path.read_text(encoding="utf-8") if index_path.exists() else None
            append_index_entry(index_path, index_entry)
            passed_checks += 1
        tmp_run_dir.replace(final_run_dir)
        if mode == "run":
            render = subprocess.run(
                [sys.executable, str(paths["render_review"]), "--root", str(root), "--run-id", run_id],
                cwd=root,
                capture_output=True,
                text=True,
                check=False,
            )
            if render.returncode != 0:
                if previous_index is None:
                    index_path.unlink(missing_ok=True)
                else:
                    write_text_atomic(index_path, previous_index)
                shutil.rmtree(final_run_dir, ignore_errors=True)
                # Clean up any partially-written render artifacts so they do not
                # linger as orphaned files after the rollback.
                for orphan in [
                    phase_dir / "proposals" / f"CONTRACT_PROPOSALS_{run_id}.md",
                    phase_dir / "review" / f"CONTRACT_REVIEW_{run_id}.md",
                ]:
                    orphan.unlink(missing_ok=True)
                fail(render.stderr.strip() or render.stdout.strip() or "render-review failed")
            update_index_review_paths(
                index_path,
                run_id,
                f"autoresearch/contract/phase2/review/CONTRACT_REVIEW_{run_id}.md",
            )
            passed_checks += 1
    except BaseException:
        shutil.rmtree(tmp_run_dir, ignore_errors=True)
        raise

    if mode == "run":
        score = 0.0 if total_checks == 0 else passed_checks / total_checks
        append_results_row(
            phase_dir / "results.tsv",
            short_head(root),
            score,
            passed_checks,
            total_checks,
            "keep",
            f"phase2 run {run_id} (execution checks)",
        )
        print(
            "phase2 run complete: "
            f"run_id={run_id} fixtures={len(fixtures)} proposals={proposal_count} "
            f"checks={passed_checks}/{total_checks} score={score:.3f}"
        )
        return 0

    score_payload = score_outputs(root, eval_path, final_run_dir)
    append_scored_results_row(
        phase_dir / "results.tsv",
        short_head(root),
        score_payload,
        "baseline",
        f"phase2 baseline {run_id}",
    )
    print(
        "phase2 baseline complete: "
        f"run_id={run_id} proposals={proposal_count} "
        f"score={score_payload['score']:.3f} passed={score_payload['passed']}/{score_payload['total']}"
    )
    return 0


def phase_eval(root: Path, phase: str, eval_path: Path, output_dir: Path) -> int:
    payload = score_outputs(root, eval_path, output_dir)
    print(
        f"{phase} eval complete: "
        f"score={payload['score']:.3f} passed={payload['passed']}/{payload['total']}"
    )
    return 0 if payload["score"] >= 1.0 else 1


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run contract autoresearch phases")
    parser.add_argument("--root", required=True, type=Path)
    parser.add_argument("--phase", required=True, choices=["phase1", "phase2"])
    parser.add_argument("--mode", required=True, choices=["run", "baseline", "eval"])
    parser.add_argument("--tag", default=now_utc().strftime("%b%d").lower())
    parser.add_argument("--model", default="sonnet")
    parser.add_argument("--eval", required=True, type=Path)
    parser.add_argument("--workdir")
    parser.add_argument("--output-dir", type=Path)
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    root = args.root.resolve()
    eval_path = args.eval
    if not eval_path.is_absolute():
        eval_path = (root / eval_path).resolve()
    if not eval_path.exists():
        fail(f"missing eval config: {eval_path}")

    if args.mode == "eval":
        if args.output_dir is None:
            fail("--output-dir is required for eval mode")
        output_dir = args.output_dir
        if not output_dir.is_absolute():
            output_dir = (root / output_dir).resolve()
        return phase_eval(root, args.phase, eval_path, output_dir)

    if args.phase == "phase1":
        return phase1_run(root, args.tag, args.model, eval_path, args.workdir, args.mode)
    if args.phase == "phase2":
        return phase2_run(root, args.tag, args.model, eval_path, args.workdir, args.mode)
    fail(f"unsupported phase: {args.phase}")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
