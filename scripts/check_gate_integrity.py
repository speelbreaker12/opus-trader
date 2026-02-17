#!/usr/bin/env python3
"""Gate integrity linter — heuristic scan for order-entrypoint calls
that lack nearby gate/guard signals.

Exit codes:
  0 — no findings (or config missing)
  1 — configuration error (invalid regex, malformed YAML)
  2 — findings detected

This is a defense-in-depth lint. The canonical enforcement is the 8-gate
pipeline in build_order_intent(). This linter catches code that bypasses
the chokepoint entirely.
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

try:
    import yaml  # type: ignore[import-untyped]

    HAS_YAML = True
except ImportError:
    HAS_YAML = False


# ── Minimal YAML fallback ──────────────────────────────────────────
def _parse_yaml_list(text: str, key: str) -> list[str]:
    """Extract a list of strings from a simple YAML key."""
    out: list[str] = []
    in_key = False
    for line in text.splitlines():
        stripped = line.strip()
        if stripped == f"{key}:" or stripped.startswith(f"{key}:"):
            in_key = True
            continue
        if in_key:
            if stripped.startswith("- "):
                val = stripped[2:].strip()
                # Strip inline comments BEFORE quote-stripping
                comment_idx = val.find("  #")
                if comment_idx != -1:
                    val = val[:comment_idx].strip()
                val = val.strip("'\"")
                out.append(val)
            elif stripped and not stripped.startswith("#"):
                break
    return out


def _parse_yaml_int(text: str, key: str, default: int) -> int:
    for line in text.splitlines():
        stripped = line.strip()
        if stripped.startswith(f"{key}:"):
            val = stripped.split(":", 1)[1].strip()
            try:
                return int(val)
            except ValueError:
                return default
    return default


def load_config(root: Path) -> dict:
    config_path = root / ".gates" / "gate_integrity.yml"
    if not config_path.is_file():
        return {}

    raw = config_path.read_text(encoding="utf-8")

    if HAS_YAML:
        with open(config_path, encoding="utf-8") as f:
            return yaml.safe_load(f) or {}

    # Fallback: minimal parser
    return {
        "lookback_lines": _parse_yaml_int(raw, "lookback_lines", 60),
        "order_call_patterns": _parse_yaml_list(raw, "order_call_patterns"),
        "gate_patterns": _parse_yaml_list(raw, "gate_patterns"),
        "ignore_path_regexes": _parse_yaml_list(raw, "ignore_path_regexes"),
    }


# ── Scanning ───────────────────────────────────────────────────────

SOURCE_EXTENSIONS = {".rs", ".py"}


def should_skip(path: Path, ignore_res: list[re.Pattern[str]]) -> bool:
    s = str(path)
    return any(r.search(s) for r in ignore_res)


def is_fn_definition(line: str, match_start: int) -> bool:
    """Return True if the matched pattern sits inside a function definition.

    Handles both Rust (`fn name`) and Python (`def name`).
    """
    prefix = line[:match_start].rstrip()
    # Rust: `fn place_order(`, `pub fn place_order(`, `pub(crate) fn place_order(`
    if re.search(r'\bfn\s*$', prefix):
        return True
    # Python: `def place_order(`, `async def place_order(`
    if re.search(r'\bdef\s*$', prefix):
        return True
    return False


def scan_file(
    path: Path,
    order_res: list[re.Pattern[str]],
    gate_res: list[re.Pattern[str]],
    lookback: int,
) -> list[dict]:
    findings: list[dict] = []
    try:
        lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
    except OSError:
        return findings

    for lineno, line in enumerate(lines):
        for order_re in order_res:
            m = order_re.search(line)
            if not m:
                continue

            # Skip comments and function definitions (not actual calls)
            stripped = line.lstrip()
            if stripped.startswith("//") or (stripped.startswith("#") and not stripped.startswith("#[")):
                continue
            if is_fn_definition(line, m.start()):
                continue

            # Look back for gate signals
            window_start = max(0, lineno - lookback)
            window = "\n".join(lines[window_start:lineno + 1])
            gate_found = any(g.search(window) for g in gate_res)

            if not gate_found:
                findings.append({
                    "file": str(path),
                    "line": lineno + 1,
                    "text": line.strip(),
                    "pattern": order_re.pattern,
                })
    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Gate integrity linter")
    parser.add_argument("--root", default=".", help="Repository root")
    parser.add_argument("--config", default=None, help="Config file override")
    args = parser.parse_args()

    root = Path(args.root).resolve()

    if args.config:
        config_path = Path(args.config)
        if HAS_YAML:
            with open(config_path, encoding="utf-8") as f:
                config = yaml.safe_load(f) or {}
        else:
            raw = config_path.read_text(encoding="utf-8")
            config = {
                "lookback_lines": _parse_yaml_int(raw, "lookback_lines", 60),
                "order_call_patterns": _parse_yaml_list(raw, "order_call_patterns"),
                "gate_patterns": _parse_yaml_list(raw, "gate_patterns"),
                "ignore_path_regexes": _parse_yaml_list(raw, "ignore_path_regexes"),
            }
    else:
        config = load_config(root)

    if not config:
        print("[gate_integrity] INFO: no .gates/gate_integrity.yml found, skipping", file=sys.stderr)
        return 0

    order_patterns = config.get("order_call_patterns", [])
    gate_patterns = config.get("gate_patterns", [])
    lookback = config.get("lookback_lines", 60)
    ignore_patterns = config.get("ignore_path_regexes", [])

    if not order_patterns:
        print("[gate_integrity] INFO: no order_call_patterns configured, skipping", file=sys.stderr)
        return 0

    if not gate_patterns:
        print("[gate_integrity] INFO: no gate_patterns configured, skipping", file=sys.stderr)
        return 0

    try:
        order_res = [re.compile(p) for p in order_patterns]
        gate_res = [re.compile(p) for p in gate_patterns]
        ignore_res = [re.compile(p) for p in ignore_patterns]
    except re.error as e:
        print(f"[gate_integrity] ERROR: invalid regex in config: {e}", file=sys.stderr)
        return 1

    all_findings: list[dict] = []
    scanned = 0

    for dirpath, dirnames, filenames in os.walk(root):
        # Prune well-known build/vcs directories in-place for walk efficiency.
        # This is separate from ignore_path_regexes (which filters relative paths
        # after walk); both are needed — pruning avoids descending at all.
        dirnames[:] = [
            d for d in dirnames
            if d not in {"target", ".git", "node_modules", ".venv", "__pycache__"}
        ]

        for fname in filenames:
            fpath = Path(dirpath) / fname
            if fpath.suffix not in SOURCE_EXTENSIONS:
                continue
            try:
                rel = fpath.relative_to(root)
            except ValueError:
                continue  # symlink outside root — skip
            if should_skip(rel, ignore_res):
                continue

            findings = scan_file(fpath, order_res, gate_res, lookback)
            all_findings.extend(findings)
            scanned += 1

    print(f"[gate_integrity] scanned {scanned} files", file=sys.stderr)

    if all_findings:
        print(f"[gate_integrity] FINDINGS: {len(all_findings)} order-entrypoint call(s) without nearby gate signal", file=sys.stderr)
        for f in all_findings:
            print(f"  {f['file']}:{f['line']}: {f['text']}", file=sys.stderr)
        return 2

    print("[gate_integrity] OK: no ungated order-entrypoint calls found", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
