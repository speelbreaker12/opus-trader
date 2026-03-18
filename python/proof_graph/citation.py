"""File existence and symbol checker for structured evidence citations."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Optional

from .schema import EvidenceEntry


@dataclass(frozen=True)
class CitationResult:
    valid: bool
    file_exists: bool
    line_range_valid: bool
    symbol_found: Optional[bool]  # None if check_symbol=False
    message: str


def check_citation(
    entry: EvidenceEntry,
    repo_root: Path,
    check_symbol: bool = False,
) -> CitationResult:
    """Validate file exists, line range valid, optionally check symbol presence.

    This is a utility — NOT called by validation rules (rules stay pure,
    no filesystem access). Used by init.py and available as standalone tool.
    """
    file_path = (repo_root / entry.file).resolve()
    if not file_path.is_relative_to(repo_root.resolve()):
        return CitationResult(
            valid=False,
            file_exists=False,
            line_range_valid=False,
            symbol_found=None,
            message=f"path traversal: {entry.file} resolves outside repo root",
        )
    if not file_path.is_file():
        return CitationResult(
            valid=False,
            file_exists=False,
            line_range_valid=False,
            symbol_found=None,
            message=f"file not found: {entry.file}",
        )

    try:
        lines = file_path.read_text(encoding="utf-8").splitlines()
    except OSError as e:
        return CitationResult(
            valid=False,
            file_exists=True,
            line_range_valid=False,
            symbol_found=None,
            message=f"cannot read file: {e}",
        )

    total_lines = len(lines)
    if entry.line_start < 1 or entry.line_end < entry.line_start:
        return CitationResult(
            valid=False,
            file_exists=True,
            line_range_valid=False,
            symbol_found=None,
            message=(
                f"invalid line range: {entry.line_start}-{entry.line_end} "
                f"(file has {total_lines} lines)"
            ),
        )

    if entry.line_start > total_lines or entry.line_end > total_lines:
        return CitationResult(
            valid=False,
            file_exists=True,
            line_range_valid=False,
            symbol_found=None,
            message=(
                f"line range {entry.line_start}-{entry.line_end} "
                f"exceeds file length ({total_lines} lines)"
            ),
        )

    if not check_symbol:
        return CitationResult(
            valid=True,
            file_exists=True,
            line_range_valid=True,
            symbol_found=None,
            message="ok",
        )

    # Check symbol in cited line range (1-based to 0-based)
    cited_text = "\n".join(lines[entry.line_start - 1:entry.line_end])
    found = entry.symbol in cited_text
    return CitationResult(
        valid=found,
        file_exists=True,
        line_range_valid=True,
        symbol_found=found,
        message="ok" if found else f"symbol {entry.symbol!r} not found in lines {entry.line_start}-{entry.line_end}",
    )
