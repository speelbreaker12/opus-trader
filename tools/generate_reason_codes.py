#!/usr/bin/env python3
"""
Generate Rust/Python reason-code artifacts from status reason registries manifest.

Usage:
  python tools/generate_reason_codes.py --write
  python tools/generate_reason_codes.py --check
"""

from __future__ import annotations

import argparse
import difflib
import json
import re
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
DEFAULT_MANIFEST = ROOT / "specs/status/status_reason_registries_manifest.json"

DEFAULT_OUTPUTS = {
    "rust_status": "crates/soldier_core/src/status_codes_generated.rs",
    "rust_reject": "crates/soldier_core/src/execution/reject_reason_generated.rs",
    "python": "tools/generated_status_reason_codes.py",
}

CANONICAL_DECISION_A_LATCH = "REDUCEONLY_OPEN_PERMISSION_LATCHED"


def fail(msg: str) -> "NoReturn":
    raise SystemExit(f"FAIL: {msg}")


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        fail(f"manifest not found: {path}")
    except json.JSONDecodeError as ex:
        fail(f"manifest JSON parse error ({path}): {ex}")


def normalize_code_list(value: Any) -> list[str]:
    if isinstance(value, dict):
        if "values" in value:
            return normalize_code_list(value["values"])
        code = value.get("code")
        return [code] if isinstance(code, str) else []
    if isinstance(value, list):
        out: list[str] = []
        for item in value:
            if isinstance(item, str):
                out.append(item)
            elif isinstance(item, dict):
                code = item.get("code")
                if isinstance(code, str):
                    out.append(code)
        return out
    return []


def normalize_structured_codes(value: Any, *, context: str) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if not isinstance(value, list):
        fail(f"{context} must be a list")
    for item in value:
        if isinstance(item, str):
            out.append(
                {
                    "code": item,
                    "display": item,
                    "latched": False,
                    "unblock_type": "AUTO",
                    "unblock_condition": "",
                }
            )
            continue
        if not isinstance(item, dict):
            fail(f"{context} entries must be string or object")
        code = item.get("code")
        if not isinstance(code, str) or not code:
            fail(f"{context} object entry missing non-empty 'code'")
        unblock = item.get("unblock")
        unblock_type = "AUTO"
        unblock_condition = ""
        if isinstance(unblock, dict):
            if isinstance(unblock.get("type"), str):
                unblock_type = unblock["type"]
            if isinstance(unblock.get("condition"), str):
                unblock_condition = unblock["condition"]
        display = item.get("display") if isinstance(item.get("display"), str) else code
        latched = bool(item.get("latched", False))
        out.append(
            {
                "code": code,
                "display": display,
                "latched": latched,
                "unblock_type": unblock_type,
                "unblock_condition": unblock_condition,
            }
        )
    return out


def words_from_token(token: str) -> list[str]:
    if re.search(r"[^A-Za-z0-9]", token):
        return [part for part in re.split(r"[^A-Za-z0-9]+", token) if part]
    words = re.findall(r"[A-Z]+(?=[A-Z][a-z0-9]|$)|[A-Z]?[a-z0-9]+", token)
    return words if words else [token]


def to_pascal(token: str) -> str:
    words = words_from_token(token)
    out = "".join(word[:1].upper() + word[1:].lower() for word in words)
    if not out:
        fail(f"cannot derive Rust identifier from empty token {token!r}")
    if out[0].isdigit():
        out = f"V{out}"
    return out


def pascal_to_shouty(name: str) -> str:
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    return s.upper()


def rust_str(value: str) -> str:
    # JSON-style \\uXXXX escapes are invalid in Rust string literals.
    # Convert them to Rust's \\u{XXXX} form while keeping ASCII-only output.
    dumped = json.dumps(value, ensure_ascii=True)
    return re.sub(r"\\u([0-9a-fA-F]{4})", r"\\u{\1}", dumped)


def py_str(value: str) -> str:
    return json.dumps(value, ensure_ascii=True)


def render_simple_enum(enum_name: str, values: list[str]) -> str:
    variants: list[tuple[str, str]] = []
    seen: set[str] = set()
    for token in values:
        variant = to_pascal(token)
        if variant in seen:
            fail(f"duplicate variant name {variant!r} in {enum_name}")
        seen.add(variant)
        variants.append((variant, token))

    lines: list[str] = []
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    lines.append(f"pub enum {enum_name} {{")
    for variant, token in variants:
        lines.append(f"    #[serde(rename = {rust_str(token)})]")
        lines.append(f"    {variant},")
    lines.append("}")
    lines.append("")
    lines.append(f"impl {enum_name} {{")
    lines.append("    pub const ALL: &'static [Self] = &[")
    for variant, _token in variants:
        lines.append(f"        Self::{variant},")
    lines.append("    ];")
    lines.append("")
    lines.append("    pub const fn as_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, token in variants:
        lines.append(f"            Self::{variant} => {rust_str(token)},")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_mode_reason_enum(
    kill: list[dict[str, Any]],
    reduce_only: list[dict[str, Any]],
) -> str:
    entries: list[tuple[str, dict[str, Any], str]] = []
    seen_variants: set[str] = set()

    def push(entry: dict[str, Any], tier: str) -> None:
        token = entry["code"]
        variant = to_pascal(token)
        if variant in seen_variants:
            fail(f"duplicate ModeReasonCode variant {variant!r}")
        seen_variants.add(variant)
        entries.append((variant, entry, tier))

    for item in kill:
        push(item, "Kill")
    for item in reduce_only:
        push(item, "ReduceOnly")

    lines: list[str] = []
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    lines.append("pub enum ModeReasonCode {")
    for variant, entry, _tier in entries:
        lines.append(f"    #[serde(rename = {rust_str(entry['code'])})]")
        lines.append(f"    {variant},")
    lines.append("}")
    lines.append("")
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq)]")
    lines.append("pub struct UnblockMeta {")
    lines.append("    pub unblock_type: &'static str,")
    lines.append("    pub condition: &'static str,")
    lines.append("}")
    lines.append("")
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq)]")
    lines.append("pub struct ModeReasonMeta {")
    lines.append("    pub display: &'static str,")
    lines.append("    pub latched: bool,")
    lines.append("    pub unblock: UnblockMeta,")
    lines.append("    pub tier: TradingMode,")
    lines.append("}")
    lines.append("")
    lines.append("impl ModeReasonCode {")
    lines.append("    pub const ALL: &'static [Self] = &[")
    for variant, _entry, _tier in entries:
        lines.append(f"        Self::{variant},")
    lines.append("    ];")
    lines.append("")
    lines.append("    pub const fn as_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, entry, _tier in entries:
        lines.append(f"            Self::{variant} => {rust_str(entry['code'])},")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    pub const fn meta(self) -> ModeReasonMeta {")
    lines.append("        match self {")
    for variant, entry, tier in entries:
        lines.append(f"            Self::{variant} => ModeReasonMeta {{")
        lines.append(f"                display: {rust_str(entry['display'])},")
        lines.append(f"                latched: {'true' if entry['latched'] else 'false'},")
        lines.append("                unblock: UnblockMeta {")
        lines.append(f"                    unblock_type: {rust_str(entry['unblock_type'])},")
        lines.append(f"                    condition: {rust_str(entry['unblock_condition'])},")
        lines.append("                },")
        lines.append(f"                tier: TradingMode::{to_pascal(tier)},")
        lines.append("            },")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_open_permission_enum(open_permission: list[dict[str, Any]]) -> str:
    entries: list[tuple[str, dict[str, Any]]] = []
    seen: set[str] = set()
    for entry in open_permission:
        variant = to_pascal(entry["code"])
        if variant in seen:
            fail(f"duplicate OpenPermissionReasonCode variant {variant!r}")
        seen.add(variant)
        entries.append((variant, entry))

    lines: list[str] = []
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    lines.append("pub enum OpenPermissionReasonCode {")
    for variant, entry in entries:
        lines.append(f"    #[serde(rename = {rust_str(entry['code'])})]")
        lines.append(f"    {variant},")
    lines.append("}")
    lines.append("")
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq)]")
    lines.append("pub struct OpenPermissionReasonMeta {")
    lines.append("    pub display: &'static str,")
    lines.append("    pub unblock: UnblockMeta,")
    lines.append("}")
    lines.append("")
    lines.append("impl OpenPermissionReasonCode {")
    lines.append("    pub const ALL: &'static [Self] = &[")
    for variant, _entry in entries:
        lines.append(f"        Self::{variant},")
    lines.append("    ];")
    lines.append("")
    lines.append("    pub const fn as_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, entry in entries:
        lines.append(f"            Self::{variant} => {rust_str(entry['code'])},")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    pub const fn meta(self) -> OpenPermissionReasonMeta {")
    lines.append("        match self {")
    for variant, entry in entries:
        lines.append(f"            Self::{variant} => OpenPermissionReasonMeta {{")
        lines.append(f"                display: {rust_str(entry['display'])},")
        lines.append("                unblock: UnblockMeta {")
        lines.append(f"                    unblock_type: {rust_str(entry['unblock_type'])},")
        lines.append(f"                    condition: {rust_str(entry['unblock_condition'])},")
        lines.append("                },")
        lines.append("            },")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_owner_state_enum(owner_state: list[dict[str, Any]]) -> str:
    entries: list[tuple[str, dict[str, Any]]] = []
    seen: set[str] = set()
    for entry in owner_state:
        variant = to_pascal(entry["code"])
        if variant in seen:
            fail(f"duplicate OwnerStateCode variant {variant!r}")
        seen.add(variant)
        entries.append((variant, entry))

    lines: list[str] = []
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    lines.append("pub enum OwnerStateCode {")
    for variant, entry in entries:
        lines.append(f"    #[serde(rename = {rust_str(entry['code'])})]")
        lines.append(f"    {variant},")
    lines.append("}")
    lines.append("")
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq)]")
    lines.append("pub struct OwnerStateMeta {")
    lines.append("    pub display: &'static str,")
    lines.append("}")
    lines.append("")
    lines.append("impl OwnerStateCode {")
    lines.append("    pub const ALL: &'static [Self] = &[")
    for variant, _entry in entries:
        lines.append(f"        Self::{variant},")
    lines.append("    ];")
    lines.append("")
    lines.append("    pub const fn as_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, entry in entries:
        lines.append(f"            Self::{variant} => {rust_str(entry['code'])},")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    pub const fn meta(self) -> OwnerStateMeta {")
    lines.append("        match self {")
    for variant, entry in entries:
        lines.append(f"            Self::{variant} => OwnerStateMeta {{")
        lines.append(f"                display: {rust_str(entry['display'])},")
        lines.append("            },")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines)


def render_rust_status_module(manifest: dict[str, Any]) -> str:
    regs = manifest.get("registries", {})
    trading_mode = normalize_code_list(regs.get("TradingMode", {}))
    deployment_environment = normalize_code_list(regs.get("DeploymentEnvironment", {}))
    risk_state = normalize_code_list(regs.get("RiskState", {}))
    f1_cert_state = normalize_code_list(regs.get("F1CertState", {}))
    mode_reg = regs.get("ModeReasonCode", {})
    mode_kill = normalize_structured_codes(mode_reg.get("Kill", []), context="ModeReasonCode.Kill")
    mode_reduce = normalize_structured_codes(
        mode_reg.get("ReduceOnly", []),
        context="ModeReasonCode.ReduceOnly",
    )
    open_permission = normalize_structured_codes(
        regs.get("OpenPermissionReasonCode", {}).get("values", []),
        context="OpenPermissionReasonCode.values",
    )
    owner_state = normalize_structured_codes(
        regs.get("OwnerStateCode", {}).get("values", []),
        context="OwnerStateCode.values",
    )

    lines: list[str] = []
    lines.append("// @generated by tools/generate_reason_codes.py")
    lines.append("// source: specs/status/status_reason_registries_manifest.json")
    lines.append("// DO NOT EDIT.")
    lines.append("")
    lines.append(render_simple_enum("TradingMode", trading_mode))
    lines.append(render_simple_enum("DeploymentEnvironment", deployment_environment))
    lines.append(render_simple_enum("RiskState", risk_state))
    lines.append(render_simple_enum("F1CertState", f1_cert_state))
    lines.append(render_mode_reason_enum(mode_kill, mode_reduce))
    lines.append(render_open_permission_enum(open_permission))
    lines.append(render_owner_state_enum(owner_state))
    return "\n".join(lines).rstrip() + "\n"


def render_rust_reject_module(manifest: dict[str, Any]) -> str:
    regs = manifest.get("registries", {})
    reject_values = normalize_code_list(regs.get("RejectReasonCode", {}))
    variants: list[tuple[str, str, str]] = []
    seen: set[str] = set()
    for token in reject_values:
        variant = to_pascal(token)
        if variant in seen:
            fail(f"duplicate RejectReasonCode variant {variant!r}")
        seen.add(variant)
        variants.append((variant, token, pascal_to_shouty(token)))

    lines: list[str] = []
    lines.append("// @generated by tools/generate_reason_codes.py")
    lines.append("// source: specs/status/status_reason_registries_manifest.json")
    lines.append("// DO NOT EDIT.")
    lines.append("")
    lines.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    lines.append("#[serde(rename_all = \"SCREAMING_SNAKE_CASE\")]")
    lines.append("pub enum RejectReasonCode {")
    for variant, _token, _wire in variants:
        lines.append(f"    {variant},")
    lines.append("}")
    lines.append("")
    lines.append("impl RejectReasonCode {")
    lines.append("    pub const ALL: &'static [Self] = &[")
    for variant, _token, _wire in variants:
        lines.append(f"        Self::{variant},")
    lines.append("    ];")
    lines.append("")
    lines.append("    pub const fn as_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, token, _wire in variants:
        lines.append(f"            Self::{variant} => {rust_str(token)},")
    lines.append("        }")
    lines.append("    }")
    lines.append("")
    lines.append("    pub const fn wire_str(self) -> &'static str {")
    lines.append("        match self {")
    for variant, _token, wire in variants:
        lines.append(f"            Self::{variant} => {rust_str(wire)},")
    lines.append("        }")
    lines.append("    }")
    lines.append("}")
    lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def enum_member_name(token: str) -> str:
    if re.fullmatch(r"[A-Z][A-Z0-9_]*", token):
        return token
    return pascal_to_shouty(to_pascal(token))


def render_py_enum(enum_name: str, values: list[str]) -> str:
    lines: list[str] = [f"class {enum_name}(str, Enum):"]
    for token in values:
        lines.append(f"    {enum_member_name(token)} = {py_str(token)}")
    lines.append("")
    return "\n".join(lines)


def render_python_module(manifest: dict[str, Any]) -> str:
    regs = manifest.get("registries", {})
    trading_mode = normalize_code_list(regs.get("TradingMode", {}))
    mode_reg = regs.get("ModeReasonCode", {})
    mode_kill = normalize_code_list(mode_reg.get("Kill", []))
    mode_reduce = normalize_code_list(mode_reg.get("ReduceOnly", []))
    open_permission = normalize_code_list(regs.get("OpenPermissionReasonCode", {}))
    reject = normalize_code_list(regs.get("RejectReasonCode", {}))

    lines: list[str] = []
    lines.append("# @generated by tools/generate_reason_codes.py")
    lines.append("# source: specs/status/status_reason_registries_manifest.json")
    lines.append("# DO NOT EDIT.")
    lines.append("from __future__ import annotations")
    lines.append("")
    lines.append("from enum import Enum")
    lines.append("from typing import Final")
    lines.append("")
    lines.append(render_py_enum("TradingMode", trading_mode))
    lines.append(render_py_enum("ModeReasonCode", mode_kill + mode_reduce))
    lines.append(render_py_enum("OpenPermissionReasonCode", open_permission))
    lines.append(render_py_enum("RejectReasonCode", reject))
    lines.append("MODE_REASON_CODES_KILL: Final[frozenset[str]] = frozenset({")
    for token in mode_kill:
        lines.append(f"    {py_str(token)},")
    lines.append("})")
    lines.append("")
    lines.append("MODE_REASON_CODES_REDUCEONLY: Final[frozenset[str]] = frozenset({")
    for token in mode_reduce:
        lines.append(f"    {py_str(token)},")
    lines.append("})")
    lines.append("")
    lines.append("OPEN_PERMISSION_REASON_CODES: Final[frozenset[str]] = frozenset({")
    for token in open_permission:
        lines.append(f"    {py_str(token)},")
    lines.append("})")
    lines.append("")
    lines.append("REJECT_REASON_CODES: Final[frozenset[str]] = frozenset({")
    for token in reject:
        lines.append(f"    {py_str(token)},")
    lines.append("})")
    lines.append("")
    lines.append(
        "DECISION_A_CANONICAL_LATCH_REASON: Final[str] = "
        f"{py_str(CANONICAL_DECISION_A_LATCH)}"
    )
    lines.append("")
    return "\n".join(lines).rstrip() + "\n"


def resolve_outputs(manifest: dict[str, Any]) -> dict[str, Path]:
    codegen = manifest.get("codegen", {})
    outputs = codegen.get("outputs", {})
    resolved: dict[str, Path] = {}
    for key, default_path in DEFAULT_OUTPUTS.items():
        rel = outputs.get(key, default_path)
        if not isinstance(rel, str) or not rel:
            fail(f"manifest codegen output {key!r} must be a non-empty string path")
        resolved[key] = ROOT / rel
    return resolved


def show_diff(path: Path, expected: str, actual: str) -> None:
    rel = path.relative_to(ROOT) if path.is_relative_to(ROOT) else path
    diff = difflib.unified_diff(
        actual.splitlines(),
        expected.splitlines(),
        fromfile=f"{rel} (current)",
        tofile=f"{rel} (expected)",
        lineterm="",
    )
    print("\n".join(diff))


def write_if_needed(path: Path, content: str, *, check_only: bool) -> bool:
    current = path.read_text(encoding="utf-8") if path.exists() else None
    if current == content:
        return False

    if check_only:
        if current is None:
            print(f"MISSING: {path.relative_to(ROOT)}")
        else:
            show_diff(path, content, current)
        return True

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    print(f"updated: {path.relative_to(ROOT)}")
    return True


def parse_args() -> argparse.Namespace:
    ap = argparse.ArgumentParser(description="Generate status/reason-code artifacts")
    ap.add_argument(
        "--manifest",
        default=str(DEFAULT_MANIFEST),
        help="Path to status reason registries manifest",
    )
    ap.add_argument("--write", action="store_true", help="Write generated files to disk")
    ap.add_argument("--check", action="store_true", help="Check files are up to date")
    return ap.parse_args()


def main() -> int:
    args = parse_args()
    if args.write == args.check:
        fail("provide exactly one of --write or --check")

    manifest_path = Path(args.manifest)
    if not manifest_path.is_absolute():
        manifest_path = (ROOT / manifest_path).resolve()

    manifest = load_manifest(manifest_path)
    outputs = resolve_outputs(manifest)

    rendered = {
        "rust_status": render_rust_status_module(manifest),
        "rust_reject": render_rust_reject_module(manifest),
        "python": render_python_module(manifest),
    }

    check_only = bool(args.check)
    changed = False
    for key, path in outputs.items():
        changed = write_if_needed(path, rendered[key], check_only=check_only) or changed

    if check_only and changed:
        print("reason-code generation drift detected")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
