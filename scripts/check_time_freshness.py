#!/usr/bin/env python3
"""
check_time_freshness.py

Mechanical linter for TIME_FRESHNESS.yaml against CONTRACT.md.

Checks:
- Required fields per entry (including refs.runtime_acceptance_tests)
- Section/AT references exist; runtime_acceptance_tests subset of acceptance_tests
- /status coverage for ts/age/expires/lag/pXX/count_window/ms patterns
- Appendix A time/freshness params auto-detected from A.7 Summary Table
- Optional Appendix A pattern coverage (require_appendix_keys_matching/ignore_appendix_keys)

Strict mode treats warnings as errors and enforces Appendix A coverage (cannot be disabled).
"""

from __future__ import annotations
import argparse
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Set

try:
    import yaml
except Exception:
    yaml = None

HEADING_ID_RE = re.compile(r'^\s{0,3}#{1,6}\s+(?:\*\*)?(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)(?:\*\*)?')
APPENDIX_A_RE = re.compile(r'^\s{0,3}##\s+\*\*Appendix A:', re.IGNORECASE)
AT_RE = re.compile(r'\bAT-(\d{1,4})\b')
REASON_RE = re.compile(r'\b(?:KILL|REDUCEONLY)_[A-Z0-9_]+\b')
BACKTICK_RE = re.compile(r'`([A-Za-z_][A-Za-z0-9_]*)`')

REQ_FIELDS_COMMON = ["id","signal","units","critical","missing_behavior","stale_behavior","refs"]
REQ_FIELDS_FRESHNESS = ["value_field","freshness_param"]
REQ_FIELDS_STATUS_METRIC = ["status_fields"]

REQ_REFS_FIELDS = ["sections","acceptance_tests","runtime_acceptance_tests"]

def pick_default_contract_path(user_path: str) -> Path:
    if user_path:
        return Path(user_path)
    for cand in ["specs/CONTRACT.md", "CONTRACT.md"]:
        p = Path(cand)
        if p.exists():
            return p
    return Path("CONTRACT.md")

def pick_default_spec_path(user_path: str) -> Path:
    if user_path:
        return Path(user_path)
    # try common repo layouts
    for cand in [
        "specs/flows/TIME_FRESHNESS.yaml",
        "TIME_FRESHNESS.yaml",
        "gpt/TIME_FRESHNESS.yaml",
        "gpt/TIME_FRESHNESS_v9.yaml",
        "TIME_FRESHNESS_v9.yaml",
    ]:
        p = Path(cand)
        if p.exists():
            return p
    return Path("TIME_FRESHNESS.yaml")

def read_text(p: Path) -> str:
    return p.read_text(encoding="utf-8", errors="replace")

def parse_contract(contract_text: str) -> Dict[str, Any]:
    lines = contract_text.splitlines()
    headings: Set[str] = set()
    for line in lines:
        m = HEADING_ID_RE.match(line)
        if m:
            headings.add(m.group("id"))

    ats = set(f"AT-{m.group(1)}" for m in AT_RE.finditer(contract_text))
    reasons = set(REASON_RE.findall(contract_text))

    # Appendix A keys (backticked) - best effort
    app_start = None
    for i, line in enumerate(lines):
        if APPENDIX_A_RE.match(line):
            app_start = i
            break

    app_keys: Set[str] = set()
    appendix_table: Dict[str, str] = {}
    if app_start is not None:
        for line in lines[app_start:]:
            for m in BACKTICK_RE.finditer(line):
                app_keys.add(m.group(1))

        in_table = False
        for line in lines[app_start:]:
            if "A.7 Summary Table" in line:
                in_table = True
                continue
            if in_table:
                if not line.strip().startswith("|"):
                    if appendix_table:
                        break
                    continue
                parts = [p.strip() for p in line.strip().strip("|").split("|")]
                if len(parts) >= 4 and parts[0].startswith("`") and parts[0].endswith("`"):
                    param = parts[0].strip("`")
                    unit = parts[2].strip()
                    appendix_table[param] = unit

    any_keys = set(m.group(1) for m in BACKTICK_RE.finditer(contract_text))
    return {
        "lines": lines,
        "headings": headings,
        "ats": ats,
        "reasons": reasons,
        "app_keys": app_keys,
        "any_keys": any_keys,
        "appendix_table": appendix_table,
    }

def extract_status_required_fields(contract_lines: list[str]) -> dict[str, set[str]]:
    """Extract key fields referenced in the '/status response MUST include (minimum)' list in §7.0."""
    heading_re = re.compile(r'^\s{0,3}(#{1,6})\s+(?:\*\*)?(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)(?:\*\*)?\b')
    headings: list[tuple[int,int,str]] = []
    for i, line in enumerate(contract_lines, start=1):
        m = heading_re.match(line)
        if m:
            headings.append((i, len(m.group(1)), m.group('id')))
    h7 = next(((ln,lvl,sid) for ln,lvl,sid in headings if sid=='7.0'), None)
    if not h7:
        return {k:set() for k in ["ts_ms","age","expires","lag","pxx","count_window","ms"]}
    start_ln, start_lvl, _ = h7
    end_ln = len(contract_lines)
    for ln,lvl,sid in headings:
        if ln <= start_ln:
            continue
        if lvl <= start_lvl:
            end_ln = ln - 1
            break
    section = contract_lines[start_ln-1:end_ln]

    marker_idx = None
    for idx, line in enumerate(section):
        if '/status response MUST include (minimum):' in line:
            marker_idx = idx
            break
    if marker_idx is None:
        return {k:set() for k in ["ts_ms","age","expires","lag","pxx","count_window","ms"]}

    pats = {
        "ts_ms": re.compile(r'\b[a-z0-9][a-z0-9_]*_ts_ms\b'),
        "age": re.compile(r'\b[a-z0-9][a-z0-9_]*_age_(?:sec|s)\b'),
        "expires": re.compile(r'\b[a-z0-9][a-z0-9_]*_expires_at\b'),
        "lag": re.compile(r'\b[a-z0-9][a-z0-9_]*_lag_ms\b'),
        "pxx": re.compile(r'\b[a-z0-9][a-z0-9_]*_p(?:95|99)_ms\b'),
        "count_window": re.compile(r'\b[a-z0-9][a-z0-9_]*_count_\d+[smhd]\b'),
        "ms": re.compile(r'\b[a-z0-9][a-z0-9_]*_ms\b'),
    }
    out = {k:set() for k in pats.keys()}

    for line in section[marker_idx+1:]:
        if not line.strip():
            break
        if not line.lstrip().startswith('-'):
            continue
        for k,pat in pats.items():
            for m in pat.finditer(line):
                out[k].add(m.group(0))

    # generic *_ms includes *_ts_ms; subtract those
    out["ms"] = set(x for x in out["ms"] if not x.endswith("_ts_ms"))
    return out

def err(msg: str, errors: list[str]) -> None:
    errors.append(msg)

def warn(msg: str, warnings: list[str]) -> None:
    warnings.append(msg)

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", default="", help="Path to CONTRACT.md (default tries specs/CONTRACT.md then CONTRACT.md)")
    ap.add_argument("--spec", default="", help="Path to TIME_FRESHNESS*.yaml (default tries specs/flows/TIME_FRESHNESS.yaml then repo root)")
    ap.add_argument("--strict", action="store_true", help="Treat warnings as errors; enforce non-disableable coverage gates")
    args = ap.parse_args()

    if yaml is None:
        print("ERROR: PyYAML is required (pip install pyyaml).", file=sys.stderr)
        return 1

    contract_path = pick_default_contract_path(args.contract)
    spec_path = pick_default_spec_path(args.spec)

    if not contract_path.exists():
        print(f"ERROR: contract not found: {contract_path}", file=sys.stderr)
        return 1
    if not spec_path.exists():
        print(f"ERROR: spec not found: {spec_path}", file=sys.stderr)
        return 1

    contract_text = read_text(contract_path)
    contract = parse_contract(contract_text)
    status_fields = extract_status_required_fields(contract["lines"])

    spec = yaml.safe_load(read_text(spec_path))
    if not isinstance(spec, dict) or "entries" not in spec or not isinstance(spec["entries"], list):
        print("ERROR: spec must be YAML with top-level key: entries: [ ... ]", file=sys.stderr)
        return 1

    errors: list[str] = []
    warnings: list[str] = []

    coverage = spec.get("coverage") or {}
    require_patterns = coverage.get("require_appendix_keys_matching") or []
    if not isinstance(require_patterns, list):
        require_patterns = []
    require_patterns = [p for p in require_patterns if isinstance(p, str)]

    ignore_appendix_keys: Set[str] = set()
    ig = coverage.get("ignore_appendix_keys") or []
    if isinstance(ig, list):
        for k in ig:
            if isinstance(k, str):
                ignore_appendix_keys.add(k)

    # Ignore lists
    ignore_status_ts = set(coverage.get("ignore_status_ts_fields") or [])
    ignore_status_age = set(coverage.get("ignore_status_age_fields") or [])
    ignore_status_expires = set(coverage.get("ignore_status_expires_fields") or [])
    ignore_status_lag = set(coverage.get("ignore_status_lag_fields") or [])
    ignore_status_pxx = set(coverage.get("ignore_status_pxx_fields") or [])
    ignore_status_count = set(
        coverage.get("ignore_status_count_window_fields")
        or coverage.get("ignore_status_count_fields")
        or []
    )
    ignore_status_ms = set(coverage.get("ignore_status_ms_fields") or [])

    ignore_appendix_params = set(coverage.get("ignore_appendix_time_params") or [])
    ignore_appendix_no_at = set(coverage.get("ignore_appendix_time_params_without_at") or [])
    ignore_appendix_no_runtime = set(coverage.get("ignore_appendix_time_params_without_runtime_at") or [])

    # In strict mode, Appendix coverage cannot be disabled.
    # We ignore coverage.appendix_time_mode as a disable switch.
    if args.strict:
        mode = coverage.get("appendix_time_mode", "auto")
        if mode != "auto":
            err("STRICT: coverage.appendix_time_mode must be 'auto' (cannot disable Appendix-A coverage in strict).", errors)
            # We'll continue collecting other errors too.

    # Validate entries and collect coverage sets
    covered_status: Set[str] = set()
    covered_appendix_params: Dict[str, Dict[str, Set[str]]] = {}  # param -> {"ats": set, "runtime_ats": set}
    seen_ids: Set[str] = set()

    for e in spec["entries"]:
        if not isinstance(e, dict):
            err("Entry is not a mapping/dict.", errors)
            continue

        eid = e.get("id")
        if isinstance(eid, str):
            if eid in seen_ids:
                err(f"{eid}: duplicate id", errors)
            seen_ids.add(eid)

        # Required common fields
        for f in REQ_FIELDS_COMMON:
            if f not in e:
                err(f"{e.get('id','<no-id>')}: missing required field '{f}'", errors)

        # Determine entry kind
        has_freshness = "freshness_param" in e or "timestamp_field" in e
        if has_freshness:
            for f in REQ_FIELDS_FRESHNESS:
                if f not in e:
                    err(f"{e.get('id','<no-id>')}: missing required field '{f}' (freshness entry)", errors)

        if "status_fields" in e:
            if not isinstance(e["status_fields"], list):
                err(f"{e.get('id','<no-id>')}: status_fields must be a list", errors)

        # refs
        refs = e.get("refs")
        if not isinstance(refs, dict):
            err(f"{e.get('id','<no-id>')}: refs must be a dict", errors)
            continue
        for f in REQ_REFS_FIELDS:
            if f not in refs:
                err(f"{e.get('id','<no-id>')}: refs missing '{f}'", errors)

        sections = refs.get("sections") or []
        if isinstance(sections, str):
            sections = [sections]
        for s in sections:
            s2 = str(s).replace("§","").strip()
            if s2 in ("Definitions","Appendix A"):
                continue
            if re.fullmatch(r'\d+(?:\.(?:\d+|[A-Za-z]))*', s2):
                if s2 not in contract["headings"]:
                    err(f"{e.get('id')}: refs.sections includes missing heading id '{s2}'", errors)

        ats = refs.get("acceptance_tests") or []
        if isinstance(ats, str):
            ats = [ats]
        runtime_ats = refs.get("runtime_acceptance_tests") or []
        if isinstance(runtime_ats, str):
            runtime_ats = [runtime_ats]

        # AT existence
        for at in ats:
            if at not in contract["ats"]:
                err(f"{e.get('id')}: refs.acceptance_tests contains AT not in contract: {at}", errors)
        for at in runtime_ats:
            if at not in contract["ats"]:
                err(f"{e.get('id')}: refs.runtime_acceptance_tests contains AT not in contract: {at}", errors)

        # Deterministic runtime definition: runtime_ats must be subset of ats
        if set(runtime_ats) - set(ats):
            err(f"{e.get('id')}: runtime_acceptance_tests must be subset of acceptance_tests", errors)

        # Critical entries must have at least one AT
        if bool(e.get("critical", False)) and len(ats) == 0:
            err(f"{e.get('id')}: critical entry must have >=1 acceptance_tests", errors)

        # Mode reason codes must be valid tokens if present
        mrc = e.get("mode_reason_code")
        if mrc:
            if mrc not in contract["reasons"]:
                err(f"{e.get('id')}: mode_reason_code not found in contract tokens: {mrc}", errors)

        # Unit sanity (light)
        units = str(e.get("units","")).lower()
        ts_field = str(e.get("timestamp_field","") or "")
        if ts_field.endswith("_ts_ms") and "ms" not in units:
            warn(f"{e.get('id')}: timestamp_field looks like ms but units not ms: {ts_field} / {e.get('units')}", warnings)

        # Coverage contribution: status_fields + value/timestamp fields
        for sf in (e.get("status_fields") or []):
            covered_status.add(str(sf))
        for f in ["value_field","timestamp_field"]:
            v = e.get(f)
            if isinstance(v, str) and v:
                covered_status.add(v)

        # Appendix param coverage
        p = e.get("freshness_param")
        if isinstance(p, str) and p:
            bucket = covered_appendix_params.setdefault(p, {"ats": set(), "runtime_ats": set()})
            bucket["ats"].update(ats)
            bucket["runtime_ats"].update(runtime_ats)

    # Optional Appendix A key coverage (pattern-based)
    if require_patterns:
        used_params = set(covered_appendix_params.keys())
        needed: Set[str] = set()
        for k in contract["app_keys"]:
            for pat in require_patterns:
                if pat == "ttl_s":
                    if k.endswith("ttl_s"):
                        needed.add(k)
                elif pat in k:
                    needed.add(k)
        missing_keys = sorted([k for k in needed if k not in used_params and k not in ignore_appendix_keys])
        if missing_keys:
            err(
                "COVERAGE: Appendix A keys missing from TIME_FRESHNESS (freshness_param): "
                + ", ".join(missing_keys),
                errors,
            )

    # /status coverage enforcement
    def enforce_status(bucket_name: str, fields: set[str], ignore: set[str]):
        for f in sorted(fields):
            if f in ignore:
                continue
            if f not in covered_status:
                msg = f"/status field '{f}' is required (pattern {bucket_name}) but not covered by TIME_FRESHNESS entries"
                (err if args.strict else warn)(msg, errors if args.strict else warnings)

    enforce_status("ts_ms", status_fields["ts_ms"], ignore_status_ts)
    enforce_status("age", status_fields["age"], ignore_status_age)
    enforce_status("expires_at", status_fields["expires"], ignore_status_expires)
    enforce_status("lag_ms", status_fields["lag"], ignore_status_lag)
    enforce_status("p95/p99", status_fields["pxx"], ignore_status_pxx)
    enforce_status("count_window", status_fields["count_window"], ignore_status_count)
    enforce_status("ms_generic", status_fields["ms"], ignore_status_ms)

    # Appendix A time/freshness parameter coverage enforcement (strict ALWAYS enforces)
    appendix_table: Dict[str, str] = contract["appendix_table"]
    if appendix_table:
        # auto-detect time/freshness params by (unit in {sec, ms, hours, days}) and name contains substrings
        unit_ok = {"sec","ms","hours","days"}
        name_subs = ("ttl","stale","window","cooldown","max_age","retention","expires","drift","kill_s","lookback")

        detected = []
        for param, unit in appendix_table.items():
            u = unit.strip().lower()
            if u not in unit_ok:
                continue
            if any(s in param for s in name_subs):
                detected.append(param)

        for param in sorted(detected):
            if param in ignore_appendix_params:
                continue
            if param not in covered_appendix_params:
                msg = f"Appendix A time param '{param}' detected but not referenced by any TIME_FRESHNESS entry (freshness_param)"
                (err if args.strict else warn)(msg, errors if args.strict else warnings)
                continue

            ats = covered_appendix_params[param]["ats"]
            rts = covered_appendix_params[param]["runtime_ats"]

            if len(ats) == 0 and param not in ignore_appendix_no_at:
                msg = f"Appendix A time param '{param}' has no acceptance_tests coverage via TIME_FRESHNESS entries"
                (err if args.strict else warn)(msg, errors if args.strict else warnings)

            if len(rts) == 0 and param not in ignore_appendix_no_runtime:
                msg = f"Appendix A time param '{param}' has no runtime_acceptance_tests coverage via TIME_FRESHNESS entries"
                (err if args.strict else warn)(msg, errors if args.strict else warnings)

    # Output
    if warnings and args.strict:
        errors.extend([f"STRICT-WARN: {w}" for w in warnings])
        warnings = []

    if errors:
        print("FAIL:", file=sys.stderr)
        for e in errors[:200]:
            print(" -", e, file=sys.stderr)
        if len(errors) > 200:
            print(f" ... ({len(errors)-200} more)", file=sys.stderr)
        return 1

    if warnings:
        print("WARNINGS:")
        for w in warnings:
            print(" -", w)
    print("OK: time/freshness spec checks passed.")
    return 0

if __name__ == "__main__":
    raise SystemExit(main())
