#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


PHASE1_JSON_REQUIREMENTS = """JSON requirements:
- Return exactly one JSON object and no other text.
- Top-level fields: generated_at (ISO 8601 string), validator_version (string), findings (array).
- Each finding must include: finding_id, section, category, severity, description, evidence, proposed_fix_type, proposed_fix.
- finding_id format: F-###.
- Allowed category values: missing_fail_closed, weak_normative, missing_at_pair, stale_input_unspecified, gate_interaction_gap, cross_ref_broken.
- Allowed severity values: P0, P1, P2.
- Evidence must include line (integer) and quote (string under 200 chars). evidence.context is optional.
- Allowed proposed_fix_type values: mechanical, new_requirement.
- Use severity conservatively.
- If no qualifying defect exists, return a valid object with findings: [].
"""

PHASE2_JSON_REQUIREMENTS = """JSON requirements:
- Return exactly one JSON object and no other text.
- Top-level fields: generated_at (ISO 8601 string), validator_version (string), proposals (array).
- Each proposal must include: proposal_id, source_finding, source_finding_category, section, change_type, rationale, status, dedupe_key.
- proposal_id format: P-###. source_finding format: F-###.
- Allowed change_type values: mechanical, new_requirement.
- Allowed status values: proposed, pending_scope_review, rejected, stale.
- Allowed source_finding_category values: missing_fail_closed, weak_normative, missing_at_pair, stale_input_unspecified, gate_interaction_gap, cross_ref_broken.
- For mechanical proposals, include mechanical_ok (boolean). If mechanical_ok is true, include replace_span and mechanical_details.
- replace_span must include: start_line, end_line, old_text, new_text.
- For new_requirement proposals, include proposed_text.
"""


def fail(message: str, exit_code: int = 1) -> int:
    print(message, file=sys.stderr)
    return exit_code


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument("--model", default="")
    parser.add_argument("-p", dest="prompt", required=True)
    parser.add_argument("--print", action="store_true", dest="print_mode")
    args, extras = parser.parse_known_args(argv)
    if extras:
        raise SystemExit(f"unsupported argument(s): {' '.join(extras)}")
    return args


def extract_line(raw_prompt: str, prefix: str) -> str:
    needle = f"{prefix}:"
    for line in raw_prompt.splitlines():
        if line.startswith(needle):
            return line.split(":", 1)[1].strip()
    return ""


def extract_block(raw_prompt: str, start_marker: str, end_marker: str | None = None) -> str:
    if start_marker not in raw_prompt:
        return ""
    block = raw_prompt.split(start_marker, 1)[1]
    if end_marker and end_marker in block:
        block = block.split(end_marker, 1)[0]
    return block.strip()


def build_prompt(raw_prompt: str) -> str:
    task_kind = extract_line(raw_prompt, "TASK_KIND")
    fixture_path = extract_line(raw_prompt, "FIXTURE_PATH")
    skill_text = extract_block(raw_prompt, "Skill instructions:\n", "\n\nRequired schema:\n")
    findings_json = extract_block(raw_prompt, "\n\nDetector findings JSON:\n")

    if task_kind == "contract-gap-detector" and fixture_path:
        return f"""Read exactly one file and nothing else: {fixture_path}

Skill instructions:
{skill_text}

{PHASE1_JSON_REQUIREMENTS}
"""

    if task_kind == "contract-patch" and fixture_path:
        return f"""Read exactly one file and nothing else: {fixture_path}

Skill instructions:
{skill_text}

Detector findings JSON:
{findings_json}

{PHASE2_JSON_REQUIREMENTS}
"""

    return (
        "Use only the provided prompt contents. Return exactly one response and no extra commentary.\n\n"
        + raw_prompt
    )


def resolve_workdir(cwd: Path) -> Path:
    result = subprocess.run(
        ["git", "-C", str(cwd), "rev-parse", "--show-toplevel"],
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode == 0:
        candidate = result.stdout.strip()
        if candidate:
            return Path(candidate)
    return cwd


def resolve_auth_source() -> Path:
    explicit = os.environ.get("CONTRACT_CODEX_AUTH_JSON")
    if explicit:
        return Path(explicit)
    return Path.home() / ".codex" / "auth.json"


def map_model(model: str) -> str:
    if model in {"", "sonnet"}:
        return os.environ.get("CONTRACT_CODEX_DEFAULT_MODEL", "gpt-5.4")
    return model


def write_config(home_dir: Path, model: str, reasoning_effort: str) -> None:
    codex_dir = home_dir / ".codex"
    codex_dir.mkdir(parents=True, exist_ok=True)
    (codex_dir / "config.toml").write_text(
        "\n".join(
            [
                f'model = "{model}"',
                f'model_reasoning_effort = "{reasoning_effort}"',
                "[features]",
                "apps = false",
                "default_mode_request_user_input = false",
                "multi_agent = false",
                "js_repl = false",
                "shell_snapshot = false",
                "unified_exec = false",
                "steer = false",
                "",
            ]
        ),
        encoding="utf-8",
    )


def run_codex(prompt: str, model: str, cwd: Path) -> str:
    auth_source = resolve_auth_source()
    if not auth_source.is_file():
        raise SystemExit(fail(f"missing Codex auth file: {auth_source}"))

    codex_bin = os.environ.get("CONTRACT_CODEX_BIN", "codex")
    reasoning_effort = os.environ.get("CONTRACT_CODEX_REASONING_EFFORT", "xhigh")
    workdir = resolve_workdir(cwd)

    with tempfile.TemporaryDirectory(prefix="contract-codex-wrapper.") as temp_dir_str:
        temp_dir = Path(temp_dir_str)
        last_file = temp_dir / "last.txt"
        stdout_file = temp_dir / "stdout.txt"
        stderr_file = temp_dir / "stderr.txt"
        clean_home = temp_dir / "home"
        clean_codex_dir = clean_home / ".codex"
        clean_codex_dir.mkdir(parents=True, exist_ok=True)
        shutil.copy2(auth_source, clean_codex_dir / "auth.json")
        write_config(clean_home, model, reasoning_effort)

        cmd = [
            codex_bin,
            "exec",
            "--color",
            "never",
            "--disable",
            "apps",
            "--disable",
            "default_mode_request_user_input",
            "--ephemeral",
            "--skip-git-repo-check",
            "-C",
            str(workdir),
            "-s",
            "read-only",
            "-m",
            model,
            "-c",
            f'model_reasoning_effort="{reasoning_effort}"',
            "--output-last-message",
            str(last_file),
            "-",
        ]
        env = os.environ.copy()
        env["HOME"] = str(clean_home)
        result = subprocess.run(
            cmd,
            input=prompt,
            capture_output=True,
            text=True,
            check=False,
            env=env,
        )
        stdout_file.write_text(result.stdout, encoding="utf-8")
        stderr_file.write_text(result.stderr, encoding="utf-8")

        if result.returncode != 0:
            message = result.stderr.strip() or result.stdout.strip() or "codex exec failed"
            raise SystemExit(fail(message))
        if not last_file.is_file():
            raise SystemExit(fail("codex exec did not produce --output-last-message output"))
        return last_file.read_text(encoding="utf-8")


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    prompt = build_prompt(args.prompt)
    model = map_model(args.model)
    sys.stdout.write(run_codex(prompt, model, Path.cwd()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
