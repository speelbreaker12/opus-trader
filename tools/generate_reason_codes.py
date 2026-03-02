#!/usr/bin/env python3
"""Generate Rust and Python reason/status code types from the status manifest."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = ROOT / "specs/status/status_reason_registries_manifest.json"

DEFAULT_OUTPUTS = {
    "rust_status": Path("crates/soldier_core/src/status_codes_generated.rs"),
    "rust_reject": Path("crates/soldier_core/src/execution/reject_reason_generated.rs"),
    "python": Path("tools/generated_status_reason_codes.py"),
}

SPECIAL_SEGMENTS = {
    "REDUCEONLY": "ReduceOnly",
    "KILL": "Kill",
    "OPEN": "Open",
    "WS": "Ws",
    "MM": "Mm",
    "F1": "F1",
    "L2": "L2",
    "IOC": "Ioc",
    "DEV": "Dev",
    "STAGING": "Staging",
    "PAPER": "Paper",
    "LIVE": "Live",
    "IDLE": "Idle",
    "HTTP": "Http",
    "RISKSTATE": "RiskState",
}


@dataclass(frozen=True)
class ReasonEntry:
    variant: str
    token: str


@dataclass(frozen=True)
class ModeReasonMetaEntry:
    code: str
    variant: str
    display: str
    latched: bool
    unblock_type: str
    unblock_condition: str
    tier: str


def read_manifest(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def rust_str(value: str) -> str:
    return json.dumps(value)


def python_str(value: str) -> str:
    return json.dumps(value)


def pascal_to_shouty(name: str) -> str:
    s = re.sub(r"(?<=[a-z0-9])(?=[A-Z])", "_", name)
    s = re.sub(r"(?<=[A-Z])(?=[A-Z][a-z])", "_", s)
    return s.upper()


def code_to_rust_variant(code: str) -> str:
    parts = [p for p in code.split("_") if p]
    rendered: list[str] = []
    for part in parts:
        if part in SPECIAL_SEGMENTS:
            rendered.append(SPECIAL_SEGMENTS[part])
        elif part.isdigit():
            rendered.append(part)
        else:
            rendered.append(part[:1] + part[1:].lower())
    candidate = "".join(rendered)
    if not candidate:
        raise ValueError(f"unable to derive Rust variant from code: {code}")
    if candidate[0].isdigit():
        candidate = f"N{candidate}"
    return candidate


def value_to_rust_variant(value: str) -> str:
    if "_" in value:
        return code_to_rust_variant(value)
    if re.match(r"^[A-Z0-9_]+$", value):
        return code_to_rust_variant(value)
    if re.match(r"^[A-Za-z][A-Za-z0-9]*$", value):
        return value
    raise ValueError(f"unsupported enum value for Rust variant conversion: {value}")


def ensure_unique_variants(entries: list[ReasonEntry], enum_name: str) -> None:
    seen: dict[str, str] = {}
    for entry in entries:
        prior = seen.get(entry.variant)
        if prior is not None and prior != entry.token:
            raise ValueError(
                f"duplicate Rust variant {entry.variant} in {enum_name}: {prior} vs {entry.token}"
            )
        seen[entry.variant] = entry.token


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


def registry_values(registries: dict[str, Any], key: str) -> list[str]:
    if key not in registries:
        raise KeyError(f"manifest missing registry: {key}")
    values = normalize_code_list(registries[key])
    if not values:
        raise ValueError(f"registry {key} has no values")
    return values


def entry_list(values: list[str]) -> list[ReasonEntry]:
    out = [ReasonEntry(variant=value_to_rust_variant(v), token=v) for v in values]
    return out


def reject_entry_list(values: list[str]) -> list[ReasonEntry]:
    out = [ReasonEntry(variant=v, token=v) for v in values]
    ensure_unique_variants(out, "RejectReasonCode")
    return out


def render_rust_enum(
    name: str,
    entries: list[ReasonEntry],
    *,
    serde_token: callable,
    allow_variant_names: bool = False,
) -> list[str]:
    ensure_unique_variants(entries, name)

    out: list[str] = []
    out.append("#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]")
    if allow_variant_names:
        out.append("#[allow(clippy::enum_variant_names)]")
    out.append(f"pub enum {name} {{")
    for entry in entries:
        out.append(f"    #[serde(rename = {rust_str(serde_token(entry.token))})]")
        out.append(f"    {entry.variant},")
        out.append("")
    out.pop()
    out.append("}")
    out.append("")
    out.append(f"impl {name} {{")
    out.append("    pub const ALL: &'static [Self] = &[")
    for entry in entries:
        out.append(f"        Self::{entry.variant},")
    out.append("    ];")
    out.append("")
    out.append("    pub const fn as_str(self) -> &'static str {")
    out.append("        match self {")
    for entry in entries:
        out.append(f"            Self::{entry.variant} => {rust_str(entry.token)},")
    out.append("        }")
    out.append("    }")
    out.append("}")
    return out


def render_rust_reject_enum(entries: list[ReasonEntry]) -> str:
    ensure_unique_variants(entries, "RejectReasonCode")

    lines: list[str] = [
        "// @generated by tools/generate_reason_codes.py",
        f"// source: {MANIFEST_PATH.relative_to(ROOT)}",
        "// DO NOT EDIT.",
        "",
        "#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, serde::Serialize, serde::Deserialize)]",
        "pub enum RejectReasonCode {",
    ]

    for entry in entries:
        wire = pascal_to_shouty(entry.token)
        lines.append(f"    #[serde(rename = {rust_str(wire)})]")
        lines.append(f"    {entry.variant},")
        lines.append("")
    lines.pop()
    lines.extend(
        [
            "}",
            "",
            "impl RejectReasonCode {",
            "    pub const ALL: &'static [Self] = &[",
        ]
    )
    for entry in entries:
        lines.append(f"        Self::{entry.variant},")
    lines.extend(
        [
            "    ];",
            "",
            "    /// Contract token from the manifest.",
            "    pub const fn as_str(self) -> &'static str {",
            "        match self {",
        ]
    )
    for entry in entries:
        lines.append(f"            Self::{entry.variant} => {rust_str(entry.token)},")
    lines.extend(
        [
            "        }",
            "    }",
            "",
            "    /// Current serde / wire representation.",
            "    pub const fn wire_str(self) -> &'static str {",
            "        match self {",
        ]
    )
    for entry in entries:
        wire = pascal_to_shouty(entry.token)
        lines.append(f"            Self::{entry.variant} => {rust_str(wire)},")
    lines.extend(["        }", "    }", "}"])

    return "\n".join(lines) + "\n"


def mode_meta_entries(mode_reasons: dict[str, Any]) -> list[ModeReasonMetaEntry]:
    out: list[ModeReasonMetaEntry] = []
    for tier in ("Kill", "ReduceOnly"):
        items = mode_reasons.get(tier)
        if not isinstance(items, list):
            raise ValueError(f"ModeReasonCode.{tier} must be a list")
        for item in items:
            if not isinstance(item, dict):
                raise ValueError(f"ModeReasonCode.{tier} entry must be object")
            code = item.get("code")
            display = item.get("display")
            latched = item.get("latched")
            unblock = item.get("unblock")
            if not isinstance(code, str):
                raise ValueError(f"ModeReasonCode.{tier} entry missing code string")
            if not isinstance(display, str):
                raise ValueError(f"ModeReasonCode.{tier}.{code} missing display string")
            if not isinstance(latched, bool):
                raise ValueError(f"ModeReasonCode.{tier}.{code} missing latched bool")
            if not isinstance(unblock, dict):
                raise ValueError(f"ModeReasonCode.{tier}.{code} missing unblock object")
            unblock_type = unblock.get("type")
            unblock_condition = unblock.get("condition")
            if not isinstance(unblock_type, str) or not isinstance(unblock_condition, str):
                raise ValueError(f"ModeReasonCode.{tier}.{code} unblock fields invalid")
            out.append(
                ModeReasonMetaEntry(
                    code=code,
                    variant=code_to_rust_variant(code),
                    display=display,
                    latched=latched,
                    unblock_type=unblock_type,
                    unblock_condition=unblock_condition,
                    tier=tier,
                )
            )
    return out


def render_rust_status_codes(registries: dict[str, Any]) -> str:
    trading_mode_entries = entry_list(registry_values(registries, "TradingMode"))
    deployment_entries = entry_list(registry_values(registries, "DeploymentEnvironment"))
    risk_state_entries = entry_list(registry_values(registries, "RiskState"))
    f1_cert_entries = entry_list(registry_values(registries, "F1CertState"))

    mode_meta = mode_meta_entries(registries.get("ModeReasonCode", {}))
    mode_entries = [ReasonEntry(variant=item.variant, token=item.code) for item in mode_meta]

    open_permission_entries = entry_list(registry_values(registries, "OpenPermissionReasonCode"))
    owner_state_entries = entry_list(registry_values(registries, "OwnerStateCode"))

    lines: list[str] = [
        "// @generated by tools/generate_reason_codes.py",
        f"// source: {MANIFEST_PATH.relative_to(ROOT)}",
        "// DO NOT EDIT.",
        "",
    ]

    lines.extend(
        render_rust_enum(
            "TradingMode",
            trading_mode_entries,
            serde_token=lambda token: token,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "DeploymentEnvironment",
            deployment_entries,
            serde_token=lambda token: token,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "RiskState",
            risk_state_entries,
            serde_token=lambda token: token,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "F1CertState",
            f1_cert_entries,
            serde_token=lambda token: token,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "ModeReasonCode",
            mode_entries,
            serde_token=lambda token: token,
            allow_variant_names=True,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "OpenPermissionReasonCode",
            open_permission_entries,
            serde_token=lambda token: token,
            allow_variant_names=True,
        )
    )
    lines.append("")
    lines.extend(
        render_rust_enum(
            "OwnerStateCode",
            owner_state_entries,
            serde_token=lambda token: token,
            allow_variant_names=True,
        )
    )
    lines.append("")
    lines.extend(
        [
            "#[derive(Debug, Clone, Copy, PartialEq, Eq)]",
            "pub struct UnblockMeta {",
            "    pub unblock_type: &'static str,",
            "    pub condition: &'static str,",
            "}",
            "",
            "#[derive(Debug, Clone, Copy, PartialEq, Eq)]",
            "pub struct ModeReasonMeta {",
            "    pub display: &'static str,",
            "    pub latched: bool,",
            "    pub unblock: UnblockMeta,",
            "    pub tier: TradingMode,",
            "}",
            "",
            "impl ModeReasonCode {",
            "    pub const fn meta(self) -> ModeReasonMeta {",
            "        match self {",
        ]
    )
    for item in mode_meta:
        lines.extend(
            [
                f"            Self::{item.variant} => ModeReasonMeta {{",
                f"                display: {rust_str(item.display)},",
                f"                latched: {str(item.latched).lower()},",
                "                unblock: UnblockMeta {",
                f"                    unblock_type: {rust_str(item.unblock_type)},",
                f"                    condition: {rust_str(item.unblock_condition)},",
                "                },",
                f"                tier: TradingMode::{item.tier},",
                "            },",
            ]
        )
    lines.extend(["        }", "    }", "}"])

    return "\n".join(lines) + "\n"


def enum_member_name(token: str) -> str:
    if re.match(r"^[A-Z][A-Z0-9_]*$", token):
        return token
    return pascal_to_shouty(token)


def render_python_enum(name: str, values: list[str]) -> list[str]:
    lines = [f"class {name}(str, Enum):"]
    for value in values:
        member = enum_member_name(value)
        lines.append(f"    {member} = {python_str(value)}")
    return lines


def render_python_module(manifest: dict[str, Any]) -> str:
    registries = manifest.get("registries", {})

    trading_mode = registry_values(registries, "TradingMode")
    deployment = registry_values(registries, "DeploymentEnvironment")
    risk_state = registry_values(registries, "RiskState")
    f1_state = registry_values(registries, "F1CertState")
    reject_values = registry_values(registries, "RejectReasonCode")
    open_perm_values = registry_values(registries, "OpenPermissionReasonCode")
    owner_state_values = registry_values(registries, "OwnerStateCode")

    mode_meta = mode_meta_entries(registries.get("ModeReasonCode", {}))
    mode_values = [item.code for item in mode_meta]

    lines = [
        "# @generated by tools/generate_reason_codes.py",
        f"# source: {MANIFEST_PATH.relative_to(ROOT)}",
        "# DO NOT EDIT.",
        "",
        "from __future__ import annotations",
        "",
        "from dataclasses import dataclass",
        "from enum import Enum",
        "from typing import Final",
        "",
    ]

    lines.extend(render_python_enum("TradingMode", trading_mode))
    lines.append("")
    lines.extend(render_python_enum("DeploymentEnvironment", deployment))
    lines.append("")
    lines.extend(render_python_enum("RiskState", risk_state))
    lines.append("")
    lines.extend(render_python_enum("F1CertState", f1_state))
    lines.append("")
    lines.extend(render_python_enum("ModeReasonCode", mode_values))
    lines.append("")
    lines.extend(render_python_enum("OpenPermissionReasonCode", open_perm_values))
    lines.append("")
    lines.extend(render_python_enum("OwnerStateCode", owner_state_values))
    lines.append("")
    lines.extend(render_python_enum("RejectReasonCode", reject_values))
    lines.append("")
    lines.extend(
        [
            "@dataclass(frozen=True)",
            "class UnblockMeta:",
            "    unblock_type: str",
            "    condition: str",
            "",
            "",
            "@dataclass(frozen=True)",
            "class ModeReasonMeta:",
            "    display: str",
            "    latched: bool",
            "    unblock: UnblockMeta",
            "    tier: TradingMode",
            "",
            "",
            "MODE_REASON_META: Final[dict[ModeReasonCode, ModeReasonMeta]] = {",
        ]
    )

    for item in mode_meta:
        member = enum_member_name(item.code)
        lines.extend(
            [
                f"    ModeReasonCode.{member}: ModeReasonMeta(",
                f"        display={python_str(item.display)},",
                f"        latched={str(item.latched)},",
                "        unblock=UnblockMeta(",
                f"            unblock_type={python_str(item.unblock_type)},",
                f"            condition={python_str(item.unblock_condition)},",
                "        ),",
                f"        tier=TradingMode.{enum_member_name(item.tier)},",
                "    ),",
            ]
        )
    lines.extend(["}", ""])

    lines.extend(
        [
            "OPEN_PERMISSION_REASON_CODES: Final[frozenset[str]] = frozenset(",
            "    item.value for item in OpenPermissionReasonCode",
            ")",
            "",
            "DECISION_A_LATCH_REASON: Final[str] = ModeReasonCode.REDUCEONLY_OPEN_PERMISSION_LATCHED.value",
        ]
    )

    return "\n".join(lines) + "\n"


def resolve_output_paths(manifest: dict[str, Any]) -> dict[str, Path]:
    out = {key: ROOT / rel for key, rel in DEFAULT_OUTPUTS.items()}

    codegen = manifest.get("codegen")
    if not isinstance(codegen, dict):
        return out

    outputs = codegen.get("outputs")
    if not isinstance(outputs, dict):
        return out

    for key in DEFAULT_OUTPUTS:
        raw = outputs.get(key)
        if isinstance(raw, str) and raw:
            out[key] = ROOT / raw

    return out


def render_outputs(manifest: dict[str, Any]) -> dict[str, str]:
    registries = manifest.get("registries")
    if not isinstance(registries, dict):
        raise ValueError("manifest.registries must be an object")

    reject_values = registry_values(registries, "RejectReasonCode")
    reject_entries = reject_entry_list(reject_values)

    return {
        "rust_reject": render_rust_reject_enum(reject_entries),
        "rust_status": render_rust_status_codes(registries),
        "python": render_python_module(manifest),
    }


def write_outputs(paths: dict[str, Path], rendered: dict[str, str]) -> int:
    changed = 0
    for key, content in rendered.items():
        path = paths[key]
        path.parent.mkdir(parents=True, exist_ok=True)
        current = path.read_text(encoding="utf-8") if path.exists() else None
        if current != content:
            path.write_text(content, encoding="utf-8")
            changed += 1
            print(f"updated: {path.relative_to(ROOT)}")
        else:
            print(f"ok: {path.relative_to(ROOT)}")
    return changed


def check_outputs(paths: dict[str, Path], rendered: dict[str, str]) -> int:
    stale: list[str] = []
    for key, content in rendered.items():
        path = paths[key]
        if not path.exists():
            stale.append(f"missing: {path.relative_to(ROOT)}")
            continue
        current = path.read_text(encoding="utf-8")
        if current != content:
            stale.append(f"stale: {path.relative_to(ROOT)}")

    if stale:
        print("reason-code generation drift detected:", file=sys.stderr)
        for item in stale:
            print(f"  - {item}", file=sys.stderr)
        print(
            "run `python tools/generate_reason_codes.py --write` to refresh generated outputs",
            file=sys.stderr,
        )
        return 1

    for key in ("rust_reject", "rust_status", "python"):
        print(f"ok: {paths[key].relative_to(ROOT)}")
    return 0


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--write", action="store_true", help="write generated outputs to disk")
    mode.add_argument("--check", action="store_true", help="fail if generated outputs are stale")
    parser.add_argument(
        "--manifest",
        type=Path,
        default=MANIFEST_PATH,
        help=f"manifest path (default: {MANIFEST_PATH.relative_to(ROOT)})",
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    manifest_path = args.manifest
    if not manifest_path.is_absolute():
        manifest_path = ROOT / manifest_path

    if not manifest_path.exists():
        print(f"missing manifest: {manifest_path}", file=sys.stderr)
        return 2

    manifest = read_manifest(manifest_path)
    output_paths = resolve_output_paths(manifest)
    rendered = render_outputs(manifest)

    if args.write:
        write_outputs(output_paths, rendered)
        return 0

    return check_outputs(output_paths, rendered)


if __name__ == "__main__":
    raise SystemExit(main())
