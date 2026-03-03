#!/usr/bin/env python3
"""
Fail CI if /status mode/open-permission reason codes leak into Rust string literals.

Exit codes:
  0 = no leaks found
  1 = leak(s) found
  2 = setup/configuration error
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Iterable


class SetupError(RuntimeError):
    """Raised for deterministic setup/validation failures."""


def eprint(*args: object) -> None:
    print(*args, file=sys.stderr)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Detect leaked /status mode/open-permission reason code literals in Rust source."
    )
    parser.add_argument(
        "--manifest",
        default="specs/status/status_reason_registries_manifest.json",
        help="Path to status reason registries manifest",
    )
    parser.add_argument(
        "--scan-root",
        default="crates",
        help="Root directory to scan for Rust files",
    )
    parser.add_argument(
        "--allow-path",
        action="append",
        default=[],
        help="Optional repo-relative file/dir path(s) to exclude from checks",
    )
    return parser.parse_args()


def resolve_path(path_arg: str, cwd: Path) -> Path:
    path = Path(path_arg)
    if path.is_absolute():
        return path
    return (cwd / path).resolve()


def ensure_manifest_and_scan_root(manifest: Path, scan_root: Path) -> None:
    if not manifest.exists():
        raise SetupError(f"manifest does not exist: {manifest}")
    if not manifest.is_file():
        raise SetupError(f"manifest is not a file: {manifest}")
    if not scan_root.exists():
        raise SetupError(f"scan root does not exist: {scan_root}")
    if not scan_root.is_dir():
        raise SetupError(f"scan root is not a directory: {scan_root}")


def normalize_allow_paths(raw_allow_paths: Iterable[str], cwd: Path, scan_root: Path) -> set[Path]:
    allowed: set[Path] = set()
    for raw in raw_allow_paths:
        candidate = Path(raw)
        if candidate.is_absolute():
            raise SetupError(f"--allow-path must be repo-relative, got absolute path: {raw}")
        if ".." in candidate.parts:
            raise SetupError(f"--allow-path must not contain '..' segments: {raw}")

        resolved = (cwd / candidate).resolve()
        if not resolved.exists():
            raise SetupError(f"--allow-path does not exist: {raw}")

        try:
            resolved.relative_to(scan_root)
        except ValueError as ex:
            raise SetupError(
                f"--allow-path must normalize under scan root '{scan_root}': {raw}"
            ) from ex

        allowed.add(resolved)
    return allowed


def expect_dict(value: object, field: str) -> dict[str, object]:
    if not isinstance(value, dict):
        raise SetupError(f"{field} must be an object")
    return value


def expect_list(value: object, field: str) -> list[object]:
    if not isinstance(value, list):
        raise SetupError(f"{field} must be a list")
    return value


def extract_code_list(entries: list[object], field: str) -> list[str]:
    codes: list[str] = []
    for idx, entry in enumerate(entries):
        if not isinstance(entry, dict):
            raise SetupError(f"{field}[{idx}] must be an object with non-empty string 'code'")
        code = entry.get("code")
        if not isinstance(code, str) or not code.strip():
            raise SetupError(f"{field}[{idx}].code must be a non-empty string")
        codes.append(code)
    return codes


def load_forbidden_codes(manifest_path: Path) -> list[str]:
    try:
        manifest_text = manifest_path.read_text(encoding="utf-8")
    except OSError as ex:
        raise SetupError(f"failed to read manifest '{manifest_path}': {ex}") from ex

    try:
        manifest_json = json.loads(manifest_text)
    except json.JSONDecodeError as ex:
        raise SetupError(
            f"manifest is not valid JSON ({manifest_path}:{ex.lineno}:{ex.colno}): {ex.msg}"
        ) from ex

    manifest = expect_dict(manifest_json, "manifest")
    registries = expect_dict(manifest.get("registries"), "registries")

    mode_reason_code = expect_dict(
        registries.get("ModeReasonCode"),
        "registries.ModeReasonCode",
    )
    kill_entries = expect_list(
        mode_reason_code.get("Kill"),
        "registries.ModeReasonCode.Kill",
    )
    reduce_only_entries = expect_list(
        mode_reason_code.get("ReduceOnly"),
        "registries.ModeReasonCode.ReduceOnly",
    )

    open_permission_reason_code = expect_dict(
        registries.get("OpenPermissionReasonCode"),
        "registries.OpenPermissionReasonCode",
    )
    open_permission_entries = expect_list(
        open_permission_reason_code.get("values"),
        "registries.OpenPermissionReasonCode.values",
    )

    # RejectReasonCode is intentionally excluded by design.
    codes = (
        extract_code_list(kill_entries, "registries.ModeReasonCode.Kill")
        + extract_code_list(reduce_only_entries, "registries.ModeReasonCode.ReduceOnly")
        + extract_code_list(
            open_permission_entries,
            "registries.OpenPermissionReasonCode.values",
        )
    )
    return sorted(set(codes))


def is_ident_char(ch: str) -> bool:
    return ch.isalnum() or ch == "_"


def is_hex_digit(ch: str) -> bool:
    return ("0" <= ch <= "9") or ("a" <= ch <= "f") or ("A" <= ch <= "F")


def decode_rust_string_literal(raw: str) -> str:
    decoded: list[str] = []
    i = 0
    length = len(raw)

    while i < length:
        ch = raw[i]
        if ch != "\\":
            decoded.append(ch)
            i += 1
            continue

        if i + 1 >= length:
            decoded.append("\\")
            i += 1
            continue

        esc = raw[i + 1]
        if esc == "n":
            decoded.append("\n")
            i += 2
            continue
        if esc == "r":
            decoded.append("\r")
            i += 2
            continue
        if esc == "t":
            decoded.append("\t")
            i += 2
            continue
        if esc == "0":
            decoded.append("\0")
            i += 2
            continue
        if esc in {'"', "'", "\\"}:
            decoded.append(esc)
            i += 2
            continue

        if esc == "x":
            if i + 3 < length and is_hex_digit(raw[i + 2]) and is_hex_digit(raw[i + 3]):
                decoded.append(chr(int(raw[i + 2 : i + 4], 16)))
                i += 4
                continue
            # Preserve fail-closed behavior for malformed escapes by keeping the suffix.
            decoded.append("x")
            i += 2
            continue

        if esc == "u" and i + 2 < length and raw[i + 2] == "{":
            j = i + 3
            digits: list[str] = []
            valid = True
            while j < length and raw[j] != "}":
                token = raw[j]
                if token == "_":
                    j += 1
                    continue
                if not is_hex_digit(token):
                    valid = False
                    break
                digits.append(token)
                j += 1

            if valid and j < length and raw[j] == "}" and digits:
                codepoint = int("".join(digits), 16)
                if 0 <= codepoint <= 0x10FFFF:
                    decoded.append(chr(codepoint))
                    i = j + 1
                    continue

            decoded.append("u")
            i += 2
            continue

        # String continuation: backslash + newline + indentation.
        if esc == "\n":
            i += 2
            while i < length and raw[i] in {" ", "\t", "\n", "\r"}:
                i += 1
            continue
        if esc == "\r" and i + 2 < length and raw[i + 2] == "\n":
            i += 3
            while i < length and raw[i] in {" ", "\t", "\n", "\r"}:
                i += 1
            continue

        # Unknown escapes are preserved as the escaped char to avoid hiding content.
        decoded.append(esc)
        i += 2

    return "".join(decoded)


def parse_raw_string_at(source: str, index: int, current_line: int) -> tuple[int, str, int, int] | None:
    if index >= len(source):
        return None

    if source.startswith("br", index) or source.startswith("rb", index):
        prefix_end = index + 2
    elif source[index] == "r":
        prefix_end = index + 1
    else:
        return None

    hash_count = 0
    while prefix_end < len(source) and source[prefix_end] == "#":
        hash_count += 1
        prefix_end += 1

    if prefix_end >= len(source) or source[prefix_end] != '"':
        return None

    start_line = current_line
    content_start = prefix_end + 1
    closing = '"' + ("#" * hash_count)
    closing_index = source.find(closing, content_start)
    if closing_index < 0:
        consumed = source[index:]
        return None if not consumed else (start_line, "", len(source), current_line + consumed.count("\n"))

    literal_value = source[content_start:closing_index]
    consumed = source[index : closing_index + len(closing)]
    next_index = closing_index + len(closing)
    next_line = current_line + consumed.count("\n")
    return (start_line, literal_value, next_index, next_line)


def iter_rust_string_literals(source: str) -> Iterable[tuple[int, str]]:
    i = 0
    line = 1
    length = len(source)

    while i < length:
        ch = source[i]

        if ch == "\n":
            line += 1
            i += 1
            continue

        if ch == "/" and i + 1 < length:
            nxt = source[i + 1]
            if nxt == "/":
                i += 2
                while i < length and source[i] != "\n":
                    i += 1
                continue
            if nxt == "*":
                i += 2
                depth = 1
                while i < length and depth > 0:
                    c = source[i]
                    if c == "\n":
                        line += 1
                        i += 1
                        continue
                    if c == "/" and i + 1 < length and source[i + 1] == "*":
                        depth += 1
                        i += 2
                        continue
                    if c == "*" and i + 1 < length and source[i + 1] == "/":
                        depth -= 1
                        i += 2
                        continue
                    i += 1
                continue

        if ch in {"r", "b"}:
            prev = source[i - 1] if i > 0 else ""
            if not prev or not is_ident_char(prev):
                raw = parse_raw_string_at(source, i, line)
                if raw is not None:
                    start_line, value, i, line = raw
                    if value:
                        yield start_line, value
                    continue

        if ch == '"':
            start_line = line
            i += 1
            value_chars: list[str] = []
            while i < length:
                c = source[i]
                if c == "\n":
                    line += 1
                if c == "\\":
                    if i + 1 < length:
                        # Preserve escaped source form. This checker matches direct literal values.
                        value_chars.append(source[i])
                        value_chars.append(source[i + 1])
                        if source[i + 1] == "\n":
                            line += 1
                        i += 2
                        continue
                    value_chars.append(c)
                    i += 1
                    continue
                if c == '"':
                    i += 1
                    yield start_line, decode_rust_string_literal("".join(value_chars))
                    break
                value_chars.append(c)
                i += 1
            continue

        i += 1


def scan_for_leaks(scan_root: Path, forbidden: set[str], allow_paths: set[Path], cwd: Path) -> list[tuple[str, int, str]]:
    hits: list[tuple[str, int, str]] = []
    rust_files = sorted(
        (path for path in scan_root.rglob("*.rs") if path.is_file()),
        key=lambda p: p.as_posix(),
    )

    for path in rust_files:
        resolved = path.resolve()
        if any(resolved == allow or allow in resolved.parents for allow in allow_paths):
            continue

        try:
            source = path.read_text(encoding="utf-8")
        except OSError as ex:
            raise SetupError(f"failed to read Rust source '{path}': {ex}") from ex
        except UnicodeDecodeError as ex:
            raise SetupError(f"Rust source is not valid UTF-8 '{path}': {ex}") from ex

        try:
            rel = resolved.relative_to(cwd).as_posix()
        except ValueError:
            rel = resolved.as_posix()

        for line, literal in iter_rust_string_literals(source):
            if literal in forbidden:
                hits.append((rel, line, literal))

    return sorted(hits, key=lambda t: (t[0], t[1], t[2]))


def run() -> int:
    args = parse_args()
    cwd = Path.cwd().resolve()
    manifest = resolve_path(args.manifest, cwd)
    scan_root = resolve_path(args.scan_root, cwd)

    ensure_manifest_and_scan_root(manifest, scan_root)
    allow_paths = normalize_allow_paths(args.allow_path, cwd, scan_root)
    forbidden_codes = set(load_forbidden_codes(manifest))
    hits = scan_for_leaks(scan_root, forbidden_codes, allow_paths, cwd)

    if hits:
        eprint("FAIL: /status mode/open-permission reason code literals leaked into Rust source")
        for rel, line, code in hits:
            eprint(f"{rel}:{line}:{code}")
        return 1

    print("PASS: no /status mode/open-permission reason code literals leaked into Rust source")
    return 0


def main() -> int:
    try:
        return run()
    except SetupError as ex:
        eprint(f"FAIL: SETUP ERROR: {ex}")
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
