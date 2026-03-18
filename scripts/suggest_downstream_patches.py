#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
LLM-Assisted Downstream Patch Suggester.

Reads an Impact Report, extracts CONTRACT clause diffs, and uses Claude
to suggest patches for downstream artifacts (plan, code) that need updates.

Usage:
    # Generate suggestions for all unresolved items
    python scripts/suggest_downstream_patches.py \\
        --impact artifacts/impact_report.json \\
        --output patches/

    # Generate for specific clause only
    python scripts/suggest_downstream_patches.py \\
        --clause CSP-007 \\
        --output patches/

    # Dry run (show prompts without calling Claude)
    python scripts/suggest_downstream_patches.py --dry-run

Exit codes:
    0 = success (patches generated or nothing to do)
    1 = error
    2 = Claude CLI not available
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Optional

# Add scripts to path for utils import
SCRIPT_DIR = Path(__file__).parent
sys.path.insert(0, str(SCRIPT_DIR.parent))

try:
    import yaml
except ImportError:
    print("ERROR: pyyaml not installed. Run: pip install pyyaml", file=sys.stderr)
    sys.exit(1)

from scripts.utils.artifact_loader import (
    extract_contract_clause,
    extract_prd_item,
    extract_slice,
    format_prd_item_for_patch,
    get_clause_diff,
    get_prd_item_json,
    load_file_content,
    parse_artifact_path,
)


# --- Configuration ---
DEFAULT_IMPACT_PATH = Path("artifacts/impact_report.json")
DEFAULT_OUTPUT_DIR = Path("patches")
DEFAULT_CONTRACT_PATH = Path("specs/CONTRACT.md")
DEFAULT_TRACE_PATH = Path("specs/TRACE.yaml")
DEFAULT_PLAN_PATH = Path("specs/IMPLEMENTATION_PLAN.md")
DEFAULT_PRD_PATH = Path("plans/prd.json")
DEFAULT_MODEL = "sonnet"


# --- Prompt Template ---
PROMPT_TEMPLATE = """\
You are updating downstream implementation artifacts after a CONTRACT change.

## CONTRACT Change ({clause_id}: {clause_name})

{clause_diff}

## Current Downstream Artifact

File: {artifact_path}

```
{current_content}
```

## Task

Generate a unified diff patch that updates the artifact to reflect the CONTRACT change.

Guidelines:
- Preserve existing structure, formatting, and style
- Only modify sections directly affected by the contract change
- Ensure terminology matches the updated contract clause
- Add or update references to contract section numbers if needed
- Do NOT add unrelated changes or "improvements"

Output ONLY the patch in unified diff format, starting with:
--- a/{artifact_path}
+++ b/{artifact_path}

Do not include any explanation or commentary outside the diff."""


# --- Data Classes ---
@dataclass
class PatchRequest:
    """A request to generate a patch for a downstream artifact."""

    clause_id: str
    clause_name: str
    clause_diff: str
    artifact_path: str
    artifact_type: str  # "plan" | "code" | "tests"
    current_content: str


@dataclass
class PatchResult:
    """Result of a patch generation attempt."""

    clause_id: str
    artifact_path: str
    patch_content: Optional[str]
    error: Optional[str]
    prompt: str  # Keep prompt for debugging


# --- Core Functions ---
def check_claude_cli() -> bool:
    """Check if Claude CLI is available."""
    try:
        result = subprocess.run(
            ["claude", "--version"],
            capture_output=True,
            text=True,
            check=False,
        )
        return result.returncode == 0
    except FileNotFoundError:
        return False


def call_claude(prompt: str, model: str = DEFAULT_MODEL) -> str:
    """
    Call Claude CLI with a prompt.

    Args:
        prompt: The prompt to send
        model: Model to use (default: sonnet)

    Returns:
        Claude's response text

    Raises:
        RuntimeError: If Claude CLI fails
    """
    result = subprocess.run(
        ["claude", "-p", prompt, "--model", model],
        capture_output=True,
        text=True,
        check=False,
    )

    if result.returncode != 0:
        raise RuntimeError(f"Claude CLI failed: {result.stderr}")

    return result.stdout.strip()


def load_impact_report(path: Path) -> Optional[dict]:
    """Load impact report JSON."""
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: Failed to load impact report: {e}", file=sys.stderr)
        return None


def load_trace(path: Path) -> Optional[dict]:
    """Load TRACE.yaml."""
    try:
        return yaml.safe_load(path.read_text(encoding="utf-8"))
    except Exception as e:
        print(f"ERROR: Failed to load TRACE.yaml: {e}", file=sys.stderr)
        return None


def build_patch_requests(
    report: dict,
    trace: dict,
    contract_path: Path,
    plan_path: Path,
    prd_path: Path,
    base_path: Path,
    clause_filter: Optional[str] = None,
    base_ref: str = "origin/main",
) -> List[PatchRequest]:
    """
    Build patch requests for unresolved items.

    Args:
        report: Impact report data
        trace: TRACE.yaml data
        contract_path: Path to CONTRACT.md
        plan_path: Path to IMPLEMENTATION_PLAN.md
        prd_path: Path to prd.json
        base_path: Base path for resolving relative paths
        clause_filter: Optional clause ID to filter (e.g., "CSP-007")
        base_ref: Git ref for diff comparison

    Returns:
        List of PatchRequest objects
    """
    requests = []

    for item in report.get("items", []):
        # Skip resolved items
        if item.get("resolved", False):
            continue

        clause_id = item.get("clause_id", "")
        clause_name = item.get("clause_name", "Unknown")

        # Apply filter if specified
        if clause_filter and clause_id != clause_filter:
            continue

        # Get clause diff
        clause_diff = get_clause_diff(contract_path, clause_id, base_ref)
        if not clause_diff:
            # Try getting current clause content if no diff available
            clause_content = extract_contract_clause(contract_path, clause_id)
            if clause_content:
                clause_diff = f"Current clause content:\n\n{clause_content}"
            else:
                print(f"WARN: No diff or content for {clause_id}", file=sys.stderr)
                continue

        # Get trace entry for downstream artifacts
        trace_entry = trace.get("clauses", {}).get(clause_id, {})

        # Process each downstream artifact type
        for artifact_type in ["plan", "code", "prd"]:
            artifacts = trace_entry.get(artifact_type, []) or []

            for artifact_ref in artifacts:
                file_path, anchor = parse_artifact_path(artifact_ref)

                # Determine if this artifact needs review
                downstream = item.get("downstream", {})
                type_artifacts = downstream.get(artifact_type, [])

                # Check if this artifact is marked as needing review
                needs_review = any(
                    "(needs review)" in a and file_path in a for a in type_artifacts
                )

                if not needs_review:
                    continue

                # Load artifact content based on type
                if artifact_type == "plan" and anchor:
                    # Extract specific slice from plan
                    content = extract_slice(plan_path, anchor)
                    if not content:
                        print(
                            f"WARN: Could not extract {anchor} from {file_path}",
                            file=sys.stderr,
                        )
                        continue
                elif artifact_type == "prd" and anchor:
                    # Extract specific PRD item
                    prd_item = extract_prd_item(prd_path, anchor)
                    if not prd_item:
                        print(
                            f"WARN: Could not extract PRD item {anchor} from {file_path}",
                            file=sys.stderr,
                        )
                        continue
                    content = get_prd_item_json(prd_path, anchor)
                    if not content:
                        continue
                else:
                    # Load full file
                    content = load_file_content(Path(file_path), base_path)
                    if not content:
                        print(
                            f"WARN: Could not load {file_path}",
                            file=sys.stderr,
                        )
                        continue

                requests.append(
                    PatchRequest(
                        clause_id=clause_id,
                        clause_name=clause_name,
                        clause_diff=clause_diff,
                        artifact_path=artifact_ref,
                        artifact_type=artifact_type,
                        current_content=content,
                    )
                )

    return requests


def build_prompt(request: PatchRequest) -> str:
    """Build the LLM prompt for a patch request."""
    return PROMPT_TEMPLATE.format(
        clause_id=request.clause_id,
        clause_name=request.clause_name,
        clause_diff=request.clause_diff,
        artifact_path=request.artifact_path,
        current_content=request.current_content,
    )


def extract_patch_from_response(response: str) -> Optional[str]:
    """
    Extract unified diff patch from Claude's response.

    Handles responses that might include extra text before/after the diff.
    """
    lines = response.split("\n")
    patch_lines = []
    in_patch = False

    for line in lines:
        # Start of patch
        if line.startswith("--- "):
            in_patch = True
            patch_lines = [line]
        elif in_patch:
            # End of patch (blank line or non-patch content after hunks)
            if line.startswith("```"):
                break
            patch_lines.append(line)

    if not patch_lines:
        return None

    return "\n".join(patch_lines)


def generate_patch(
    request: PatchRequest,
    model: str = DEFAULT_MODEL,
    dry_run: bool = False,
) -> PatchResult:
    """
    Generate a patch for a single artifact.

    Args:
        request: The patch request
        model: Model to use
        dry_run: If True, don't call Claude, just return the prompt

    Returns:
        PatchResult with patch content or error
    """
    prompt = build_prompt(request)

    if dry_run:
        return PatchResult(
            clause_id=request.clause_id,
            artifact_path=request.artifact_path,
            patch_content=None,
            error="DRY RUN - no Claude call made",
            prompt=prompt,
        )

    try:
        response = call_claude(prompt, model)
        patch = extract_patch_from_response(response)

        if not patch:
            return PatchResult(
                clause_id=request.clause_id,
                artifact_path=request.artifact_path,
                patch_content=None,
                error="Could not extract patch from response",
                prompt=prompt,
            )

        return PatchResult(
            clause_id=request.clause_id,
            artifact_path=request.artifact_path,
            patch_content=patch,
            error=None,
            prompt=prompt,
        )

    except RuntimeError as e:
        return PatchResult(
            clause_id=request.clause_id,
            artifact_path=request.artifact_path,
            patch_content=None,
            error=str(e),
            prompt=prompt,
        )


def write_patch(result: PatchResult, output_dir: Path) -> Optional[Path]:
    """
    Write a patch to a file.

    Args:
        result: The patch result
        output_dir: Directory to write patches to

    Returns:
        Path to the written file, or None if no patch
    """
    if not result.patch_content:
        return None

    output_dir.mkdir(parents=True, exist_ok=True)

    # Generate filename from clause ID and artifact path
    artifact_name = result.artifact_path.replace("/", "_").replace("#", "_")
    filename = f"{result.clause_id}_{artifact_name}.patch"
    output_path = output_dir / filename

    output_path.write_text(result.patch_content, encoding="utf-8")
    return output_path


# --- Main ---
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate patch suggestions for downstream artifacts after CONTRACT changes"
    )
    parser.add_argument(
        "--impact",
        type=Path,
        default=DEFAULT_IMPACT_PATH,
        help=f"Path to impact report JSON (default: {DEFAULT_IMPACT_PATH})",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Output directory for patches (default: {DEFAULT_OUTPUT_DIR})",
    )
    parser.add_argument(
        "--contract",
        type=Path,
        default=DEFAULT_CONTRACT_PATH,
        help=f"Path to CONTRACT.md (default: {DEFAULT_CONTRACT_PATH})",
    )
    parser.add_argument(
        "--trace",
        type=Path,
        default=DEFAULT_TRACE_PATH,
        help=f"Path to TRACE.yaml (default: {DEFAULT_TRACE_PATH})",
    )
    parser.add_argument(
        "--plan",
        type=Path,
        default=DEFAULT_PLAN_PATH,
        help=f"Path to IMPLEMENTATION_PLAN.md (default: {DEFAULT_PLAN_PATH})",
    )
    parser.add_argument(
        "--prd",
        type=Path,
        default=DEFAULT_PRD_PATH,
        help=f"Path to prd.json (default: {DEFAULT_PRD_PATH})",
    )
    parser.add_argument(
        "--clause",
        type=str,
        default=None,
        help="Generate patches for specific clause only (e.g., CSP-007)",
    )
    parser.add_argument(
        "--model",
        type=str,
        default=DEFAULT_MODEL,
        help=f"Claude model to use (default: {DEFAULT_MODEL})",
    )
    parser.add_argument(
        "--base-ref",
        type=str,
        default="origin/main",
        help="Git ref for diff comparison (default: origin/main)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show prompts without calling Claude",
    )
    parser.add_argument(
        "--verbose",
        "-v",
        action="store_true",
        help="Verbose output",
    )
    args = parser.parse_args()

    # Check Claude CLI availability (unless dry run)
    if not args.dry_run and not check_claude_cli():
        print(
            "ERROR: Claude CLI not found. Install with: npm install -g @anthropic-ai/claude-code",
            file=sys.stderr,
        )
        return 2

    # Load impact report
    report = load_impact_report(args.impact)
    if not report:
        # Check if file doesn't exist vs parse error
        if not args.impact.exists():
            print(f"No impact report found at {args.impact}")
            print("Generate one with: python scripts/generate_impact_report.py --json > artifacts/impact_report.json")
            return 1
        return 1

    # Check if there are unresolved items
    if report.get("unresolved_count", 0) == 0:
        print("No unresolved items in impact report. Nothing to do.")
        return 0

    # Load TRACE.yaml
    trace = load_trace(args.trace)
    if not trace:
        return 1

    # Get base path for resolving relative paths
    base_path = Path.cwd()

    # Build patch requests
    requests = build_patch_requests(
        report=report,
        trace=trace,
        contract_path=args.contract,
        plan_path=args.plan,
        prd_path=args.prd,
        base_path=base_path,
        clause_filter=args.clause,
        base_ref=args.base_ref,
    )

    if not requests:
        print("No artifacts found that need patches.")
        if args.clause:
            print(f"(Filtered to clause: {args.clause})")
        return 0

    print(f"Found {len(requests)} artifact(s) needing patches")
    print()

    # Generate patches
    results = []
    for i, request in enumerate(requests, 1):
        print(f"[{i}/{len(requests)}] Generating patch for {request.artifact_path}...")

        if args.verbose or args.dry_run:
            print("-" * 60)
            print("PROMPT:")
            print(build_prompt(request)[:1000] + "..." if len(build_prompt(request)) > 1000 else build_prompt(request))
            print("-" * 60)

        result = generate_patch(request, args.model, args.dry_run)
        results.append(result)

        if result.error:
            print(f"  ERROR: {result.error}")
        elif result.patch_content:
            output_path = write_patch(result, args.output)
            if output_path:
                print(f"  Wrote: {output_path}")

    # Summary
    print()
    print("=" * 60)
    print("SUMMARY")
    print("=" * 60)

    successful = [r for r in results if r.patch_content]
    failed = [r for r in results if r.error and "DRY RUN" not in r.error]

    print(f"Total requests: {len(results)}")
    print(f"Patches generated: {len(successful)}")
    print(f"Failed: {len(failed)}")

    if successful:
        print()
        print("Generated patches:")
        for result in successful:
            patch_name = f"{result.clause_id}_{result.artifact_path.replace('/', '_').replace('#', '_')}.patch"
            print(f"  - {args.output / patch_name}")
        print()
        print("To apply a patch:")
        print(f"  git apply {args.output}/<patch-file>")

    if failed:
        print()
        print("Failed patches:")
        for result in failed:
            print(f"  - {result.clause_id} / {result.artifact_path}: {result.error}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
