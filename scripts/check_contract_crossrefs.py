#!/usr/bin/env python3
"""
Mechanical cross-reference checker for CONTRACT.md.

Checks:
- §section references resolve to real headings
- Heading IDs are unique
- "Appendix A default/see Appendix A" references mention known Appendix A config keys
- (Optional) AT-### references resolve to defined AT blocks

Exit codes:
0 = pass (no errors)
2 = errors found
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Dict, List, Set, Tuple


@dataclass(frozen=True)
class Finding:
    severity: str  # "ERROR" | "WARN"
    code: str
    line: int
    message: str
    context: str


HEADING_ID_RE = re.compile(
    r'^\s{0,3}#{1,6}\s+(?:\*\*)?'
    r'(?P<id>\d+(?:\.(?:\d+|[A-Za-z]))*)'
    r'(?:\*\*)?'
)
SECTION_REF_RE = re.compile(r'§\s*(\d+(?:\.(?:\d+|[A-Za-z]))*)')
SEE_SECTION_REF_RE = re.compile(r'\bsee\s+§\s*(\d+(?:\.(?:\d+|[A-Za-z]))*)', re.IGNORECASE)

AT_ID_RE = re.compile(r'\bAT-(\d{1,4})\b')
BACKTICK_TOKEN_RE = re.compile(r'`([A-Za-z_][A-Za-z0-9_]*)`')
ASSIGN_TOKEN_RE = re.compile(r'\b([a-z][a-z0-9_]{2,})\s*=')

# Tokens that often appear near Appendix A refs but are NOT config keys
NON_CONFIG_ALLOWLIST = {
    "slippage_bps", "risk_state", "trading_mode", "policy_age_sec",
    "rate_limit_session_kill_active", "too_many_requests",
}


def read_lines(path: Path) -> List[str]:
    return path.read_text(encoding="utf-8", errors="replace").splitlines()


def index_headings(lines: List[str]) -> Dict[str, List[int]]:
    headings: Dict[str, List[int]] = {}
    for i, line in enumerate(lines, start=1):
        m = HEADING_ID_RE.match(line)
        if m:
            hid = m.group("id")
            headings.setdefault(hid, []).append(i)
    return headings


def find_appendix_a_start(lines: List[str]) -> int:
    for i, line in enumerate(lines):
        if re.search(r'^\s*##\s+\*\*Appendix A:', line):
            return i
    return -1


def index_appendix_a_keys(lines: List[str]) -> Set[str]:
    """
    Build a set of candidate config keys from Appendix A by collecting backticked tokens.
    We then filter to "config-ish" keys (lowercase + underscores).
    """
    start = find_appendix_a_start(lines)
    if start < 0:
        return set()

    raw: Set[str] = set()
    for line in lines[start:]:
        for m in BACKTICK_TOKEN_RE.finditer(line):
            raw.add(m.group(1))

    cfg: Set[str] = set()
    for tok in raw:
        if re.fullmatch(r'[a-z][a-z0-9_]+', tok) and '_' in tok:
            cfg.add(tok)
    return cfg


def extract_line_tokens(line: str) -> Set[str]:
    toks: Set[str] = set()
    for m in BACKTICK_TOKEN_RE.finditer(line):
        toks.add(m.group(1))
    for m in ASSIGN_TOKEN_RE.finditer(line):
        toks.add(m.group(1))
    return toks


def check_section_refs(lines: List[str], headings: Dict[str, List[int]], include_bare_refs: bool) -> List[Finding]:
    findings: List[Finding] = []

    # Duplicate heading IDs
    for hid, locs in headings.items():
        if len(locs) > 1:
            findings.append(Finding(
                severity="WARN",
                code="DUPLICATE_HEADING_ID",
                line=locs[1],
                message=f"Heading id '{hid}' appears multiple times at lines {locs}.",
                context=lines[locs[1]-1].strip()[:160],
            ))

    # Reference extraction
    for i, line in enumerate(lines, start=1):
        refs: List[str] = []
        for m in SEE_SECTION_REF_RE.finditer(line):
            refs.append(m.group(1))
        if include_bare_refs:
            for m in SECTION_REF_RE.finditer(line):
                refs.append(m.group(1))

        for sid in refs:
            if sid not in headings:
                findings.append(Finding(
                    severity="ERROR",
                    code="MISSING_SECTION_TARGET",
                    line=i,
                    message=f"Reference to §{sid} has no matching heading id in CONTRACT.md.",
                    context=line.strip()[:200],
                ))
    return findings


def check_appendix_a_refs(lines: List[str], appendix_keys: Set[str], strict: bool) -> List[Finding]:
    findings: List[Finding] = []
    if not appendix_keys:
        findings.append(Finding(
            severity="ERROR",
            code="APPENDIX_A_NOT_FOUND",
            line=1,
            message="Appendix A heading not found; cannot validate Appendix A references.",
            context=lines[0].strip()[:160] if lines else "",
        ))
        return findings

    trigger_re = re.compile(
        r'(see Appendix A|default.*Appendix A|defaults.*Appendix A|Appendix A\))',
        re.IGNORECASE,
    )

    for i, line in enumerate(lines, start=1):
        if "Appendix A" not in line:
            continue
        if not trigger_re.search(line):
            continue

        toks = extract_line_tokens(line)
        toks = {t for t in toks if t not in NON_CONFIG_ALLOWLIST}

        # Which tokens look like actual config keys?
        resolved = {t for t in toks if t in appendix_keys}
        unresolved_candidates = {
            t for t in toks
            if re.fullmatch(r'[a-z][a-z0-9_]+', t) and '_' in t and t not in appendix_keys
        }

        if resolved:
            continue

        # If we found plausible config-like tokens but none exist in Appendix A => warn/error
        if unresolved_candidates:
            sev = "ERROR" if strict else "WARN"
            findings.append(Finding(
                severity=sev,
                code="APPENDIX_A_KEY_NOT_FOUND",
                line=i,
                message=(
                    "Appendix A referenced but keys not found in Appendix A: "
                    f"{sorted(unresolved_candidates)}"
                ),
                context=line.strip()[:220],
            ))
        else:
            # Could not infer which param this line is trying to default
            findings.append(Finding(
                severity="WARN",
                code="APPENDIX_A_REF_AMBIGUOUS",
                line=i,
                message=(
                    "Appendix A referenced, but no recognizable config key found on this line "
                    "(tighten wording or add backticks)."
                ),
                context=line.strip()[:220],
            ))

    return findings


def check_at_refs(lines: List[str], strict: bool) -> List[Finding]:
    """
    Optional: ensure AT-### references exist as definitional blocks somewhere in the contract.
    Heuristic: treat a line starting with 'AT-###' as a definition.
    """
    findings: List[Finding] = []
    defined: Set[str] = set()
    referenced: List[Tuple[int, str]] = []

    for i, line in enumerate(lines, start=1):
        m = re.match(r'^\s*AT-(\d{1,4})\b', line)
        if m:
            defined.add(m.group(1))

        for m2 in AT_ID_RE.finditer(line):
            referenced.append((i, m2.group(1)))

    for line_no, at_id in referenced:
        if at_id not in defined:
            sev = "ERROR" if strict else "WARN"
            findings.append(Finding(
                severity=sev,
                code="AT_REFERENCE_NOT_DEFINED",
                line=line_no,
                message=f"AT-{at_id} referenced but no definitional 'AT-{at_id}' block line found.",
                context=lines[line_no-1].strip()[:200],
            ))

    return findings


def render(findings: List[Finding], as_json: bool) -> str:
    if as_json:
        payload = [finding.__dict__ for finding in findings]
        return json.dumps(payload, indent=2, sort_keys=True)

    if not findings:
        return "PASS: no cross-reference issues found."

    out: List[str] = []
    for f in findings:
        out.append(f"{f.severity} {f.code} @L{f.line}: {f.message}\n  ↳ {f.context}")
    return "\n\n".join(out)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--contract", default="specs/CONTRACT.md", help="Path to CONTRACT.md")
    ap.add_argument("--strict", action="store_true", help="Treat Appendix A key misses / AT undefined as ERROR")
    ap.add_argument(
        "--include-bare-section-refs",
        action="store_true",
        help="Also validate any '§X' references, not just 'see §X'",
    )
    ap.add_argument(
        "--check-at",
        action="store_true",
        help="Also validate AT-### references resolve to definitional AT blocks",
    )
    ap.add_argument("--json", dest="json_out", action="store_true", help="Emit JSON instead of text")
    ap.add_argument("--out", default="", help="Write output to this path as well as stdout")
    args = ap.parse_args()

    path = Path(args.contract)
    if not path.exists():
        print(f"ERROR: contract file not found: {path}", file=sys.stderr)
        return 2

    lines = read_lines(path)
    headings = index_headings(lines)
    appendix_keys = index_appendix_a_keys(lines)

    findings: List[Finding] = []
    findings += check_section_refs(lines, headings, include_bare_refs=args.include_bare_section_refs)
    findings += check_appendix_a_refs(lines, appendix_keys, strict=args.strict)
    if args.check_at:
        findings += check_at_refs(lines, strict=args.strict)

    output = render(findings, as_json=args.json_out)
    print(output)

    if args.out:
        Path(args.out).write_text(output + "\n", encoding="utf-8")

    has_error = any(f.severity == "ERROR" for f in findings)
    return 2 if has_error else 0


if __name__ == "__main__":
    raise SystemExit(main())
